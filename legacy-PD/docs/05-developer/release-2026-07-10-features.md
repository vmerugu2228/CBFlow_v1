# Release 2026-07-10 — Feature Notes

Complete developer-facing changelog for what shipped this cycle. Grouped
by subsystem so it's easy to hand off to whoever maintains each area.

## 1. STA scenario dispatch inlined

**Files:** `PD/cmds/STA/synopsys/pt/v1.0.0/timing_subnode_handler.tcl`, `PD/cmds/STA/cadence/tempus/v1.0.0/timing_subnode_handler.tcl`

The prior consolidation had deleted `timing_scenario_pt.tcl` /
`timing_scenario_handler.tcl` but left dangling references in the timing
subnode handler's `dynamic` and `default` branches. Real (non-test) STA
runs would crash for PT and silently skip scenarios for Tempus.

Both handlers now:
- Inline the per-scenario tool-command generation (Tempus's `default`
  branch already did this; extended PT to match).
- Self-invoke via `tclsh [info script] <scenario> <run_dir> <node>` from
  the `dynamic` branch to iterate scenarios (matches how race_engine
  expands per-scenario subnodes at build time).
- Relax the "scenario not found in analysis_views" hard error to a
  test-mode-tolerant stub path — production runs still fail loudly.

## 2. Post-cascade config validation

**Files:** `PD/utils/commands/config_validator.py` (new), `PD/config/flow/v1.0.0/flow_config.tcl`, `PD/utils/commands/race_engine.py`, `PD/utils/commands/validation_cmd.py`

- New `config_validator.assert_mandatory_vars(cfg, flow_type)` runs
  right after `_resolve_config()` in `RaceEngine.build()`.
- `flow_config.tcl` declares `flow(mandatory_vars,all)` (cross-flow) and
  `flow(mandatory_vars,<FLOW>)` (per-flow) — every listed key must be
  non-empty in the resolved cascade, else `ConfigError` with every
  missing key named at once.
- `cbflow workspace validate` also runs the same check per registered
  run — pre-flight for CI.
- Resolver schema bumped v2 → v3 to include `flow(mandatory_vars,*)`
  emissions.

## 3. Handler consolidation

**Files:** `PD/utils/utilities/v1.0.0/handler_common.tcl` (+148 lines), 133 subnode handlers under `PD/cmds/`

- New procs in `handler_common.tcl`:
  - `handler_dispatch` — the standard `setup / run / validate / finish`
    switch that ~117 handlers open-coded.
  - `handler_dispatch_inputs` — the multi-arm dispatch used by inputs
    handlers (`setup` / `<input_type>` / `validate` / `finish`).
  - `handler_resolve_inputs` — wraps `resolve_flow_inputs`.
- Every migrated standard handler reduces from ~50 lines to ~10:
  ```tcl
  source ".../handler_common.tcl"
  source ".../launch_utils.tcl"
  lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
  handler_load_configs $run_dir "<FLOW>"
  ...
  handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                   $cmd_file $test_mode $_tool
  ```
- Net: ~4400 lines removed from `PD/cmds/`, uniform handler shape across
  the whole framework.
- Not migrated (intentional): STA `timing_subnode_handler.tcl` (custom
  scenario dispatch), STA `extraction_subnode_handler.tcl` (custom rc\_\*
  dynamic subnodes), 2 large custom inputs handlers (`PNR/innovus/*`
  607 lines, `SYNTH/genus/*` 920 lines).

## 4. Smarter dashboard polling

**Files:** `PD/utils/dashboard/race_dashboard.py`, `PD/utils/dashboard/static/adaptive_poll.js` (new), `PD/utils/dashboard/templates/{dashboard,grid,dag}.html`, `PD/utils/commands/cbflow_config.py`

- `race_dashboard.py`:
  - `_db_etag()` — sha1 of DB `mtime_ns + size`. 16-hex-char.
  - `_json_response_cached()` — replaces `_json_response` for the four
    status endpoints (`/api/status`, `/api/dag`, `/api/jobs`,
    `/api/run-summary`). Sends `ETag`; honors `If-None-Match` → `304`.
  - `run_activity` field added to `/api/status`: `"active"` iff any
    RUNNING/PENDING job, else `"idle"`.
- `adaptive_poll.js`:
  - Self-tuning loop. **2 s active / 10 s idle** by default (override
    per-page via `window.__cbfAdaptiveInterval`).
  - Piggybacks a lightweight `/api/status` probe (ETag-cached; 304 most
    of the time) to keep activity signal fresh.
  - Wired into `dashboard.html`, `grid.html`, `dag.html` — falls back to
    fixed `setInterval` if the helper failed to load.
- `cbflow_config._mtimes()` now watches framework-level
  `flow_config.tcl` + `<FLOW>_config.tcl` mtimes in addition to
  user_config / runtime_flow_config. The long-lived dashboard daemon
  now picks up framework config edits without a restart.

## 5. DAG rendering rewrite

**File:** `PD/utils/dashboard/templates/dag.html`

- Replaced the flat left-to-right chain layout with real topological
  columns: `level(stage) = max(level(dep) for dep in stage_deps[stage]) + 1`.
- Bezier arrows drawn from `stage_deps` (real dependencies), not
  consecutive-position edges.
- Diamond intermediates (a stage with one parent P and one child C
  where P also directly gates C) are offset vertically so the
  bypass branch is visually distinct.
