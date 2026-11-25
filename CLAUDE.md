# CBflow Multi-Discipline Design Automation Framework

## What is CBflow
CBflow v2.0.0 is a multi-discipline design automation framework. It coordinates 32 flows across four disciplines — Physical Design (PD, 12 flows), Design-For-Test (DFT, 7 flows after the 2026-11-03 pass split), RTL Design Verification (DV, 9 flows), and RTL design-side quality (RTL, 4 flows) — through a Python-native RACE DAG execution engine, SQLite status tracking, web GUI dashboard, and per-scenario MMMC parallelism.

## Supported Flows
- **PD**  — SYNTH, PNR, SYNTH_PNR, FP, FCFP, STA, LEC, CLP, PV, EMIR, POPT, ECO
- **DFT** — DFT_INSERT_PASS1 (Core: MBIST+BSCAN), DFT_INSERT_PASS2 (Top: TDR/DFT-Signals/SRI), DFT_INSERT_PASS3 (EDT+OCC), SCAN_INSERT, ATPG, GLS_FUNC, GLS_SCAN_MBIST
- **DV**  — SPEC_RAMP, PLANNING, TB_SETUP, M1_EXEC, M2_EXEC, M3_EXEC, M4_EXEC, ECO_EXEC, DV_SIGNOFF
- **RTL** — RTL_LINT (Spyglass / Jaspergold HAL), RTL_CDC (Spyglass CDC / Jaspergold CDC), RTL_RDC (Spyglass RDC / Jaspergold RDC), UPF_CHECK (VC-LP / Conformal LP)

PD flows support dual tools (Synopsys: FC/PT/Formality/ICV/RedHawk + Cadence: Innovus/Genus/Tempus/Conformal/Voltus/Calibre) plus an **open-source** vendor on sky130 (`opensource`: yosys SYNTH/LEC, OpenROAD FP/PNR, OpenSTA STA, KLayout/Magic+Netgen PV — see "Open-Source Flow" below). DFT + DV scaffolds ship with node_configs; discipline-specific tool handlers extend from there. RTL ships with real Spyglass command emission for RTL_LINT; CDC/RDC/UPF_CHECK Synopsys handlers are scaffolded.

## Repository Layout (post cbflow_global refactor)

Umbrella root + one directory per discipline + one shared `global/` layer:

