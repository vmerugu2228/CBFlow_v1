# CBflow Dashboard Daemon — User Guide

**Version:** 2.1.1
**Date:** 2026-06-12
**Author:** CBflow Development Team

---

## Table of Contents

1. [What changed in v2.1.1](#1-what-changed-in-v211)
2. [Quick start](#2-quick-start)
3. [The daemon lifecycle](#3-the-daemon-lifecycle)
4. [The web UI](#4-the-web-ui)
5. [CLI reference](#5-cli-reference)
6. [State directory](#6-state-directory)
7. [SSH and remote access](#7-ssh-and-remote-access)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What changed in v2.1.1

In v2.1.0, every `cbflow run gui` spawned a **fresh foreground HTTP server** per run. With 5-10 active runs per user this caused:

- "Port already in use" errors
- "Firefox already running, but is not responding"
- 10 active runs = 10 server processes, 10 browser tabs, 10 file watchers

v2.1.1 replaces this with a **per-user daemon**: one HTTP server per user, deterministic port, stable URL, all runs share it.

| Before (v2.1.0) | After (v2.1.1) |
|---|---|
| One server per run | One server per user |
| Random port from hash | `9000 + (uid % 1000)` deterministic |
| Browser launches per run | One stable URL; browser reuses tabs |
| Dies when terminal closes | Persists across shells |
| Up to 200 concurrent ports | Always 1 port |

## 1a. What changed in the 2026-07-10 release

Three quality-of-life improvements landed on top of the v2.1.1 architecture:

### Adaptive polling with ETag support

`/api/status`, `/api/dag`, `/api/jobs`, and `/api/run-summary` now support
`ETag` / `If-None-Match`. The client-side `adaptive_poll.js` helper polls
faster while a run is active and slows down when it's idle:

| State | Interval |
|---|---|
| At least one job RUNNING or PENDING | **2 s** (dashboard.html), **3 s** (grid/dag) |
| All jobs terminal | **10 s** |
| After a network error | **15 s** back-off |

The activity signal is a new `run_activity` field on `/api/status`
(`"active"` / `"idle"`). Every request also uses `If-None-Match` — when the
DB hasn't changed since the last poll the server returns `304 Not Modified`
with no body, cutting bandwidth ~80% during idle windows.

### DAG rendering rewrite

`/dag` now renders a real topological layout instead of a flat left-to-right
chain:

- Stages are grouped into columns by their longest path from a root
  (`level(stage) = max(level(dep) for dep in stage_deps[stage]) + 1`).
- Arrows are cubic Bezier curves drawn from actual `stage_deps` entries
  (previously the renderer just drew a line between the i-th and (i+1)-th
  stage in `stage_order`).
- Parallel branches sit at the same column, stacked vertically.
- When one stage bypasses another via a longer path (e.g. `A → B → C` when
  `A → C` also exists), the bypass edge renders **dashed light gray** and
  the intermediate stage is nudged vertically so both branches are readable.

### Framework config-cache invalidation

Prior to this release, edits to `flow_config.tcl` or the per-flow
`<FLOW>_config.tcl` were invisible to the long-lived daemon until you
restarted it. The cascade cache now watches those files' mtimes in addition
to `user_config.tcl` / `runtime_flow_config.tcl`, so framework edits show
up on the next API call.

---

## 2. Quick start

```bash
# In any run directory
cd P0_run_SYNTH_PNR_test1

# Launch GUI — daemon auto-starts on first call
cbflow run gui

# Browser opens to http://127.0.0.1:9501/run/<run_id>/
# (port = 9000 + your uid % 1000)

# Register more runs from other terminals — daemon stays up
cd /other/area/P0_run_PNR_test1 && cbflow run gui --no-browser
cd /yet/another/P0_run_STA_test1 && cbflow run gui --no-browser

# See all your registered runs
cbflow dashboard list

# When you're done
cbflow dashboard stop          # optional — daemon is cheap to leave running
```

---

## 3. The daemon lifecycle

### Starting

The daemon **auto-starts** on first `cbflow run gui` invocation. You can also start it explicitly:

```bash
cbflow dashboard start                # detached
cbflow dashboard start --foreground   # foreground (debug)
cbflow dashboard start --port 9999    # override the deterministic port
```

### Status

```bash
cbflow dashboard status
# state:  running
# pid:    25083
# port:   9501
# url:    http://127.0.0.1:9501/
# runs:   5 active, 0 archived
```

Exit codes: `0` running, `3` stopped, `4` stale state detected.

### Stopping

```bash
cbflow dashboard stop                 # SIGTERM, waits 5s, then SIGKILL
cbflow dashboard restart              # stop + start
```

Stopping the daemon does **not** delete the run registry. When the daemon restarts, all previously-registered runs come back.

### Stale-state recovery

If the daemon crashes (kill -9, system reboot, etc.), the on-disk state files are stale. The next `cbflow dashboard start` automatically:

1. Checks if the recorded PID is still alive
2. If alive, checks if the process start-time matches (catches PID recycling)
3. Probes the recorded port
4. If anything is stale: logs the reason, cleans up, starts fresh

---

## 4. The web UI

### The banner

- **CBflow Dashboard** logo + **RACE ENGINE** pill
- Byline: "Developed by SmartSoc"
- Live stat tiles: **Active**, **Archived**, **Projects**, **Designs**, **PID**, **Port**
- **Projects chips**: one chip per project showing `project_name (active_run_count)`

### Register a run

There are three ways:

**A. Via CLI** (most common):

```bash
cd <run_dir>
cbflow run gui            # registers + opens browser
```

**B. Paste a path into the Register form** at the top of the UI:

```
/absolute/path/to/P0_run_<flow>_<run_name>
```

Click **Register**.

**C. Browse picker**:

1. Click **Browse** in the Register panel
2. The picker expands showing every run discovered under each project's `workarea_path` (parsed from `PD/config/project/<name>/v1.0.0/<name>_config.tcl`)
3. Grouped by `project / design`, sticky headers
4. Type into the input to filter live (matches project, design, name, path, flow type)
5. Click an unregistered row's **Register** button — adds to registry + auto-refreshes; already-registered rows show a green `REGISTERED` pill

### Runs table

- **Run** column: bold display name (basename of run_dir, e.g. `P0_run_SYNTH_PNR_test1`) with the run_id (`b29f00bea7fd`) as a small grey caption
- **Flow** column: color-coded chip per flow type (SYNTH purple, PNR blue, SYNTH_PNR indigo, STA green, LEC amber, CLP orange, PV red, EMIR dark red, FP cyan, FCFP teal, POPT violet, ECO slate)
- **Run dir**: monospace, muted color
- **Registered / Last seen**: human-readable relative time (`5m ago`, `2h ago`); hover for absolute ISO timestamp
- **Deregister** button per row, with confirm dialog

Live filter box on the right narrows by any substring (run_id, run name, flow, path).
Refresh button + 5-second auto-poll.

### Per-run pages

Click any run_id → opens `/run/<id>/` with the full per-run dashboard (stage pipeline, DAG, job grid, log viewer, MMMC scenarios). All the v2.0.0 dashboard features work; the daemon just routes them.

POST actions (run, retrace, bypass, force) preserve owner-uid checking — the daemon runs as your uid, so only your runs are mutable.

---

## 5. CLI reference

### Lifecycle

```bash
cbflow dashboard start [--port N] [--foreground]
cbflow dashboard stop
cbflow dashboard restart [--port N]
cbflow dashboard status
cbflow dashboard logs [--follow]
```

### Registry

```bash
cbflow dashboard list
cbflow dashboard register <run_dir>
cbflow dashboard deregister <run-or-id>
```

### Browser

```bash
cbflow dashboard open                 # open browser to index
cbflow dashboard open <run_dir>       # deep-link a specific run
cbflow dashboard open <run_id>        # same, by id
```

In SSH sessions: browser launch is skipped; instead prints the `ssh -L PORT:localhost:PORT user@host` tunnel command.

### `cbflow run gui` (modified)

```bash
cbflow run gui                        # default: daemon path
cbflow run gui --no-browser           # register, print URL, no browser
cbflow run gui --foreground           # legacy per-run server (back-compat)
cbflow run gui --foreground --port 9090  # legacy server on specific port
```

Passing `--port` without `--foreground` errors with a hint to use `cbflow dashboard start --port N`.

### `cbflow run clean`

```bash
cbflow run clean --confirm            # also deregisters from daemon (best-effort)
```

---

## 6. State directory

All daemon state lives under `~/.cbflow/dashboard/` (mode 0700, owner-only):

```
~/.cbflow/dashboard/
  dashboard.pid          # atomic O_EXCL pidfile
  dashboard.port         # port the daemon is listening on
  dashboard.start_ts     # for PID-recycling identity check
  dashboard.log          # daemon log
  control.sock           # AF_UNIX IPC socket (mode 0600)
  runs/<run_id>.json     # one file per registered run
  last_open.json         # 5-sec browser-launch dedup
```

Each `runs/<id>.json` is small:

```json
{
  "run_id": "b29f00bea7fd",
  "run_dir": "/Users/vmerugu/projects/CBflow_clone/workarea/cpu_core/P0_run_SYNTH_PNR_test1",
  "registered_at": "2026-06-11T14:19:28",
  "last_seen_at": "2026-06-11T15:31:38",
  "owner_uid": 501,
  "flow_type": "SYNTH_PNR",
  "project": "bumblebee",
  "design": "cpu_core",
  "phase": "P0",
  "tech": "gf_22nm",
  "archived": false
}
```

### Safe to delete?

- `~/.cbflow/dashboard/runs/<id>.json` — yes, deletes the registration (same as `cbflow dashboard deregister`)
- `~/.cbflow/dashboard/dashboard.{pid,port,start_ts,log}` — yes if daemon is stopped; daemon recreates on next start
- `~/.cbflow/dashboard/control.sock` — yes, daemon recreates

You can safely `rm -rf ~/.cbflow/dashboard/` when the daemon is stopped — your run dirs in `workarea/` are untouched.

---

## 7. SSH and remote access

The daemon binds **127.0.0.1 only** (not 0.0.0.0). For remote access from your laptop:

```bash
# On your laptop:
ssh -L 9501:localhost:9501 user@build-server

# Then open in your local browser:
http://127.0.0.1:9501/
```

The `cbflow dashboard open` command auto-detects SSH sessions (via `$SSH_CLIENT` / `$SSH_TTY` / `$SSH_CONNECTION` env vars) and prints the exact tunnel command instead of trying to launch a browser:

```
$ cbflow dashboard open
SSH session detected — not opening browser.
Tunnel:    ssh -L 9501:localhost:9501 $USER@build-server.acme.com
Then open: http://127.0.0.1:9501/
```

---

## 8. Troubleshooting

### "Port already in use" on `cbflow dashboard start`

The deterministic port `9000 + (uid % 1000)` is occupied by something else (not our daemon). Options:

- `cbflow dashboard start --port 9999` — override
- Find what's using it: `lsof -iTCP:9501 -sTCP:LISTEN`

### "Another dashboard daemon is already running"

Either:
- A real daemon is up — use `cbflow dashboard status` to see it
- Stale state from a crashed daemon — the next start auto-cleans, but you can force: `cbflow dashboard stop && cbflow dashboard start`

### Firefox shows the same URL twice

The daemon's URL is **stable across runs**. Firefox/Chrome reuses the tab if it's already open. If you see a duplicate tab, close one — both pointed at the same daemon URL.

### Run shows up but the per-run page is empty

Check `cbflow dashboard logs`. Likely causes:
- The run's SQLite DB doesn't exist yet (`cbflow run all` hasn't been called)
- The DB pointer file is stale (rebuild with `cd <run_dir> && cbflow run status`)

### Daemon doesn't start in SSH session

Common cause: `$HOME` resolves to a path that overflows AF_UNIX's 104-char limit. Check `len(~/.cbflow/dashboard/control.sock)`. Fix: shorten `$HOME` or set `CBFLOW_DASHBOARD_HOME` to a shorter path.

### Per-run dashboard shows "empty canvas"

This was a v2.1.0 bug fixed in v2.1.1. The page's JS calls absolute `/api/...` URLs which the daemon rewrites to `/run/<id>/api/...`. If you still see it after upgrading, run `cbflow dashboard restart` to ensure the new daemon picks up the rewritten templates.

### Old per-run servers from v2.1.0 still showing up

`cbflow dashboard list` only shows runs registered with the daemon. If you still have foreground `start_dashboard` processes from v2.1.0, kill them with `pkill -f race_dashboard.py`. The new daemon's port (9000-range) doesn't conflict with their hash-derived ports (10000-60000 range).