- Bypass edges (the direct P→C when a longer P→…→C branch exists) render
  dashed light gray so the primary chain reads as dominant.

## 6. Project dashboard module

**Files:** `PD/utils/project_dashboard/` (new package: `daemon.py`, `router.py`, `tracker_db.py`, `client.py`, `lifecycle.py`, `state_paths.py`, `floorplan.py`), `PD/utils/commands/project_dashboard_cmd.py`, `PD/bin/cbflow` (dispatcher entry)

Per-project milestone-rollup dashboard. See
[`../02-user-guide/project-dashboard-guide.md`](../02-user-guide/project-dashboard-guide.md)
for the user-facing surface. Key implementation notes:

- Port assignment deterministic: `25000 + hash(project) % 2500`.
- State directory: `~/.cbflow/project-dashboard/<project>/`.
- `tracker.db` schema: `(block, phase, milestone, status, signoff_ratio, released_at)` with `PRIMARY KEY (block, phase, milestone)`.
- Written by `cbflow run release --tag` inside a run directory.
- Read by the daemon's `/api/list`, `/api/summary`, `/api/floorplan` routes.

## 7. PV flow expansion

**Files:** `PD/config/flow/v1.0.0/node_configs/PV_config.tcl`, `PD/cmds/PV/mentor/calibre/v1.0.0/*`, `PD/cmds/PV/synopsys/icv/v1.0.0/*`

Removed: `fill1`, `erc1`.

Added:

| Stage | Deps | Purpose | Reference tool call |
|---|---|---|---|
| `nettran1` | `netlist1` | Verilog → LVS-ready CDL | `v2lvs -lsp` |
| `merge_gds1` | `netlist1, def1, gds1` | Merge base + fill GDS | `calibredrv layout filemerge` |
| `fill_merge_gds1` | `merge_gds1` | Post-merge fill validation | `calibre -drc` (fill runset) |
| `decomp1` | `fill_merge_gds1` | Multi-patterning colorization | `calibre -mp -mp_colors N` |
| `decomp_merge_gds1` | `fill_merge_gds1, decomp1` | Signoff GDS assembly | `calibredrv layout filemerge -mp_runset` |
| `perc_ldl1` | `decomp_merge_gds1` | Latch-up / leakage PERC | `calibre -perc -ldl` |

Rewired: all check stages (`drc1`, `lvs1`, `perc1`, `perc_ldl1`, `xor1`)
now depend on `decomp_merge_gds1` instead of the old `fill1`. `lvs1`
retains its dep on `nettran1` (LVS needs the CDL).

## 8. Runset interface documentation

**Files:** `PD/config/flow/v1.0.0/node_configs/PV_config.tcl`, `PD/config/tech/{gf_22nm,gf_28nm,tsmc_5nm,tsmc_7nm}/v1.0.0/tech_config.tcl`

`PV_config.tcl` declares placeholders for every rule deck consumed by
the flow: `drc / lvs / perc / perc_ldl / fill / multi_patterning / xor`.

All 4 tech configs declare `tech(rules,*)` + `tech(spice,stdcell)` so
the ICV runset fallback chain has documented interface points:

```
Calibre (SVRF): pv(<stage>,runset) → pv(input,rule_deck_<stage>) → passthrough
ICV (RSL):      pv(<stage>,rule_deck) → tech(rules,<stage>) → pv(input,rule_deck_<stage>)
```

## 9. LSF coverage checks

**Files:** `PD/utils/commands/test_suite/static_checks.py`, `PD/utils/commands/test_suite/e2e_checks.py`, `PD/config/flow/v1.0.0/lsf_config.tcl`

Three new suite checks: **cat15**, **cat16**, **e2e19**. See
[`../03-reference/lsf-checks.md`](../03-reference/lsf-checks.md) for
details. Also: explicit `lsf(flow_mapping,PV,*)` entries for the 6 new
PV stages, and `lsf(flow_mapping,PV,erc)` removed.

## 10. Test-mode outputs generator

**File:** `PD/utils/utilities/v1.0.0/launch_utils.tcl`

`handler_run`'s test-mode fallback block previously only knew about the
original PV stages (`drc / lvs / fill / erc / perc / xor / merge_data`).
Extended with cases for `nettran`, `merge_gds`, `fill_merge_gds`,
`decomp`, `decomp_merge_gds`, `perc_ldl` so the standard e2e checks
(especially `e2e14_outputs_dir_nonempty`) stay green.

## 11. Dead-code purge

Deleted 9 files that were on disk but not wired into any active flow:

- 4 `fill_*` PV command/handler files (fill1 removed from DAG)
- 4 `erc_*` PV command/handler files (erc1 removed from DAG)
- 1 `PD/utils/utilities/v1.0.0/utils.tcl.backup`

## Verification

Full test suite executed against both projects:

```
Pass: 1816   Fail: 0   Skip: 122   Duration: 561 s
```

Broken down:

- 14 static categories (including new cat15 + cat16)
- 19 e2e checks × 12 flows × 2 projects (bumblebee + denali)
- Both tool chains (Cadence + Synopsys) exercised

## Areas explicitly NOT touched

- DB hygiene (schema versioning, migrations, timestamp normalization) —
  proposed in the initial audit but user deferred.
- Command file audits for other flows (SYNTH, PNR, ECO, etc.) — this
  release focused on PV. Their command files remain as before.
- LEC / CLP / EMIR flows — no changes.
