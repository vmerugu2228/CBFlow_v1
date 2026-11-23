# SmartGrid (Project Dashboard) — User Guide

## What it is

SmartGrid is the per-project web dashboard. It aggregates every **published
release** across blocks, phases and exits of a project. The **per-run dashboard**
(`cbflow run gui` / `cbflow run dashboard`) shows the live state of one run.
SmartGrid shows what each block has *released*: metrics, checklists, timing,
floorplan and signoff verdicts.

| Dashboard | Scope | Data source | CLI |
|---|---|---|---|
| Per-run | One `.race_*.db` per run | Live SQLite from race_engine | `cbflow run gui`, `cbflow run dashboard ...` |
| SmartGrid | Published releases per project | `tracker.db` keyed on (block, phase, milestone, flow) | `cbflow smartgrid ...` |

## Starting SmartGrid

```bash
cbflow smartgrid start --project opensky
```

- It runs in the background.
- The port is derived from the user and project: `flow(smartgrid,port_base)` (25000) + `md5("<uid>:<project>") % flow(smartgrid,port_span)` (2500). For example, uid 501 + `opensky` gives 25890.
- It binds to `flow(smartgrid,bind_addr)` (`127.0.0.1`).
- State directory: `flow(smartgrid,state_dir)` = `~/.cbflow/project-dashboard/<project>/`.

These keys live in `global/config/flow/v1.0.0/flow_registry.tcl`.

Lifecycle:

```bash
cbflow smartgrid status  --project opensky
cbflow smartgrid open    --project opensky
cbflow smartgrid restart --project opensky
cbflow smartgrid stop    --project opensky
```

The legacy name `cbflow project-dashboard ...` still works and prints a rename notice.

## Publishing

A release is published from its run:

```bash
cbflow run release --from-run <run_dir> --publish [--node release_data2] [--override]
```

- Publishing is opt-in (`--publish`).
- A release node publishes automatically on finish when its form set `project(release,publish) true`. See the [Exit Release Guide](exit-release-guide.md#8-release-node-form-and-auto-publish).
- Every publish runs the milestone checklist on the run. Checks with no data are `NA`.
- Exits publish **in phase order**. A milestone is refused until every earlier exit of the phase is published for that block and phase.
- `--override` replaces an existing entry.

**Signoff runs** (STA / PV / LEC) publish as their own runs. They attach to the exit they verify, which must already be published. The block page lists them with Flow and Verdict columns; the verdict is the release's `metrics.rpt` Status.

## Pages

| Page | Route | Content |
|---|---|---|
| Project | `/project/<p>` | Discipline / block tiles, Releases, Checklist and Schedule tiles |
| Block | `/block/...` | Published runs per flow, signoff verdict pills |
| Published run | `/published/<id>` | Metrics, merged stage tables, per-scenario summary (STA timing, DRV, power), timing paths, routed-layout image, DEF viewer, checklist |
| Releases | `/project/<p>/releases` | Exit-centric release view (below) |
| Checklist | `/project/<p>/checklist` | Per-phase checklist with waivers |
| Schedule | `/project/<p>/schedule` | Phase overview, per-phase exit timetable, bottom-up block schedule |

Every page refreshes itself every 5 minutes. A countdown at the left of the header shows the time left; click it to refresh now. The countdown pauses while the schedule is being edited.

### Releases page

The page shows:

- a phase × exit overview
- per-phase rollups by exit and by level
- a **block × exit matrix**

Each matrix cell can show these elements:

- an **implementation chip**, marked ⚠ when the release is incomplete
- **signoff chips** coloured by verdict; a missing expected signoff shows as a dashed chip
- **variant chips**, such as `PV HIER`
- an **order** badge when the exit was released before an earlier exit of the phase (out-of-order flag)

`flow(release,signoff_flows)` in `flow_registry.tcl` decides which flows count as signoff:

```tcl
set flow(release,signoff_flows) {STA PV LEC CLP EMIR ECO POPT}
```

A signoff flow is counted against `release_tags(<exit>)` required_flows. The
remaining required flows are implementation alternatives: any one of them releases the exit.

### Checklist waivers

Every published checklist has a **Waive** column. On a FAIL row it opens a form:

- "waived by" is the account running SmartGrid.
- A justification is required.
- The expiry is limited by `global/config/exit/v1.0.0/waiver_config.tcl` (`max_waiver_duration_days 90`). `allow_bto_waivers false` / `allow_mto_waivers false` refuse those exits.

A waived row moves from FAIL to WAIVED and gets a revoke link. A BLOCKED checklist becomes CONDITIONAL when no blocking failure is left. Active waivers are re-applied when the cell is re-published.

API: `POST /api/published/<id>/waive` and `POST /api/published/<id>/unwaive`.

### Timing

- The "Timing by stage & corner" table has **Stage** and **Corner** filters.
- Path groups (R2R / I2R / R2O / I2O) show WNS / TNS / NVP per stage × corner.
- Slack is formatted with `flow(report,slack_digits)` decimals (default `3`). Tcl reports and SmartGrid share this setting.

### DEF viewer

- The DEF viewer resolves LEFs through the run's library-manager tag.
- It has cell selection, connectivity and keyboard shortcuts.
- The **IO pins** switch parses the DEF PINS on demand (`GET /api/floorplan/<id>/pins`). Pins are highlighted by direction, supplies are shown separately, and names appear when zoomed in.
- The std-cell layer of the floorplan payload is sampled to fit `flow(dashboard,floorplan_cells_max_bytes)` (default `12000000`). Macros are always kept.

### Schedule

The schedule is driven by `global/config/project/<proj>/<ver>/schedule_config.tcl`:

- `start_date` and `tapeout_date`
- `<phase>,<exit>` dates
- `block_lead_days`

The schedule page edits the file and writes a `.bak` backup first.

## Listing / unpublishing

```bash
cbflow smartgrid list --project opensky
cbflow smartgrid unpublish --project opensky --block gcd --phase P1 --milestone PRO_EXIT
```

## When to use it

- A program view of which block is at which exit, with signoff status.
- Reviewing released metrics, timing, layout and checklists without opening a run.

## When NOT to use it

- Watching a run execute. SmartGrid only updates on publish; use the per-run dashboard instead.

## See also

- [Exit Release Guide](exit-release-guide.md)
- [GUI User Guide](cbflow-gui-user-guide.md): per-run dashboard
- [Dashboard Daemon Guide](dashboard-daemon-guide.md)
