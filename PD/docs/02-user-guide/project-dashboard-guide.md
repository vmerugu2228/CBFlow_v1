# Project Dashboard — User Guide

## What it is

A per-project web dashboard that aggregates milestone release records
across every design + phase in a project. Where the **per-run dashboard**
(`cbflow run dashboard`) shows the state of ONE run in detail, the
**project dashboard** shows *every release milestone that has ever been
signed off* for a project — one row per (design, phase, milestone).

Two dashboards. Different scope:

| Dashboard | Scope | Data source | CLI |
|---|---|---|---|
| Per-run | One `.race_*.db` per run | Live SQLite from race_engine | `cbflow run dashboard ...` |
| Project | Many milestones per project | `tracker.db` keyed on (block, phase, milestone) | `cbflow project-dashboard ...` |

## Starting a project dashboard

```bash
cbflow project-dashboard start --project bumblebee
```

- Runs in the background.
- Port is derived deterministically from the project name: `25000 + hash(project) % 2500`.
- Bound to localhost by default. Add `--public` to bind `0.0.0.0`.
- State directory: `~/.cbflow/project-dashboard/<project>/` (contains
  `dashboard.pid`, `dashboard.port`, `tracker.db`, `dashboard.log`).

Lifecycle:

```bash
cbflow project-dashboard status  --project bumblebee   # pid + port + row count
cbflow project-dashboard open    --project bumblebee   # launch in browser
cbflow project-dashboard logs    --project bumblebee   # tail the daemon log
cbflow project-dashboard restart --project bumblebee
cbflow project-dashboard stop    --project bumblebee
```

## Publishing milestones

Rows appear in the project dashboard when a run's release milestone
completes:

```bash
# from inside a run directory
cbflow run release --tag BTO
```

The release command writes a row into the project's `tracker.db` with:

- `block` — design name (e.g. `cpu_core`)
- `phase` — project phase (e.g. `LC1`, `P0`)
- `milestone` — release tag (e.g. `FP_EXIT`, `PLACE_EXIT`, `BTO`)
- `status` — `PASS` / `CONDITIONAL` / `UNKNOWN`
- `signoff_ratio` — fraction of the milestone's checklist that passed
- `released_at` — ISO timestamp

## Listing / unpublishing

```bash
cbflow project-dashboard list --project bumblebee                      # every row
cbflow project-dashboard list --project bumblebee --block cpu_core     # filter
cbflow project-dashboard unpublish --project bumblebee \
    --block cpu_core --phase LC1 --milestone BTO                       # remove one row
```

## API endpoints

The daemon speaks JSON on the same port:

- `GET /api/list` — every published milestone row
- `GET /api/floorplan` — hierarchical block layout (uses `project(design_hierarchy)`)
- `GET /api/summary` — counts by status × milestone
- `GET /` — HTML view

## When to use it

- Executive / program-management view of a whole project's release state.
- Quick "which block is at which milestone with what confidence" glance.
- Feed CI dashboards that need to know when a block passed a milestone.

## When NOT to use it

- Debugging a single run — use per-run dashboard (`cbflow run dashboard`).
- Watching a run execute — the project dashboard only updates when
  `cbflow run release` fires. Use per-run dashboard for live progress.

## See also

- [`dashboard-daemon-guide.md`](dashboard-daemon-guide.md) — per-run dashboard
- [`release-management.md`](release-management.md) — how `cbflow run release` populates milestones
