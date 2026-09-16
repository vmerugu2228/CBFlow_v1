# Production Git Setup — gpg-encrypted SSH deploy keys

How to give a production Linux host commit + pull access to the CBflow
GitHub repo without leaving a plaintext credential on disk.

The design at a glance:
- Two GitHub **deploy keys** for the repo: one read-only, one read-write.
- Each SSH private key is symmetrically gpg-encrypted with a team
  passphrase. Only the `.gpg` blob lives on production.
- `cbflow-git-unlock` decrypts the right key in memory and loads it into
  the user's ssh-agent. The decrypted bytes never hit disk.
- Read-only key: distribute widely (anyone who pulls).
  Read-write key: distribute narrowly (the commit user, plus a backup).

Trust model: a user who has both the encrypted blob **and** the gpg
passphrase can read the repo (RO key) or push to it (RW key). Either
half alone is useless.

---

## 1. One-time key generation

Run on any trusted machine with `ssh-keygen` and `gpg`. Do **not** run on
the production box directly — keep the unencrypted private keys off the
production filesystem entirely.

```bash
# Generate the two deploy keypairs.
# -N "" leaves the SSH key itself unencrypted; the gpg layer is the only
# protection. (You can add a passphrase here for defense-in-depth — the
# script supports it but ssh-add will prompt twice.)
ssh-keygen -t ed25519 -C "cbflow-prod-ro@$(date +%Y%m%d)" -f cbflow_ro -N ""
ssh-keygen -t ed25519 -C "cbflow-prod-rw@$(date +%Y%m%d)" -f cbflow_rw -N ""

# Encrypt the PRIVATE halves. gpg prompts interactively for the passphrase
# — pick one strong passphrase per key, communicated out-of-band (e.g.,
# pulled from your password manager, dictated over a video call, never
# pasted into chat or email).
gpg --symmetric --cipher-algo AES256 --output cbflow_ro.gpg cbflow_ro
gpg --symmetric --cipher-algo AES256 --output cbflow_rw.gpg cbflow_rw

# Wipe the plaintext private halves. The public halves stay (.pub).
shred -u cbflow_ro cbflow_rw
ls -1
# Expected: cbflow_ro.gpg cbflow_ro.pub cbflow_rw.gpg cbflow_rw.pub
```

## 2. Register the public halves on GitHub

For the repo (e.g. `vmerugu2228/CBFlow_v1`):
- `Settings → Deploy keys → Add deploy key`
- Title: `cbflow-prod-ro` — paste `cbflow_ro.pub`. **Leave "Allow write
  access" unchecked.**
- Add another: Title `cbflow-prod-rw` — paste `cbflow_rw.pub`. **Check
  "Allow write access".**

GitHub will refuse to add the same public key on two repos unless they
belong to the same organization. If you need the keys across multiple
repos, switch to organization-level deploy keys or use a machine user.

## 3. Deploy the encrypted blobs to production

On the production host, as root (or via sudo):

```bash
# Group containing every user who should be able to *pull*.
sudo groupadd -f cbflow

# Optional tighter group containing only commit users.
sudo groupadd -f cbflow-committers

# Drop the encrypted blobs.
sudo install -d -m 750 -o root -g cbflow /etc/cbflow/git
sudo install -m 640 -o root -g cbflow            /path/to/cbflow_ro.gpg /etc/cbflow/git/
sudo install -m 640 -o root -g cbflow-committers /path/to/cbflow_rw.gpg /etc/cbflow/git/
```

Result:
```
/etc/cbflow/git/
├── cbflow_ro.gpg   640 root:cbflow             ← everyone in cbflow can read
└── cbflow_rw.gpg   640 root:cbflow-committers  ← only committers
```

Switch the production checkout's remote from HTTPS to SSH:

```bash
git -C /path/to/CBflow_v1 remote set-url origin git@github.com:vmerugu2228/CBFlow_v1.git
git -C /path/to/CBflow_v1 remote -v
# origin git@github.com:vmerugu2228/CBFlow_v1.git (fetch)
# origin git@github.com:vmerugu2228/CBFlow_v1.git (push)
```

## 4. Per-user setup (everyone who'll touch the repo)

The user only needs to be a member of the right group:

```bash
sudo usermod -a -G cbflow            <username>          # pull access
sudo usermod -a -G cbflow-committers <username>          # also push access
# User must log out + back in for the new group to take effect.
```

`cbflow-git-unlock` ships in `PD/bin/` and is on PATH if the user
sourced the standard CBflow env.

## 5. Daily workflow

### Pull users

```bash
cbflow-git-unlock          # prompts ONCE for the RO passphrase
# (the agent now holds the key for 8 hours — see CBFLOW_GIT_KEY_TTL)
cd /path/to/CBflow_v1
git pull origin main       # no prompt
```