```
CBflow_clone/                             $CBFLOW_ROOT
├── bin/                                  Top-level launcher symlinks → global/bin/
├── global/                               Cross-discipline layer — sourced by every run
│   ├── bin/
│   │   ├── cbflow                        Universal launcher
│   │   ├── cbflow-flow                   Flow subcommand router (auto-dispatches to discipline)
│   │   ├── _cbflow_paths.sh              Shared path resolver
│   │   ├── cbflow-oss                    Open-source tool container launcher (docker)
│   │   └── cbflow-{run,workspace,bundle,migrate,test,…}
│   ├── utils/
│   │   ├── commands/                     Python: race_engine, run_cmd, workspace_cmd, start_run, config_resolver, test_suite/
│   │   ├── utilities/v1.0.0/             TCL: utils.tcl, resolve_inputs.tcl, release_utils.tcl, handler_common.tcl, oss_utils.tcl
│   │   ├── core/                         paths.py, env.py, release_exits.py, …
│   │   ├── generation/v1.0.0/            generate_setup.tcl (config.tcl / setup.tcl per node)
│   │   ├── dashboard/                    Run dashboard (per-user daemon)
│   │   ├── project_dashboard/            SmartGrid
│   │   └── validation/v1.0.0/checks/     Exit check scripts
│   └── config/
│       ├── master_projects.json          Project registry (schema 2.0: enabled_flows_by_discipline)
│       ├── cli/discipline_commands.tcl   Subcommand → discipline map
│       ├── flow/v1.0.0/
│       │   ├── flow_registry.tcl         flow(types), flow(discipline,*), cross-domain runtime defaults
│       │   └── descriptions_config.tcl
│       ├── exit/v1.0.0/                  Exit milestone + STA_SIGNOFF checklist configs, waiver_config.tcl
│       ├── tech/<node>/v1.0.0/
│       │   └── tech_config.tcl           Foundry data + metal stack + physical cells (PD overlay merged in)
│       └── project/<name>/v1.0.0/
│           ├── <proj>_config.tcl         Identity + hierarchy + phases/phase_exits + dft params
│           ├── schedule_config.tcl       SmartGrid schedule (optional)
│           ├── mmmc_config.tcl           MMMC PVT building blocks
│           ├── mmmc_node_scenarios.tcl   Per-node setup/hold scenario assignments
│           ├── mmmc_view_definition.tcl  Auto-generated MMMC library sets + views
│           └── team_config.tcl
├── PD/                                   $CBFLOW_CORE_DIR — Physical Design discipline
│   ├── bin/
│   │   ├── cbflow                        Compat symlink → global/bin/cbflow
│   │   └── cbflow-pd                     PD-only launcher (library-manager, mmmc-manager, checklist)
│   ├── config/
│   │   ├── project/<name>/v1.0.0/
│   │   │   └── <proj>_pd_config.tcl      PD overlay: workarea_path + release,* + lsf,* + lib_root, lib_tag_root, lib_config_tag
│   │   ├── flow/v1.0.0/
│   │   │   ├── flow_config.tcl           PD mandatory_vars + node_config dispatch
│   │   │   ├── release_config.tcl        Release exits × phases, flow handshake, MILESTONE_STAGE_MAPPING
│   │   │   ├── lsf_config.tcl            LSF queues (XS/S/M/L/XL/ultra)
│   │   │   ├── dir_config.tcl            Directory structures per flow
│   │   │   ├── tool_launch_config.tcl    Tool shell + module load
│   │   │   ├── validation_config.tcl     Validation contracts
│   │   │   ├── ml_config.tcl             ML analytics
│   │   │   └── node_configs/
│   │   │       ├── <FLOW>_config.tcl         Stages, deps, subnodes, node_types, MMMC, runtime
│   │   │       └── <FLOW>_<tool>_config.tcl  Tool-specific app settings (incl. *_yosys/_openroad/_opensta/_magic)
│   │   └── setup/                        flow_proc hook files (common / project)
│   ├── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/  PD stage command files + subnode handlers (vendor opensource included)
│   └── utils/commands/                   Python: library_manager, node_manager, checklist, mmmc_manager, …
├── DFT/                                  $CBFLOW_DFT_DIR
│   ├── bin/cbflow-dft                    DFT launcher (skeleton — extension point)
│   ├── config/flow/v1.0.0/
│   │   ├── flow_config.tcl               DFT mandatory_vars + node_config dispatch
│   │   └── node_configs/                 DFT_INSERT_PASS1/2/3, SCAN_INSERT, ATPG, GLS_FUNC, GLS_SCAN_MBIST
│   └── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/  DFT tool handlers (Tessent, DFT Compiler, TestMax, VCS, Questa)
├── DV/                                   $CBFLOW_DV_DIR
│   ├── bin/cbflow-dv                     DV launcher (skeleton — extension point)
│   ├── config/flow/v1.0.0/
│   │   ├── flow_config.tcl               DV mandatory_vars + node_config dispatch
│   │   └── node_configs/                 SPEC_RAMP, PLANNING, TB_SETUP, M1-M4_EXEC, ECO_EXEC, DV_SIGNOFF
│   └── cmds/<FLOW>/                      DV tool handlers (skeleton)
└── RTL/                                  $CBFLOW_RTL_DIR
    ├── bin/cbflow-rtl                    RTL launcher (skeleton — extension point)
    ├── config/flow/v1.0.0/
    │   ├── flow_config.tcl               RTL mandatory_vars + node_config dispatch
    │   └── node_configs/                 RTL_LINT, RTL_CDC, RTL_RDC, UPF_CHECK (+ per-tool overlays)
    └── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/  RTL handlers (Spyglass, Jaspergold, VC-LP, Conformal LP)
```

## Kickoff — Environment Setup

**Only `CBFLOW_ROOT` is user-facing.** Every other CBFLOW_* var is auto-derived.

```
CBFLOW_ROOT         Umbrella install root — the ONLY var you might export
CBFLOW_CORE_DIR     Auto: $CBFLOW_ROOT/PD
CBFLOW_GLOBAL_DIR   Auto: $CBFLOW_ROOT/global    (cross-domain config layer — sourced first)
CBFLOW_DFT_DIR      Auto: $CBFLOW_ROOT/DFT       (exported only if directory exists)
CBFLOW_DV_DIR       Auto: $CBFLOW_ROOT/DV        (exported only if directory exists)
CBFLOW_RTL_DIR      Auto: $CBFLOW_ROOT/RTL       (exported only if directory exists)
```

`CBFLOW_ROOT` is the anchor, NOT `CBFLOW_GLOBAL_DIR`. `global/` is a subordinate of the root, alongside every discipline directory. `bin/cbflow --version` from anywhere shows the resolved chain.

### Optional env-var overrides

