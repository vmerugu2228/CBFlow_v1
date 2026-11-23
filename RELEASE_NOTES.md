# CBflow Release Bundle

**Generated:** 2026-09-29
**Branch:** `cbflow_global`
**Test suite:** 1338 static PASS + 419 E2E PASS · 0 FAIL · 114 SKIP · 100% pass rate on runnable tests
**Coverage:** 12 PD flows × 2 projects (bumblebee + denali), 5 DFT flows + 7 DV flows scaffolded

## 2026-11-23 update — Open-source sky130 flow, exit releases, SmartGrid

About 116 commits since 2026-11-19. The docs are in `PD/docs/02-user-guide/`:
`opensource-flow-guide.md`, `exit-release-guide.md`, `project-dashboard-guide.md` (SmartGrid),
`library-manager-user-guide.md` and `cbflow-gui-user-guide.md` §15.

### Open-source RTL-to-GDS (sky130, project `opensky`)
- **Vendor `opensource`.** Select the tool with `<flow>(tool,name)`:
  - SYNTH `yosys`
  - FP and PNR `openroad`
  - STA `opensta` (OpenRCX + OpenSTA)
  - PV `magic` (KLayout DRC by default, Magic extract + Netgen LVS)
  - LEC `yosys`

  Tools run in a container through `global/bin/cbflow-oss`. Its subcommands are `<tool> <cmd> <log>`, `exec`, `check` and `gui`, and its environment variables are `CBFLOW_OSS_IMAGE`, `CBFLOW_OSS_PDK_ROOT`, `CBFLOW_OSS_MOUNTS`, `CBFLOW_OSS_MAGICRC` and `CBFLOW_OSS_ENGINE`.
- **Hierarchy.** DL3 `gcd`, `mac_array` → DL2 `ctrl_subsys`, `ai_subsys` → DL1 `opensky_chip`. Blocks are built bottom-up through library tags (OSS0 / OSS1 / OSS2). A run picks its tag with `project(lib_config_tag)`, which can be set in user_config.
- **Command files.** Restructured into flow procs: `load_design / <operation> / report / save_design`. SYNTH uses `read_design / synthesize / report / write_design / dft_insert`.
- **SYNTH features:**
  - DFT scan insertion: `project(dft,enable|max_chain_length|clock_mixing|scan_enable_pattern)`, with a scan SDC `<design>.scan.sdc`.
  - Clock gating: `synth(oss,clock_gating,enable|min_ffs)`, using `tech(<trk>,icg_cell|icg_scan_cell)`.
  - Multi-Vt: `project(vt_flavors)` with `oss_vt_dont_use` / `oss_pnr_dont_use`, shared with PNR.
  - Memory report: `synthesis_memory.rpt`.
- **SRAM macros.** Supported through the memory category: `tech(gds|cdl|verilog,memory)`, `tech(memory,lib_set_map|power_pins|ground_pins)`, the `leaf_mem` PDN (met5 pins), macros kept in synthesis, and LVS black boxes. The gcd P2 RTL uses two `sky130_sram_1kbyte_1rw1r_32x256_8`.
- **FP:**
  - `fp(oss,pins,region)`
  - `fp(oss,macro,blockage_sides)`: created after tapcell, clipped to rows, endcaps excluded
  - `fp(oss,macro,placement)` (`""` / `row` / explicit)
  - `fp(oss,fp,die_area)`
  - `project(pdn,enable)` power-grid switch
  - PNR reads the floorplan from the FP release.
- **STA:**
  - `sta(oss,sta,mode) flat|hier`: flat reads the descendant netlists and stitches SPEF per instance.
  - `parasitic_annotation.rpt`.
  - STA_SIGNOFF checks STA_0012 to STA_0015 (dont_use, dont_touch, unannotated and partially annotated nets).
  - DRV and power reports.
  - NVP and R2R/I2R/R2O/I2O path groups, also in PNR.
- **PV:**
  - `pv(oss,pv,mode) flat|hier`: hier empties the children for DRC and black-boxes them for LVS.
  - `pv(oss,drc,engine) klayout|magic`.
  - The PV release carries the checked GDS + CDL (`flow_input_handshake(PV,netlist_cdl)`).
  - PV runs on FP_EXIT, which now requires PV.

### Library manager
- `add --category block` takes the GDS/CDL from the sibling **PV** release. With `--pv-pending`, the PNR copy is used and `tech(block,<b>,pv_release) "PENDING"` is recorded.
- Block SPEFs are linked: `tech(block,<b>,spef,<rc>)`, `tech(block,<b>,spef_corners)`.
- Shared categories (memory/io/analog/ip) bundle the lef/gds/cdl/verilog views.
- `add` keeps `tech(corners)` for non-stdcell categories and honours `--lib-tag-root`.

