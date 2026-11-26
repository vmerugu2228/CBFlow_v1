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
- `--project` is required; one daemon runs per project.
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
- PD exits publish **in phase order** (`MILESTONE_ORDER`, filtered by `project(phase_exits)`). A milestone is refused until every earlier exit of the phase is published for that block and phase. The release-time gate orders the other disciplines' exits by their own plan, `project(phase_exits,<DISC>)`.
- `--override` replaces an existing entry.

**Signoff runs** (STA / PV / LEC) publish as their own runs. They attach to the exit they verify, which must already be published. The block page lists them with Flow and Verdict columns; the verdict is the release's `metrics.rpt` Status.

## Pages

| Page | Route | Content |
|---|---|---|
| All projects | `/` | One card per project of `master_projects.json` (sibling daemons probed) |
| Project | `/project/<p>` | **Disciplines** section (one card per discipline) and **Project** section (Releases, Spec-to-GDS chain, Checklist, Schedule, Team tiles) |
| Discipline summary | `/project/<p>/<disc>` | Blocks and published runs of one discipline (`pd`, `dft`, `dv`, `rtl`); `/project/<p>/<disc>/block/<b>` per block |
| Run dashboard | `/dashboard/<DISC>` | Opens that discipline's run dashboard daemon, starting it when offline |
| Block | `/block/<b>` | Published runs per flow, signoff verdict pills |
| Published run | `/published/<id>` | Metrics, merged stage tables, per-scenario summary (STA timing, DRV, power), timing paths, routed-layout image, DEF viewer, checklist |
| Releases | `/project/<p>/releases` | Exit-centric release view (below) |
| Chain | `/project/<p>/chain` | Spec-to-GDS sign-off chain per phase × block (below) |
| Checklist | `/project/<p>/checklist` | Per-phase checklist with waivers |
| Schedule | `/project/<p>/schedule` | Phase overview, per-phase exit timetable, bottom-up block schedule |
| Team | `/project/<p>/team` | `team_config.tcl` (leads, owners) |

Every page refreshes itself every 5 minutes. A countdown at the left of the header shows the time left; click it to refresh now. The countdown pauses while the schedule is being edited.

### Project page — discipline cards

The Disciplines section has one card per discipline the project enables (`enabled_flows_by_discipline` in
`master_projects.json`), coloured with `flow(discipline_color,<DISC>)`:

- the number and names of the enabled flows,
- **● live** / **○ offline** — whether that discipline's run dashboard daemon is up for the project,
- **Summary →** (`/project/<p>/<disc>`) and **Run dashboard ↗** (`/dashboard/<DISC>`; starts the daemon if needed —
  per (discipline, project) on `flow(dashboard,project_port_base,<DISC>)`: PD 20000, DFT 21000, DV 22000, RTL 23000).

The Project section holds the cross-discipline tiles: Releases, Spec-to-GDS chain, Checklist, Schedule and Team.

### Spec-to-GDS chain

`project(signoff_chain,<phase>)` (global project config) lists a block's sign-off chain as ordered stages of
`<step> <release tag>` pairs (driven by `workarea/run_spec2gds.sh <block> <phase>`). The tile shows the current
(else latest) phase with a chain: steps released / total across the blocks that started it. The chain page shows
per phase a block × step matrix; a step is **done** when
`<release,path>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE` exists, and a done step released *before* a step of an
earlier stage is flagged **stale** (its inputs were re-released after it). A project without
`project(signoff_chain,<phase>)` shows "no project(signoff_chain,<phase>)". See the
[Spec-to-GDS guide](spec-to-gds-guide.md).

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