| Variable | Purpose | Default |
|---|---|---|
| `FLOW_CONFIG_VERSION` | config-schema version dir (`<disc>/config/flow/<ver>/…`) | `v1.0.0` (set by launcher) |
| `UTILITIES_VERSION` | utilities dir (`<disc>/utils/utilities/<ver>/…`) | `v1.0.0` (set by launcher) |
| `TECH_CONFIG_VERSION` | tech config dir | `v1.0.0` (set by launcher) |
| `PROJECT_CONFIG_VERSION` | project config dir | `v1.0.0` (set by launcher) |
| `CBFLOW_PROJECT_NAME` | active project for cascade resolve | from `project(name)` in config |
| `CBFLOW_FLOW_TYPE` | active flow for cascade resolve | from `flow(type)` in config |
| `CBFLOW_RUN_DIR` | run directory for a specific run | PWD when inside a run_dir |
| `CBFLOW_USE_LSF` | force-enable LSF submission | `flow(use_lsf)` from config |
| `CBFLOW_USE_XTERM` | force-enable xterm wrappers | `flow(use_xterm)` from config |
| `CBFLOW_BSUB_CMD` | override bsub binary / wrapper | `lsf(bsub,command)` from config |
| `CBFLOW_COLLECT_METRICS` | opt-in metrics collection at end of run | off |
| `CBFLOW_LSF_AUTO_CLEANUP` | automatic LSF resource cleanup on exit | off |
| `CBFLOW_LSF_MONITOR_AUTO` | auto-start LSF monitor thread | off |
| `CBFLOW_LSF_MONITOR_INTERVAL` | LSF monitor poll interval (seconds) | 60 |
| `CBFLOW_TOOL_VENDOR` / `_TOOL_NAME` / `_TOOL_VERSION` | override tool bindings for the current stage | from node_config |
| `CBFLOW_OSS_IMAGE` / `_PDK_ROOT` / `_MOUNTS` / `_MAGICRC` / `_ENGINE` | open-source tool container (`cbflow-oss`) | pinned image / `$HOME/eda/pdks` / — / sky130A magicrc / `docker` |
| Tool-version overrides (`TESSENT_VERSION`, `TEMPUS_VERSION`, `VOLTUS_VERSION`, `REDHAWK_VERSION`, `CONFORMAL_LP_VERSION`, `VC_LP_VERSION`, etc.) | override module-version per tool | `v1.0.0` or site-default |

## Config Cascade (order)

Every run resolves configs in this fixed order — project first because tech references `$project(lib_root)`:

1. `global/config/project/<proj>/v1.0.0/<proj>_config.tcl`      — identity + hierarchy + phases
2. `<disc>/config/project/<proj>/v1.0.0/<proj>_<disc>_config.tcl` — discipline overlays (own discipline last; PD: workarea, release, lsf, lib_root, lib tag)
3. `global/config/tech/<tech>/v1.0.0/tech_config.tcl`           — single tech file (the former PD tech_pd_config.tcl is merged in); the library tag's `lib_config.tcl` / `blocks_config.tcl` are sourced from it
4. `global/config/flow/v1.0.0/flow_registry.tcl`                — flow(types), discipline map, runtime defaults
5. `<discipline>/config/flow/v1.0.0/flow_config.tcl`            — routed by `flow(discipline,$flow_type)`
6. Node config `<discipline>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl` (+ `<FLOW>_<tool>_config.tcl` overlay from `<flow>(tool,name)`)
7. `global/config/project/<proj>/v1.0.0/mmmc_config.tcl`        — MMMC PVT building blocks
8. `<run>/setup/user_config.tcl`                                — user overrides
9. `<run>/setup/override_config.tcl` → `.<stage>` → `.<branch>` → `.<node_type>` → `.<node>` — per-node overrides (last writer wins; **no flow-name level**)

## Launcher Composition (per-discipline)

- **`bin/cbflow` → `global/bin/cbflow`** — universal launcher for cross-domain subcommands (workspace, run, bundle, migrate, test, flow types/info/stages/check, flow project, flow release, flow metrics, flow dashboard).
- **`PD/bin/cbflow-pd`** — PD-owned subcommands (`flow library-manager`, `flow mmmc-manager`, `flow checklist`). Auto-dispatched from `cbflow flow library-manager …` via `global/config/cli/discipline_commands.tcl`.
- **`DFT/bin/cbflow-dft`, `DV/bin/cbflow-dv`** — skeleton launchers, extension points for future discipline-specific tooling. Non-owned commands fall through to `global/bin/cbflow`.

Adding a new discipline-owned subcommand: (1) add to `discipline_commands.tcl`; (2) add to the discipline launcher's `<DISC>_FLOW_SUBCOMMANDS` array; (3) drop the Python handler at `<disc>/utils/commands/`.

## Launch Mode + Silent-Test-Mode Defense

Three booleans in `user_config.tcl` control how EDA tools run:

```tcl
set flow(test_mode) "false"    # real EDA (set "true" to skip tool execution)
set flow(use_lsf)   "false"    # local exec (set "true" to submit via bsub)
set flow(use_xterm) "true"     # xterm windows (set "false" for silent local exec)
```

Defaults live in `global/config/flow/v1.0.0/flow_registry.tcl:97-99`: `test_mode=false`, `use_lsf=false`, `use_xterm=true`. Env-var overrides (`CBFLOW_USE_LSF`, `CBFLOW_USE_XTERM`, `CBFLOW_BSUB_CMD`) still work; user_config wins when both are set.

Three independent gates guard against a run silently completing "clean" when the tool never actually ran (missing bsub, missing xterm, `$DISPLAY` unset, license unavailable, tool exit-0 with warnings-only failure):

1. **`start_run.py::_preflight_launch_bins`** — `workspace create` errors + cleans up partial run dir if `use_lsf=true`/bsub missing or `use_xterm=true`/xterm missing.
2. **`launch_utils.tcl::submit_job` (xterm branch)** — validates `$DISPLAY` + wrapper executable, runs xterm synchronously (removed fire-and-forget `&`), catches non-zero exit.
3. **`handler_common.tcl::handler_validate`** (production mode only) — enforces `<flow>(mandatory_outputs,<stage>)` exists+non-empty AND `outputs/` dir has ≥1 file. Test-mode short-circuits before these checks so the E2E suite is unaffected.

