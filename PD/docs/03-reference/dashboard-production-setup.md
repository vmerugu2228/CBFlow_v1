# Production Dashboard Setup

How to make the CBflow dashboard reachable from a remote browser on a
production Linux box.

## Why the default doesn't "just work" remotely

The dashboard daemon binds to `127.0.0.1` by default — same host only.
This is intentional for security: on a shared production machine, you
don't want every user on the LAN poking at your run state without
opting in.

So out of the box:

- ✅ Localhost access works (`http://127.0.0.1:<port>/` on the prod box)
- ✅ SSH-tunneled access works (`ssh -L <port>:localhost:<port> prod`)
- ❌ Direct remote access (`http://prod-host:<port>/` from your laptop)
  fails — the daemon isn't listening on the network-facing interface.

Two ways to make remote access work — pick one based on your security
posture.

---

## Option A: SSH tunnel (recommended for tightly-restricted boxes)

Keep the default bind. Each user tunnels their own port forward:

```bash
# From your workstation (substitute the prod hostname + your username)
ssh -L 9001:localhost:9001 you@prod-host

# Now open this on your workstation:
#    http://127.0.0.1:9001/
# The traffic is tunneled through the existing SSH session.
```

Pros: no extra firewall config, traffic is encrypted, no daemon flags to
remember. Cons: every user needs their own tunnel command.

Find the right port to forward — it's per-user-deterministic:

```bash
# On the prod box:
ssh you@prod-host
cbflow dashboard status
# Look for the "port: NNNN" line.
```

---

## Option B: LAN-accessible (recommended for shared chip teams behind a firewall)

Bind the daemon to all interfaces. Anyone who can reach the prod box on
the port can use the dashboard.

```bash
# Start (or restart) the daemon with --public
cbflow dashboard restart --public

# Output now shows the LAN URL:
#   dashboard daemon started on http://prod-host:9001/
#     ⚠  bound to 0.0.0.0 — reachable from any host on the LAN.
```

Or, more conveniently, set the env var system-wide so users don't have
to remember the flag:

```bash
# /etc/environment or your team's shared shell profile
export CBFLOW_DASHBOARD_BIND_ADDR=0.0.0.0
```

Then `cbflow run gui` (default) and `cbflow dashboard start` (default)
will bind LAN-accessible automatically.

Pros: zero friction for users, works from any browser on the LAN. Cons:
**no authentication** — anyone who can route to `prod-host:<port>` can
view runs. Mitigations:
- Corporate firewall blocks the dashboard port range (9000–9999) at
  the perimeter.
- The dashboard is read-mostly: pulls run state from SQLite, no write
  surface beyond `register`/`deregister` (which require AF_UNIX
  control-socket access, i.e. local user only).

---

## Flag reference

```bash
# Either CLI accepts these:
cbflow run gui      --public         # Bind 0.0.0.0 (LAN-accessible)
cbflow run gui      --bind-addr 10.0.5.42    # Bind a specific NIC IP
cbflow dashboard start --public
cbflow dashboard start --bind-addr 0.0.0.0
cbflow dashboard restart --public    # Switch a running daemon to public

# Env override (no flag needed):
export CBFLOW_DASHBOARD_BIND_ADDR=0.0.0.0
```

Priority: `--bind-addr` > `--public` > `CBFLOW_DASHBOARD_BIND_ADDR` >
default `127.0.0.1`.

---

## Verify a production daemon is reachable

```bash
# On the prod box
cbflow dashboard status
# Expected output:
#   url:   http://prod-host:9001/
#   bind:  0.0.0.0  (LAN-accessible via http://<hostname>:9001/)

# Quick liveness check (from prod box, or any host that can reach it)
curl -sS -o /dev/null -w "%{http_code}\n" http://prod-host:9001/
# 200 = OK
# 7   = no route (curl's "couldn't connect")
# 28  = timeout (firewall is dropping you)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `http://prod-host:9001/` connection refused | Daemon bound to 127.0.0.1, you're hitting it from another host | `cbflow dashboard restart --public` |
| `http://prod-host:9001/` times out | Firewall is blocking the port | Either tunnel via SSH (Option A) or ask infra to allow port 9001 from your subnet |
| `cbflow dashboard status` shows the old URL after `--public` | Daemon wasn't restarted; old bind still in effect | Use `restart --public`, not `start --public` (start refuses if already running) |
| Hostname in URL doesn't resolve from your laptop | Short hostname relies on local DNS | Use the IP, or update DNS, or use `--bind-addr <fqdn-ip>` and then the URL will use whatever your `gethostname()` returns. |
| Browser opens then nothing loads | Browser launched but daemon bind is wrong | Check `cbflow dashboard status` — `bind: 127.0.0.1` means localhost-only |

---

## Two-discipline note

CBflow runs two daemons (PD on port `9000 + uid%500`, DFT on port
`9500 + uid%500`). The bind setting is per-discipline:

```bash
cbflow dashboard start --discipline PD  --public
cbflow dashboard start --discipline DFT --public
```

Or set `CBFLOW_DASHBOARD_BIND_ADDR=0.0.0.0` once — both daemons pick it
up from the env.