### Commit user

```bash
cbflow-git-unlock --write  # prompts ONCE for the RW passphrase
cd /path/to/CBflow_v1
git add ...
git commit -m "..."        # the commit-msg hook adds a Committed-On: trailer
git push origin main       # no prompt
```

### Helpful flags

```bash
cbflow-git-unlock --status   # show the agent socket + loaded keys
cbflow-git-unlock --lock     # clear everything from the agent (end-of-session)

# Custom paths / TTL via env
CBFLOW_GIT_KEY_DIR=/opt/cbflow/keys cbflow-git-unlock --write
CBFLOW_GIT_KEY_TTL=3600 cbflow-git-unlock                # 1 hour
CBFLOW_GIT_KEY_TTL=0    cbflow-git-unlock                # until ssh-agent dies
```

## 6. Commit attribution

The deploy key has no GitHub identity, so commits show up as the local
`user.name` / `user.email`. Each user MUST set their own:

```bash
git config --global user.name  "Varun Reddy"
git config --global user.email "varun@yourorg.com"
```

For audit, the `prepare-commit-msg` hook installed by
`cbflow-git-unlock --write` also stamps:

```
Committed-On: prod-host-01 (user=varun uid=1234)
```

into every commit. `git log --format='%(trailers)'` shows the full
trail. This is the answer to "who ran git commit on which host?" when
the GitHub identity is a shared deploy key.

## 7. Rotation procedure

Rotate the RW key annually, or immediately on any suspected compromise:

1. Generate a new keypair locally (step 1 above), encrypted with a
   **new** passphrase.
2. Add the new public key to GitHub deploy keys with write access.
3. Distribute the new `.gpg` blob to production:
   `sudo install -m 640 -o root -g cbflow-committers cbflow_rw_new.gpg /etc/cbflow/git/cbflow_rw.gpg`
4. Announce the new passphrase out-of-band.
5. After a grace window (so anyone with the old passphrase has switched),
   delete the old deploy key from GitHub. Old `.gpg` blobs become inert
   even if a copy leaks — they no longer match a registered key.

RO key rotation is the same procedure with the RO group + RO passphrase.

## 8. Revocation

To kill access for a single user without rotating the whole key:

```bash
sudo gpasswd -d <user> cbflow
sudo gpasswd -d <user> cbflow-committers
# The user can no longer read /etc/cbflow/git/*.gpg.
# Existing ssh-agent sessions still hold the key in memory; either:
#   - kill the user's ssh-agent processes, or
#   - wait for the TTL to expire (default 8h).
```

To kill access for everyone (e.g., key suspected compromised):

```bash
# On GitHub, delete the deploy key. All further pushes/pulls fail
# instantly, regardless of who holds the .gpg blob or its passphrase.
# Then rotate per section 7.
```

## 9. Verification (run after setup)

```bash
# 1. Pull works without a prompt.
cbflow-git-unlock
git -C /path/to/CBflow_v1 fetch origin
ssh-add -D
git -C /path/to/CBflow_v1 fetch origin
# ↑ MUST prompt now (no key in agent) — proves the agent was the only source.

# 2. Push works for the committer.
cbflow-git-unlock --write
cd /path/to/CBflow_v1
git commit --allow-empty -m "audit: production push smoke"
git push origin main
git log -1 --format='%H %an <%ae>%n%(trailers)'
# ↑ should show the user's identity + Committed-On trailer.

# 3. No plaintext private keys on disk anywhere.
sudo find /etc/cbflow/git /home -name 'cbflow_r[wo]' -not -name '*.pub' -not -name '*.gpg' 2>/dev/null
# ↑ MUST be empty.

# 4. RO key cannot push.
cbflow-git-unlock           # loads RO
git commit --allow-empty -m "audit: RO push attempt"
git push origin main
# ↑ MUST fail with "Permission denied (publickey)" — proves RO/RW split.
```

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `gpg: decryption failed: Bad session key` | Wrong passphrase | Get the right one from your password manager. |
| `Permission denied (publickey)` on push | Loaded RO key instead of RW | `cbflow-git-unlock --lock && cbflow-git-unlock --write` |
| Helper says `encrypted key not readable` | User not in the right unix group | `sudo usermod -aG cbflow <user>`; log out + in. |
| Push hangs on first connection | Host key prompt | `ssh -T git@github.com` once to accept the host key. |
| Identities other than the deploy key get tried first | Personal SSH keys also in agent | The script writes a `~/.ssh/config` block pinning github.com to `IdentitiesOnly yes`. Verify with `grep -A5 cbflow-git-unlock ~/.ssh/config`. |