## Config Architecture

### Single Array Per Flow
Each flow uses ONE array: `synth_pnr()`, `synth()`, `pnr()`, `fp()`, `sta()`, `lec()`, `clp()`, `pv()`, `emir()`, `eco()`, `popt()`, `fcfp()`. No tool-specific arrays (`fc()`, `pt()`, `genus()`, etc.) — all merged into the flow array.

### Config Cascade (generated config.tcl per node)
project_init → project → team → tech → flow → node_common → node_tool → mmmc → user → overrides (`override_config.tcl` → `.<stage>` → `.<branch>` → `.<node_type>` → `.<node>`)

### Tech Config Structure
- Track-categorized libraries: `tech(<track>,ndm,stdcell)` + shared `tech(ndm,memory/io/analog)`
- Auto-build combined: `tech(<track>,ndm)` via foreach loop
- Per-RC-corner parasitics: `tech(rcx,<rc_corner>,<format>)` where format = tluplus/qrc/nxtgrd
- Physical cells: clock_buffers, clock_inverters, hold_buffers, delay_cells, icg_cells, power_switch, isolation, level_shifter, tie_cells, fillers, well_tap, endcap, decap

### Metal Stack Configuration
- Available stacks per technology: tech(metal_stacks_available)
- Active stack: project(metal_stack) in project_config
- Per-stack configs: config/tech/<node>/v1.0.0/metal_stack/<stack_name>.tcl
- Per-layer properties: direction, pitch, width, spacing, type (Qx/Cx/Jx/Mx)
- Auto-resolves: routing layers, TLU+/QRC paths, PG strap layers

### MMMC Auto-Generation
- PVT building blocks: `mmmc(pvt,ss)`, `mmmc(pvt,tt)`, `mmmc(pvt,ff)` + RC pairing rules
- Analysis views auto-generated: modes × corners × PVT points
- Scenario sets auto-filtered: setup, hold, signoff, all, power
- Operating modes define per-mode SDC: `operating_modes(func,constraint_file)`

### Node Config Split
- `<FLOW>_config.tcl` — common: stages, dependencies, subnodes (foreach loop), node_types, MMMC, runtime
- `<FLOW>_<tool>_config.tcl` — tool-specific: app settings, compile/place/cts/route options, required_inputs

### Exit Checklist System
- **21 milestones across 3 disciplines** (post 2026-11-03 refactor; RTL discipline added 2026-11-03 but ships without exit milestones yet — owner team adds them when sign-off cadence is defined):
  - **PD (6)**: FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO
  - **DFT (6)**: CORE_DFT_EXIT (Pass1 MBIST+BSCAN), TOP_DFT_EXIT (Pass2 TDR/SRI), EDT_OCC_EXIT (Pass3), SCAN_INSERT_EXIT, ATPG_PREPD_EXIT, ATPG_POSTPD_EXIT
  - **DV (9)**: SPEC_RAMP_EXIT, PLANNING_EXIT, TB_SETUP_EXIT, M1_EXIT, M2_EXIT, M3_EXIT, M4_EXIT, ECO_EXEC_EXIT, DV_SIGNOFF_EXIT
  - **RTL (0)**: planned — LINT_SIGNOFF, CDC_SIGNOFF, RDC_SIGNOFF, UPF_SIGNOFF per flow; configs land when owner team formalizes sign-off criteria
- Each milestone config declares `set milestone_info(discipline) "PD"|"DFT"|"DV"|"RTL"`; the CLI's `--discipline <X>` flag filters by owner.
- 182 PD library checks across 9 categories (timing, placement, clock, power, routing, physical, SI, manufacturing, eco_flow). DFT/DV milestones use mandatory_files + per-flow metric checks. RTL flows use violations_final.csv as the structured check carrier.
- **Phase-aware**: phases are **project-defined** via `set project(phases) {...}` in `global/config/project/<proj>/v1.0.0/<proj>_config.tcl`. Bumblebee uses LC1-LC5; other projects use P0-P3 or any custom scheme. Checks activate progressively as the project's declared phases advance.
- Check IDs: TMG-001, PLC-001, CLK-001, PWR-001, RTG-001, PHY-001, SI-001, MFG-001
- **Config: `global/config/exit/v1.0.0/`** (centrally declared; moved from PD/config/exit/ on 2026-11-03 because exit milestones are discipline-owned but centrally declared)
- Scripts: global/utils/validation/v1.0.0/checks/
- `STA_SIGNOFF` checklist (`global/config/exit/v1.0.0/STA_SIGNOFF_config.tcl`, checks STA_0001…STA_0015 incl. STA_0014 unannotated / STA_0015 partially annotated nets) publishes with every STA run
- Publish runs the milestone checklist (NA for checks with no data); SmartGrid waives FAIL rows (`waiver_config.tcl`: max 90 days, no BTO/MTO waivers)
- CLI: `cbflow flow checklist {list, list-checks, generate, status, sign-off, add-check, remove-check, waiver} [--discipline PD|DFT|DV|RTL]`
- Auto-detects milestone/phase/project from run directory