### Exit releases
- **Layout.** `<release,path>/<phase>/<block>/<FLOW>/<tag>`. The tag defaults to the exit name, and the phase is always the run's phase.
- **The release exit follows the source stage** (`MILESTONE_STAGE_MAPPING`): place → PLACE_EXIT, cts_opt → CTS_EXIT, pro → PRO_EXIT, signoff → BTO. There are three ways to release an intermediate stage:
  - bypass
  - `cbflow run set-dep --node X --deps a,b [--reset]`
  - add-node `export_data2` + `release_data2`
- **Exit-named tags.** A tag can name another exit with the same source stage, e.g. MTO = BTO. `cbflow run release --from-run <run> --clone-from BTO --tag MTO` copies a finished release, and `--node <release node>` selects which release node to use.
- **Exit-order gates.** `check_exit_order` runs at release time and the SmartGrid gate runs at publish time. Both follow the per-phase order in `project(phase_exits)` and have no bypass. Publishing is opt-in (`--publish`).
- **Signoff flows read only their exit's release.** This is controlled by `<flow>(release,exit_from)` and `<flow>(release,exit_exempt_inputs)`.
- **Per-node overrides.** `override_config.tcl` → `.<stage>` → `.<branch>` → `.<node_type>` → `.<node>`. The flow-name level was removed.

### Run engine / CLI
- Bypass marker `work/<FLOW>/<node>/BYPASSED`.
- Added nodes inherit `runtime,timeout`.
- `flow(max_parallel_jobs)` (0 = unlimited).
- `workspace create` archives a stale RACE DB together with its `-wal` / `-shm`.
- Run names carry the block: `<phase>_run_<FLOW>_<block>_<run>`.
- Branches clone the selected node.

### Run dashboard (per-user daemon, PD port 9000 + uid % 300)
- Always-visible action bar.
- Multi-select with Shift+click and Shift+drag, plus bulk actions.
- MMMC dialog with a sticky Save bar and an All button.
- Release-node form: Save writes `setup/override_config.<node>.tcl`, and the node publishes on re-run.
- Set Dependencies… dialog.
- Runs table: Block, Total runtime and Age columns, sortable headers, running runs first.

### SmartGrid (`cbflow smartgrid start --project <p>`; port 25000 + md5(uid:project) % 2500)
- Published runs per flow, with signoff runs on their own pages.
- **Exit-centric releases page:**
  - block × exit matrix
  - implementation and signoff chips
  - `PV HIER` variants
  - out-of-order badge
  - signoff flows from `flow(release,signoff_flows)`
- Checklist waivers (`waiver_config.tcl`).
- DEF viewer IO-pins switch.
- Stage / corner filter on the timing table.
- Floorplan payload budget `flow(dashboard,floorplan_cells_max_bytes)`.
- WNS / TNS digits `flow(report,slack_digits)` (3).
- Schedule from `schedule_config.tcl`.
- 5-minute auto-refresh.

### Workarea / tooling
- **Scripts:**
  - `workarea/run_p1_dl3.sh` (PHASE / RUN / LIB_TAG / FROM / PUBLISH_OVERRIDE; per-phase RTL `inputs/opensky/<b>/<PHASE>/<b>.f`; `overrides/pnr_<PHASE>.tcl`)
  - `run_p1_dl2.sh` (FROM / UNTIL; `overrides/pnr_<PHASE>_dl2.tcl`)
  - `run_signoff.sh` (FLOWS / MAX_PARALLEL / PV_MODE / PUBLISH=1 / LIB_TAG)
  - `test_place_release.sh` (SRC=place1|cts_opt1)
  - `test_exit_order.sh`
- `cbflow-bundle` excludes run data (workarea run dirs / logs, `test_releases`, `.race_area`).
- **Test suite:** opt-in static category 18 "hardcode" (`cbflow test --hardcode`, `hardcode_scan.py`).

---

## 2026-09-29 update — Launch-mode defense stack

Fixes the "run silently completes clean without actually running EDA" failure
mode that surfaces when `flow(use_xterm) "true"` was set but xterm was missing
or `$DISPLAY` unset (async fire-and-forget `exec xterm ... &`), or when
`flow(use_lsf) "true"` was set but `bsub` wasn't installed. Three independent
gates now guard against silent test-mode fallthrough:

1. **Pre-flight at `workspace create`** (`start_run.py::_preflight_launch_bins`).
   Errors out before the DAG is built if `flow(use_lsf)="true"` and `bsub` is
   not in PATH, or `flow(use_xterm)="true"` and `xterm` is not in PATH. The
   partial run directory is auto-cleaned so the user can fix and re-run.

2. **Runtime sync-exec in submit_job** (`launch_utils.tcl::submit_job` xterm
   branch). Removed the trailing `&` that made xterm fire-and-forget — the
   handler now waits for xterm to exit and catches non-zero exit codes.
   Also validates `$DISPLAY` is set and the launch wrapper is executable
   before invoking xterm.

3. **Post-run validation** (`handler_common.tcl::handler_validate`, production
   mode only). Previously a silent no-op that printed "validation passed"
   without checking anything. Now enforces two contracts:
   - Every path in `<flow>(mandatory_outputs,<stage>)` exists and is non-empty
   - The stage's `outputs/` directory has at least one file

   Either violation fails the validate subnode with exit 1 and names the
   missing artifact.

   Test-mode (`flow(test_mode) "true"`) short-circuits before any of the new
   checks, so the E2E suite is unaffected. Verified: 12/12 PD flows all
   still pass, 590 jobs exit-0.

Launch-mode variables — three booleans controlled via `user_config.tcl`:

```tcl
set flow(test_mode) "false"    # real EDA (set "true" to skip tool execution)
set flow(use_lsf)   "false"    # local exec (set "true" to submit via bsub)
set flow(use_xterm) "true"     # xterm windows (set "false" for silent local exec)
```

Defaults live in `global/config/flow/v1.0.0/flow_registry.tcl:97-99` —
`test_mode=false`, `use_lsf=false`, `use_xterm=true`. Env-var overrides
(`CBFLOW_USE_LSF`, `CBFLOW_USE_XTERM`, `CBFLOW_BSUB_CMD`) still work; user_config
wins when both are set.

---

**E2E job execution:** 590 stages+subnodes across 19 flow×project combinations, all exit-0

## Headline

`cbflow_global` is a multi-discipline refactor of CBflow — what was a
PD-only automation framework now hosts Physical Design (PD), Design-For-Test
(DFT), and RTL Design Verification (DV) as first-class sibling disciplines.
Every cross-domain concept — tech identity, project hierarchy, MMMC
scenarios, the flow catalog, the CLI launcher — lives in a shared `global/`
layer that all three disciplines source before layering their own overlay.

Existing PD workareas keep running byte-identically; the change is
purely structural underneath.

---

## What changed for users

### 1. New kickoff — `bin/cbflow` at the repo root

The main launcher moved from `PD/bin/cbflow` to `global/bin/cbflow`, with
a top-level convenience symlink at `bin/cbflow`. Both invocation forms work.

```bash
# Universal (recommended)
bin/cbflow workspace create --config user_config.tcl
bin/cbflow run all
bin/cbflow flow types

# Backwards compatible — every existing .run.cbflow.tcl reference to
# PD/bin/cbflow still resolves (via a compat symlink).
PD/bin/cbflow workspace status
```

**Only one env var is user-facing:** `CBFLOW_ROOT` — the repo root. Every
other `CBFLOW_*` (`CBFLOW_CORE_DIR`, `CBFLOW_GLOBAL_DIR`, `CBFLOW_DFT_DIR`,
`CBFLOW_DV_DIR`) is auto-derived by the launcher. In most installs you
export nothing — just run `bin/cbflow`.

`bin/cbflow --version` prints the full derivation chain so you can see
exactly what `CBFLOW_*` resolved to.

### 2. Discipline-specific launchers

Each discipline now has its own bin/ housing subcommands specific to that
discipline:

- **`PD/bin/cbflow-pd`** — owns `flow library-manager`, `flow mmmc-manager`,
  `flow checklist` (PD exit milestones: FP_EXIT / PLACE_EXIT / CTS_EXIT /
  PRO_EXIT / BTO / MTO)
- **`DFT/bin/cbflow-dft`** — extension point (no unique subcommands yet)
- **`DV/bin/cbflow-dv`** — extension point (no unique subcommands yet)

Auto-dispatch: typing `cbflow flow library-manager …` from anywhere
forwards to `PD/bin/cbflow-pd` via the map in
`global/config/cli/discipline_commands.tcl`. Users can also call the
discipline launcher directly. Any subcommand a discipline launcher
doesn't own falls through to `global/bin/cbflow`.

### 3. Domain-aware `cbflow flow` commands

`cbflow flow types` now groups by discipline and supports `--domain`:

```
$ bin/cbflow flow types
  Total: 24 flow types  (PD=12, DFT=5, DV=7)

$ bin/cbflow flow types --domain PD          # PD flows only
$ bin/cbflow flow types --domain DFT         # DFT flows only
$ bin/cbflow flow types --domain DV          # DV flows only
```

The version banner also shows the discipline roster (each discipline
tagged `[+]` if the directory exists on disk).

### 4. RACE DB now created at `workspace create` time

Previously the RACE status DB was lazy-initialized on first
`cbflow run all`, leaving a window where the run directory existed on
disk with no owning DB. `cbflow workspace create` now hard-fails if the
DB can't be initialized, and every valid run directory has a
`.race_db_pointer` file immediately after creation.

DB naming: `<run_dir_name>_<username>_<hash>.db` — the username segment
was always intended but recently confirmed working.

### 5. MMMC + process-corner improvements

- `mmmc-manager` backup files now go into `<config_dir>/backup/` with
  timestamped names instead of `.bak` sidecars next to the source.
- Extended process-corner family support: process names like `fff`
  (very-fast-fast), `sss`, and other multi-letter variants correctly
  classify to slow/fast/typical roles via suffix matching, no longer
  falling through to the 2-letter hardcoded `{ss, tt, ff}` dict.

### 6. Netlist / input linkage fixed for release_tag mode

Fixtures declaring per-input release-tag markers like
`sta(input,netlist_release_tag) "P0_BTO"` now correctly resolve to the
release-directory path before staging. Fixed three stacked bugs:

- `resolve_flow_inputs` only checked the generic `<flow>(input,release_tag)`
  key — per-input markers were silently ignored.
- `resolve_from_tag` sourced `release_config.tcl` only when the release
  base path was empty, leaving `flow_input_handshake` unloaded in the
  common case.
- `handler_load_configs` (called before every input handler) sourced
  flow/node/user/tool_launch configs but not the project configs — so
  `project(release,path)` was undefined at resolve time.

---

## Repository layout after the refactor

```
CBflow_clone/                             $CBFLOW_ROOT (the umbrella)
├── bin/                                  → global/bin/ (top-level symlinks)
├── global/                               cross-discipline configs + launcher
│   ├── bin/
│   │   ├── cbflow                        universal launcher
│   │   ├── cbflow-flow                   subcommand router (auto-dispatches to disciplines)
│   │   ├── _cbflow_paths.sh              shared path resolver
│   │   └── cbflow-{run,workspace,bundle,migrate,test,…}
│   └── config/
│       ├── master_projects.json          schema 2.0: enabled_flows_by_discipline
│       ├── cli/discipline_commands.tcl   subcommand → discipline map
│       ├── flow/v1.0.0/
│       │   ├── flow_registry.tcl         flow(types), flow(discipline,*), cross-domain runtime defaults
│       │   └── descriptions_config.tcl
│       ├── tech/<node>/v1.0.0/tech_config.tcl        foundry data (identity/VT/rules/SPICE/RCX)
│       └── project/<name>/v1.0.0/
│           ├── project_config.tcl        identity + hierarchy + tapeout + dft/verif params
│           ├── mmmc_config.tcl, mmmc_node_scenarios.tcl, mmmc_view_definition.tcl
│           └── team_config.tcl
├── PD/                                   $CBFLOW_CORE_DIR — Physical Design
│   ├── bin/{cbflow,cbflow-pd}
│   ├── config/
│   │   ├── tech/<node>/v1.0.0/tech_pd_config.tcl     PD overlay: metal stacks + cells + body bias
│   │   ├── project/<name>/v1.0.0/project_pd_config.tcl  PD overlay: workarea + release + lsf
│   │   ├── flow/v1.0.0/{flow_config,release_config,lsf_config,…}
│   │   └── exit/v1.0.0/                              exit-milestone checklist configs
│   ├── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/           PD stage handlers
│   └── utils/{commands,utilities,core,dashboard,…}
├── DFT/                                  $CBFLOW_DFT_DIR
│   ├── bin/cbflow-dft
│   ├── config/flow/v1.0.0/{flow_config, node_configs}
│   └── cmds/{ATPG,DFT_INSERT,SCAN_INSERT,GLS_FUNC,GLS_SCAN_MBIST}/
└── DV/                                   $CBFLOW_DV_DIR
    ├── bin/cbflow-dv
    ├── config/flow/v1.0.0/{flow_config, node_configs}
    └── cmds/{LINT,CDC,RDC,SIM,COV_MERGE,FORMAL,UPF_CHECK}/  (skeleton)
```

## Config cascade (source order per run)

Every run — via `cbflow run all` or ad-hoc `tclsh` — resolves configs in
this fixed order. Project is sourced first because tech references
`$project(lib_root)`.