## CBflow Commands

### Workspace (from workarea/<design_name>/)
```bash
cbflow workspace create --config uc_SYNTH_PNR.tcl
cbflow workspace status
cbflow workspace list-runs
```
Note: workarea path enforced from `project(workarea_path)` in project_config

### Run (from run directory)
```bash
cbflow run all                    # Execute complete flow
cbflow run status --details       # Check progress
cbflow run retrace --from cts1    # Re-run from stage
cbflow run add-node --node place2 --type place --dep place1
cbflow run create-branch --branch timing_fix --from cts1
cbflow run release --tag PLACE_EXIT
cbflow run release --from-run . --node release_data1 --publish   # publish a self-released (open-source) run
cbflow run release-check --tag BTO --project bumblebee
cbflow run gui                    # Run dashboard (per-user daemon; PD port 9000 + uid%300)
cbflow run set-dep --node export_data1 --deps place1   # rewire a node (--reset restores base-node deps)
```
Run names: `<phase>_run_<FLOW>_<block>_<run>`. A fully bypassed stage gets `work/<FLOW>/<node>/BYPASSED`.
Added nodes inherit `runtime,timeout`. `flow(max_parallel_jobs)` caps local parallel jobs (0 = unlimited).
`workspace create` archives a stale RACE DB (with `-wal`/`-shm`) as `<db>.stale-<ts>`.

### Exit releases
Layout `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>`; phase = the run's phase
(`CBFLOW_PROJECT_PHASE`); tag = `project(release,tag)` else the exit name. Exits per phase:
`project(phase_exits)`; global order `MILESTONE_ORDER` (release_config.tcl). Gates (no bypass flag):
release time `::CBFlow::Release::check_exit_order` (earlier exits of the phase need RELEASE_COMPLETE;
skipped in test mode / signoff flows) and publish time (earlier exits must be on SmartGrid).
`cbflow run release` flags: `--tag --name --dry-run --from-run --node --clone-from --publish --no-publish --override`;
publishing is opt-in (`--publish`). Signoff flows (STA/PV/LEC) read only their exit's release:
`<flow>(release,exit_from)` names the exit input, `<flow>(release,exit_exempt_inputs)` (LEC `{netlist_golden}`)
lists exceptions; from_run / explicit paths / other tags are refused. Doc: `PD/docs/02-user-guide/exit-release-guide.md`.

### Releasing an intermediate stage (e.g. place → PLACE_EXIT)
The export/release pair releases its **source stage**: the nearest non-bypassed
implementation node upstream of the export node (`oss_source_node`). The
milestone follows it (place → PLACE_EXIT, cts_opt → CTS_EXIT, pro → PRO_EXIT,
signoff → BTO; else the phase's latest earlier exit). Any of:
1. Bypass the later stages: `cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1`
   then `cbflow run stage --name release_data1`.
2. Rewire export onto the stage: `cbflow run set-dep --node export_data1 --deps place1`
   (or right-click → Set Dependencies… in the run GUI), then run release_data1.
3. Add a pair under it: `add-node --node export_data2 --type export_data --dep place1`,
   `add-node --node release_data2 --type release_data --dep export_data2`,
   then run release_data2 (publish with `cbflow run release --from-run <run> --node release_data2 --publish`).

Releases before pro carry no SPEF; before signoff no timing models. `cts`/`route` have no exit
(error). Only the open-source PNR release applies the source-stage exit today.
`workarea/test_place_release.sh` (`SRC=place1|cts_opt1`) exercises all three.

### Releasing the same data as another exit (e.g. MTO = BTO)
1. Same run, new tag: set the release node's tag to MTO (run GUI release form → Save, i.e.
   `setup/override_config.release_data1.tcl: set project(release,tag) "MTO"`), then
   `cbflow run retrace --from release_data1 && cbflow run stage --name release_data1`.
   An exit-named tag sets the milestone when it maps to the same source stage (BTO / MTO →
   signoff); another stage's exit is refused.
2. Clone a release: `cbflow run release --from-run <run> --clone-from BTO --tag MTO [--publish]`
   — copies `<FLOW>/BTO` to `<FLOW>/MTO` (records CLONED_FROM), same-stage + exit-order checked.

### Checklist
```bash
cbflow flow checklist list                                    # Show all milestones
cbflow flow checklist list-checks --milestone BTO             # List checks for milestone
cbflow flow checklist generate --milestone PLACE_EXIT         # Generate checklist
cbflow flow checklist status --milestone BTO --run-dir .      # Check status
cbflow flow checklist sign-off --milestone BTO --run-dir .    # Sign off
cbflow flow checklist add-check --milestone BTO --check-id TMG-042  # Add custom check
cbflow flow checklist remove-check --milestone BTO --check-id TMG-042  # Remove check
cbflow flow checklist waiver --milestone BTO --check-id TMG-010 --reason "..."  # Waive check
```

### Database Management
```bash
cbflow run db-manage status                                   # Show DB location and size
cbflow run db-manage backup                                   # Backup current DB
cbflow run db-manage query --table jobs --status FAIL         # Query DB tables
cbflow run db-manage export --format csv                      # Export DB data
```

## Open-Source Flow (sky130, project `opensky`)
- Tool selection: `<flow>(tool,name)` → overlay `<FLOW>_<tool>_config.tcl` (vendor `opensource`):
  SYNTH `yosys`, FP/PNR `openroad`, STA `opensta` (OpenRCX + OpenSTA), PV `magic` (KLayout DRC default,
  `pv(oss,drc,engine)`; Magic extract + Netgen LVS), LEC `yosys` (not in `project(default_tools)` —
  set `lec(tool,name) "yosys"`). Per-stage binary `<flow>(oss,tool,<stage>)`; tool keys use `<flow>(oss,…)`.
- Tools run in docker via `global/bin/cbflow-oss <tool> <cmd> <log>` (`exec`, `check`, `gui openroad|klayout`).
- Command files `PD/cmds/<FLOW>/opensource/<tool>/v1.0.0/`: inline `flow_proc load_design / <op> / report /
  save_design` (+ gates check_drc / check_lvs / verdict); SYNTH `read_design / synthesize / report /
  write_design / dft_insert`. Helpers in `global/utils/utilities/v1.0.0/oss_utils.tcl`. Hook with
  `flow_proc_prepend/append` (a `flow_proc_replace` from setup.tcl is overwritten by the command file).
- Hierarchy DL3 gcd, mac_array → DL2 ctrl_subsys, ai_subsys → DL1 opensky_chip (`project(design_hierarchy)`).
  Children come from a library tag (`project(lib_config_tag)`, per run in user_config; tags OSS0/OSS1/OSS2
  under `project(lib_tag_root)`). `library-manager add --category block --path <rel>/<phase>/<b>/PNR/<exit>`
  takes GDS/CDL from the sibling PV release (`--pv-pending` → PNR copy, `tech(block,<b>,pv_release) "PENDING"`),
  links SPEFs (`tech(block,<b>,spef,<rc>)`, `spef_corners`); `--category memory` bundles lef/gds/cdl/verilog.
- SYNTH: `project(dft,enable|max_chain_length|clock_mixing|scan_enable_pattern)` (scan SDC `<design>.scan.sdc`),
  `synth(oss,clock_gating,enable|min_ffs)` with `tech(<trk>,icg_cell|icg_scan_cell)`, `project(vt_flavors)` →
  `oss_vt_dont_use` / `oss_pnr_dont_use`, `synthesis_memory.rpt`; SRAM macros kept (`tech(memory,lib_set_map|
  power_pins|ground_pins)`, `leaf_mem` PDN with met5 pins, LVS black boxes).
- FP: `fp(oss,fp,die_area|core_utilization)`, `fp(oss,macro,placement)` (""/row/explicit),
  `fp(oss,pins,constraints)` (per-group port regions), `fp(oss,probe,enable)` (probe1: quick GPL+GRT
  congestion estimate, nothing saved; floorplan skill `.claude/skills/floorplan/`),
  `fp(oss,macro,blockage_sides)` (after tapcell, clipped to rows minus endcaps), `fp(oss,pins,region)`;
  `project(pdn,enable)` false = no grid. PNR reads the floorplan via `pnr(input,def_file_release_tag) "FP_EXIT"`.
- STA: `sta(oss,sta,mode) flat|hier` (flat = descendant netlists + per-instance SPEF); per-scenario
  setup/hold/drv/dont_use/dont_touch/parasitic_annotation/power reports; NVP; path groups R2R/I2R/R2O/I2O.
- PV: `pv(oss,pv,mode) flat|hier` (hier = children emptied for DRC, black boxes for LVS); release carries
  checked GDS + CDL (`flow_input_handshake(PV,netlist_cdl)`); FP_EXIT requires PV.
- Workarea scripts (`workarea/`): `run_p1_dl3.sh` (PHASE/RUN/LIB_TAG/FROM/PUBLISH_OVERRIDE; RTL
  `inputs/opensky/<b>/<PHASE>/<b>.f`; `overrides/pnr_<PHASE>.tcl`), `run_p1_dl2.sh` (FROM/UNTIL=FP|PNR;
  `overrides/pnr_<PHASE>_dl2.tcl`), `run_signoff.sh <b> [exit]` (FLOWS, MAX_PARALLEL, PV_MODE=hier →
  `<exit>_HIER`, PUBLISH=1, LIB_TAG; PHASE default P0), `test_place_release.sh`, `test_exit_order.sh`.