1. `global/config/project/<proj>/v1.0.0/project_config.tcl` — identity + hierarchy
2. `PD/config/project/<proj>/v1.0.0/project_pd_config.tcl` — PD overlay
3. `global/config/tech/<tech>/v1.0.0/tech_config.tcl` — foundry base
4. `PD/config/tech/<tech>/v1.0.0/tech_pd_config.tcl` — PD overlay
5. `global/config/flow/v1.0.0/flow_registry.tcl` — cross-domain runtime defaults
6. `<discipline>/config/flow/v1.0.0/flow_config.tcl` — routed by `flow(discipline,$flow_type)`
7. `<discipline>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl`
8. `global/config/project/<proj>/v1.0.0/mmmc_config.tcl` — MMMC PVT
9. `<run>/setup/user_config.tcl` — user overrides (last writer wins)

---

## Verification results

### Static suite (1425 checks across 16 categories)
- **1338 PASS · 0 FAIL · 87 SKIP** — 100% of runnable checks pass

### End-to-end suite (419 test-suite checks)
- **419 PASS · 0 FAIL · 27 SKIP** across all runnable flow×project combos

### Actual job execution (RACE DBs)

**Every PD flow validated across both projects (where fixtures exist):**

| Flow       | bumblebee | denali |
|------------|-----------|--------|
| SYNTH      | 18/18 ✓  | 18/18 ✓ |
| FP         | 30/30 ✓  | 30/30 ✓ |
| FCFP       | 65/65 ✓  | (no fixture) |
| PNR        | 49/49 ✓  | 49/49 ✓ |
| SYNTH_PNR  | 53/53 ✓  | 53/53 ✓ |
| STA        | 27/27 ✓  | 27/27 ✓ |
| LEC        | 13/13 ✓  | 13/13 ✓ |
| CLP        | 13/13 ✓  | 13/13 ✓ |
| PV         | 63/63 ✓  | (no fixture) |
| EMIR       | 19/19 ✓  | (no fixture) |
| POPT       | 23/23 ✓  | (no fixture) |
| ECO        | 14/14 ✓  | (no fixture) |
| **Total**  | **387/387** | **203/203** |

**590 total jobs (172 stages + 418 subnodes), zero failures.**

---

## Backwards compatibility

- Every existing `.run.cbflow.tcl` file continues to work. The stamped
  `CBFLOW_CORE_DIR` env var still points at `PD/`, and `PD/bin/cbflow`
  remains a valid entry point (symlink to `global/bin/cbflow`).
- Every existing user_config.tcl format works unchanged.
- Every existing tool handler under `PD/cmds/<FLOW>/…` works unchanged.
- The `legacy-PD/` snapshot at the repo root preserves the pre-refactor
  tree byte-identically for rollback (`rm -rf PD global DFT DV && mv legacy-PD PD`).

## Migration for existing installs

None required for PD users. Existing workareas keep working. New
capabilities (DFT / DV scaffolds, per-discipline launchers) are opt-in.

## Files touched (high-level)

- **New:** `global/` tree (bin + config), `PD/bin/cbflow-pd`,
  `DFT/bin/cbflow-dft`, `DV/bin/cbflow-dv`, `DV/config/flow/v1.0.0/`
  (7 node_configs), `DV/cmds/*/README.md`, `_cbflow_paths.sh`,
  `discipline_commands.tcl`
- **Moved (git mv, history preserved):** all launchers from `PD/bin/` to
  `global/bin/`; DFT node_configs from `PD/config/flow/…/node_configs/` to
  `DFT/config/flow/…/node_configs/`; `mmmc_*.tcl`, `team_config.tcl`,
  `descriptions_config.tcl`, `master_projects.json` from `PD/config/` to
  `global/config/`
- **Split:** each tech's `tech_config.tcl` into `global/…/tech_config.tcl`
  (foundry) + `PD/…/tech_pd_config.tcl` (metal + cells); each project's
  `<project>_config.tcl` into `global/…/project_config.tcl` (identity) +
  `PD/…/project_pd_config.tcl` (workarea/release/LSF)
- **Cascade + routing:** `config_resolver.tcl` reorders to source project
  before tech, routes flow_config to the right discipline via
  `flow(discipline,$flow)`, sources tech/project halves from the correct
  layer; `paths.py::get_node_config_path()` and
  `race_engine._build_command()` route to the discipline root
- **Test-suite:** `_INPUT_PSEUDO_STAGES` extended to cover DFT + DV
  inputs; cat14 (read/write parity) walks `global/config/` too