- Doc: `PD/docs/02-user-guide/opensource-flow-guide.md`.
- Spec-to-GDS front end (`RTL/docs/opensource-rtl-guide.md`): RTL_SPEC (`rtl_spec(tool,name) "rtlcheck"`) — YAML block
  spec + SystemRDL / XLS registers → PeakRDL register RTL / UVM RAL / C header, IP-XACT 1685-2014 (schema-validated),
  SDC, UPF, RTL filelist, XLS vPlan; RTL ports vs spec; SPEC_EXIT (handshake `RTL_LINT,rtl`). Helper
  `RTL/utils/oss/spec_tool.py`; installs `global/utils/oss/install_{pytools,ipxact_schema,uvm}.sh` (CBFLOW_OSS_PYTHON,
  UVM_HOME, CCACHE_DIR via cbflow-oss). Spec memories carry depth / width / ports / `mbist` (algorithm, group), checked
  vs the RTL instances. RTL checks on the SPEC_EXIT tag: RTL_LINT `verilator` (slang + Verilator SARIF + Verible),
  RTL_CDC `opencdc` (SDC clocks, sv2v), UPF_CHECK `rtlcheck`; `<arr>(oss,waivers)` YAML (reason / owner / expires);
  exits LINT_SIGNOFF / CDC_SIGNOFF / UPF_SIGNOFF; helpers `RTL/utils/oss/rtl_check.py`,
  `RTL/utils/utilities/v1.0.0/oss_rtl_utils.tcl`. SYNTH `synth(input,rtl_format) "sverilog"` → yosys-slang `read_slang`
  (reads the LINT_SIGNOFF `rtl/<d>.f`). Pilot gcd P3 = GCD accelerator (stream + SRAM job queue, 9 APB regs, 2 SRAMs;
  `inputs/opensky/gcd/P3/`, smoke TB `tb/gcd_smoke_tb.sv`). SmartGrid `/dashboard/<DISC>` opens / starts each
  discipline's run dashboard; the project page has one card per discipline.
- Open-source DV (`DV/docs/opensource-dv-guide.md`): TB_SETUP / M1-M4_EXEC / DV_SIGNOFF `<arr>(tool,name) "verilator"`
  (`review` = generic gates). UVM 2020.3.1 on Verilator `--timing --coverage`, z3 (install_pytools) for randomize.
  `DV/utils/oss/uvmgen.py` builds the UVM env from spec + RAL (`ral/<d>_ral.sv` of SPEC_EXIT) + vPlan; user-owned
  `<d>_ref_model.sv` / `<d>_coverage.sv` / `<d>_tests.sv` in `tb_setup(oss,tb_dir)` replace stubs; TB samples at the
  rising edge. `dv_tool.py` regress (vPlan tests up to M x seeds) / covmerge (code + covergroup bins from the merged
  db — Verilator get_coverage() is 0 — + vPlan closure) / triage / signoff vs `project(dv,targets,M<n>)` (DV overlay).
  DV exit plan `project(phase_exits,DV)` (opensky P1 TB_SETUP M1 M2, P2 M3 M4 DV_SIGNOFF, P3 all), ordered by the
  exit gate per discipline. gcd P3 TB `inputs/opensky/gcd/P3/tb/uvm/`.
- DFT scandef: SYNTH writes `def/<d>.scandef` (mandatory with `project(dft,enable)`; `oss_scandef.tcl` fixes OpenROAD's
  reversed chain order); PNR `init_design` requires + `read_def -incremental`s it (handshake `PNR,def_scan`); PNR / ECO
  releases carry the post-route scandef; SCAN_INSERT checks it against its netlist trace.
- Open-source DFT (`DFT/docs/opensource-dft-guide.md`): SCAN_INSERT / ATPG `<arr>(tool,name) "fault"`, GLS_FUNC /
  GLS_SCAN_MBIST `"iverilog"`. SYNTH inserts scan; SCAN_INSERT traces / checks / flush-simulates it (SCAN_INSERT_EXIT);
  ATPG = macro stubs + `fault cut` + nl2bench + Atalanta (`global/utils/oss/install_atalanta.sh`, `lsf(oss,tools_dir)`;
  research licence) + `oss_dft.py fsim` + serial-scan testbench zd sim (ATPG_PREPD_EXIT / ATPG_POSTPD_EXIT,
  `atpg(pd_phase)`; timing_sim unsupported → bypass); GLS signoff-style on a netlist tag. Helpers
  `DFT/utils/oss/oss_dft.py`, `DFT/utils/utilities/v1.0.0/oss_dft_utils.tcl`; keys `project(dft,scan_in_pattern|
  scan_out_pattern|atpg,*_min)` (DFT overlay); MMMC nodes init_scan / init_atpg / init_sim.

## Dashboards
- Run dashboard: per-user daemon, port `flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)`
  (PD 9000, width 300). Action bar, Shift+click / Shift+drag multi-select, MMMC dialog, release-node form
  (Save → `setup/override_config.<node>.tcl` with `project(release,tag|publish|publish_override)`; publishes
  on re-run), Set Dependencies…, runs table with Block / Total runtime / Age, sortable, running first.
- SmartGrid: `cbflow smartgrid start --project <p>` (port `flow(smartgrid,port_base)` + md5(uid:project) %
  `port_span`). Published runs per flow (signoff runs attach to their exit), exit-centric releases page
  (signoff flows = `flow(release,signoff_flows)`), checklist waivers, DEF IO-pins, timing stage/corner filter,
  `flow(dashboard,floorplan_cells_max_bytes)`, `flow(report,slack_digits)`, `schedule_config.tcl`.
  Doc: `PD/docs/02-user-guide/project-dashboard-guide.md`.

## Command File Bootstrap
Every command file uses the same 14-line bootstrap:
```tcl
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "<FLOW>"
set STAGE_NAME "<stage>"
set NODE_NAME "<stage>1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
```

## RACE Engine
- TCL config resolver (`config_resolver.tcl`) — executes TCL via tclsh, captures resolved variables
- Dynamic subnodes: timing/extraction nodes resolve independently per node
- Per-node scenario override via `override_config.<node>.tcl`
- Log capture: stdout/stderr → `work/<FLOW>/<stage>/run/<job_name>.log`

### Run Ownership
- Owner stored: owner + owner_uid in run_info table on first init
- Enforcement: _check_ownership() before execute/retrace/bypass/forcevalidate/force
- Dashboard: HTTP 403 for unauthorized mutations
- Read-only access (status, GUI, logs) unrestricted

### Comprehensive Database (13 tables)
Original: jobs, run_info, run_config, job_order, dag_structure, stage_metrics
New: design_info, checklist_results, release_info, lsf_details, run_logs, metrics_snapshot, config_history
DB naming: .race_<run_dir_name>_<user>_<hash>.db
DB location: project(race,db_path) race area, .race_db_pointer in run_dir

## Flow-to-Flow Handoff

Downstream flows (STA, LEC, CLP, PV, EMIR, PNR, …) consume upstream artifacts
through three user-facing patterns. **Priority: explicit path > per-input tag > generic tag.**

**Pattern A — one knob, auto-resolves every required input:**
```tcl
set sta(input,release_tag) "P1_PNR_v1"
```
The resolver walks every `STA,*` handshake entry and populates each input
from `$release_base/P1_PNR_v1/<category>/<file>`. No need to enumerate
netlist / def / spef / sdc individually.

**Pattern B — per-input tag selection (mix across tags):**
```tcl
set sta(input,release_tag)     "P1_PNR_v1"   ;# baseline for most inputs
set sta(input,sdc_release_tag) "P1_STA_v2"   ;# SDC only from a different tag
```
Per-input keys fire BEFORE generic, so the specialization wins.

**Pattern C — explicit path override (wins over any tag):**
```tcl
set sta(input,release_tag) "P1_PNR_v1"
set sta(input,netlist)     "/my/custom/foo.v"
```
Explicit paths always win — resolver's skip-if-set guard protects them.

**Also supported — `from_run` (read a sibling run's output_manifest.tcl):**
```tcl
set sta(input,from_run) "/path/to/SYNTH_PNR_run"
```

**Legacy direct paths** (set every input individually) also work and
override any tag-based resolution.

**Handshake map** at `PD/config/flow/v1.0.0/release_config.tcl` section 6
declares the `(downstream_flow, input) → (source_flow, category, filename)`
tuple. `source_flow = ANY` means any upstream that stages the canonical
filename works (STA/PV/LEC/CLP/EMIR can read from either PNR or SYNTH_PNR
tags). Specific source_flow names (RTL_LINT, UPF_CHECK, DFT_INSERT_PASS3)
appear where the artifact is semantically unique to one upstream.

**SDC per mode** (dynamic from operating_modes): `sta(input,sdc,func)`, `sta(input,sdc,test)`

## STA Dynamic Scenarios
- Each scenario runs as parallel subnode: `timing1_func_ss_0p76v_rcmax_150c`
- Scenario context file: `work/STA/timing1/run/<scenario>_context.tcl`
- Sets globals: ::CORNER, ::MODE, ::VOLTAGE, ::TEMPERATURE, ::RC_CORNER, ::LIB_SET, ::SDC_FILE, ::SPEF_FILE
- Per-node independent scenarios via override_config
- GUI: right-click timing node → MMMC Scenarios → select → Save

## Key Design Principles
- **No hardcoded defaults** — mandatory vars error if not set
- **No fallbacks** — if config missing, crash with clear message
- **Single source of truth** — one variable, one place
- **Config files are data only** — no procs in configs (moved to utils.tcl)
- **Dynamic from operating_modes** — modes/SDCs auto-propagate when adding new modes
- **Per-RC-corner parasitics** — `tech(rcx,<corner>,<format>)` resolved dynamically

## Test Mode
All flows run in test_mode=true which creates dummy output files. Set `flow(test_mode) "true"` in user_config.

## When Running CBflow Commands
- Workspace: cd to `workarea/<design_name>/` (or subdirectory)
- Run: cd to the run directory (e.g., `P0_run_SYNTH_PNR_test1/`)
- The cbflow binary is at: `bin/cbflow` (→ `global/bin/cbflow`; `PD/bin/cbflow` is a compat symlink)
