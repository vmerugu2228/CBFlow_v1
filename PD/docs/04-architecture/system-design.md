# System Design

Architecture of CBflow v2.0.0: a multi-discipline design automation framework
(PD, DFT, DV, RTL) on one shared engine, one config cascade, one CLI and one
release model. Paths below are relative to `$CBFLOW_ROOT` (the umbrella root)
unless stated otherwise.

---

## 1. Repository Layout

```
$CBFLOW_ROOT/
├── bin/                     launcher symlinks → global/bin/ (cbflow, cbflow-oss, cbflow-run, …)
├── global/                  cross-discipline layer, sourced by every run
│   ├── bin/                 cbflow, cbflow-flow, cbflow-run, cbflow-workspace, cbflow-oss,
│   │                        cbflow-oss-checks, _cbflow_paths.sh, …
│   ├── config/
│   │   ├── cli/discipline_commands.tcl        subcommand → owning discipline
│   │   ├── flow/v1.0.0/flow_registry.tcl      flow(types), flow(discipline,*), runtime + dashboard defaults
│   │   ├── flow/v1.0.0/oss_launch_config.tcl  open-source tool shells (cbflow-oss), image, tools dir
│   │   ├── flow/v1.0.0/descriptions_config.tcl, canonical_release_schema.tcl
│   │   ├── exit/v1.0.0/                       every exit milestone (all disciplines) + checks/, waivers
│   │   ├── tech/<node>/v1.0.0/tech_config.tcl single tech file per node
│   │   ├── project/<proj>/v1.0.0/             <proj>_config.tcl, team / mmmc / schedule configs
│   │   └── master_projects.json               project registry
│   └── utils/
│       ├── commands/        Python CLI + engine: race_engine.py, run_cmd.py, workspace_cmd.py,
│       │                    start_run.py, config_resolver.tcl, test_cmd.py, test_suite/
│       ├── core/            paths.py, env.py, registry.py, db.py, release_exits.py, …
│       ├── utilities/v1.0.0/ Tcl runtime: utils.tcl, handler_common.tcl, launch_utils.tcl,
│       │                    resolve_inputs.tcl, release_utils.tcl, tool_overlay.tcl,
│       │                    oss_utils.tcl, oss_flow_utils.tcl, oss_checks.tcl, oss_checkgrp_*.tcl
│       ├── generation/v1.0.0/ generate_setup.tcl (per-node config.tcl + setup.tcl)
│       ├── dashboard/       per-user run dashboard daemon
│       ├── project_dashboard/ SmartGrid (router.py, releases.py, chain.py, floorplan.py, …)
│       ├── validation/v1.0.0/ validators + checks/ (exit check scripts)
│       └── oss/             install_pytools.sh, install_uvm.sh, install_atalanta.sh, install_ipxact_schema.sh
├── PD/                      $CBFLOW_CORE_DIR
│   ├── bin/cbflow-pd        PD-owned subcommands (library-manager, mmmc-manager, checklist)
│   ├── config/flow/v1.0.0/  flow_config.tcl, release_config.tcl, lsf_config.tcl, dir_config.tcl,
│   │                        tool_launch_config.tcl, validation_config.tcl, node_configs/
│   ├── config/project/<proj>/v1.0.0/<proj>_pd_config.tcl   PD overlay (workarea, release, lsf, lib tags)
│   ├── config/setup/        flow_proc hook files (common / project)
│   ├── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/   handlers + command files
│   ├── utils/commands/      PD Python commands (library_manager_cmd, checklist_cmd, mmmc_manager_cmd, …)
│   └── ai/                  SmartGenie agent
├── DFT/  DV/  RTL/          $CBFLOW_DFT_DIR / $CBFLOW_DV_DIR / $CBFLOW_RTL_DIR
│   ├── bin/cbflow-<disc>    discipline launcher (extension point)
│   ├── config/flow/v1.0.0/  flow_config.tcl, lsf_config.tcl, dir_config.tcl, tool_launch_config.tcl, node_configs/
│   ├── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/
│   ├── utils/oss/           open-source helpers (oss_dft.py / uvmgen.py, dv_tool.py / spec_tool.py, rtl_check.py)
│   ├── utils/utilities/v1.0.0/ discipline Tcl helpers (oss_dft_utils.tcl, oss_rtl_utils.tcl, …)
│   └── docs/
└── workarea/                design workareas + driver scripts (run_p1_dl3.sh, run_signoff.sh, run_spec2gds.sh, …)
```

Only `CBFLOW_ROOT` is user-facing. `global/bin/_cbflow_paths.sh` derives
`CBFLOW_GLOBAL_DIR`, `CBFLOW_CORE_DIR` (PD), and `CBFLOW_DFT_DIR` /
`CBFLOW_DV_DIR` / `CBFLOW_RTL_DIR` (only when the directory exists), and
defaults `FLOW_CONFIG_VERSION`, `UTILITIES_VERSION`, `TECH_CONFIG_VERSION`,
`PROJECT_CONFIG_VERSION` to `v1.0.0`.

### Flow catalogue

`global/config/flow/v1.0.0/flow_registry.tcl` is the single list:
`flow(types)` (33 flows), `flow(disciplines) {PD DFT DV RTL}`,
`flow(discipline_dir,<DISC>)` and `flow(discipline,<FLOW>)`.

| Discipline | Flows |
|---|---|
| PD (12)  | SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR |
| DFT (7)  | DFT_INSERT_PASS1 DFT_INSERT_PASS2 DFT_INSERT_PASS3 SCAN_INSERT ATPG GLS_FUNC GLS_SCAN_MBIST |
| DV (9)   | SPEC_RAMP PLANNING TB_SETUP M1_EXEC M2_EXEC M3_EXEC M4_EXEC ECO_EXEC DV_SIGNOFF |
| RTL (5)  | RTL_SPEC RTL_LINT RTL_CDC RTL_RDC UPF_CHECK |

`bin/cbflow flow types` prints the live table (vendor / tool / shell per flow).

---

## 2. Launcher Composition

```
bin/cbflow ──► global/bin/cbflow           workspace | run | flow | bundle | migrate | test |
                                           dashboard | smartgrid | smartgenie | --version
                 └─ flow ──► global/bin/cbflow-flow
                               types | info | stages | nodes | check | project | release |
                               version | dev | config | plugin | metrics | …
                               *) unknown subcommand → look up
                                  global/config/cli/discipline_commands.tcl
                                  set cli(discipline,<subcmd>) "<DISC>"
                                  → exec $CBFLOW_ROOT/<DISC>/bin/cbflow-<disc> flow <subcmd> …
PD/bin/cbflow-pd   PD_FLOW_SUBCOMMANDS=(library-manager mmmc-manager checklist)
                   → python3 PD/utils/commands/<cmd>_cmd.py; anything else → global/bin/cbflow
DFT/bin/cbflow-dft, DV/bin/cbflow-dv, RTL/bin/cbflow-rtl
                   empty <DISC>_FLOW_SUBCOMMANDS today; everything falls through to global/bin/cbflow
```

`PD/bin/cbflow` is a compatibility symlink to `global/bin/cbflow`. Run
execution (`cbflow run …`) and workspace creation are discipline-agnostic: the
flow's discipline comes from `flow(discipline,<FLOW>)`. See
[Extending CBflow](../05-developer/extending.md#3-adding-a-discipline-owned-subcommand)
for adding a discipline-owned subcommand.

---

## 3. Config Cascade

Configs are plain Tcl data (no procs; procs live in `utils.tcl`). Every node's
generated `work/<FLOW>/<node>/run/config.tcl` sources, in order (later wins):

| # | File | Notes |
|---|---|---|
| 1 | `global/config/project/<proj>/v1.0.0/<proj>_config.tcl` (+ `team_config.tcl`) | identity, hierarchy, `project(phases)`, `project(phase_exits[,<DISC>])` |
| 2 | `<DISC>/config/project/<proj>/v1.0.0/<proj>_<disc>_config.tcl` | every discipline overlay present on disk (DFT, DV, RTL, then PD) — PD: workarea, `release,*`, `lsf,*`, `lib_root`, `lib_tag_root`, `lib_config_tag`, `race,db_path` |
| 3 | `global/config/tech/<tech>/v1.0.0/tech_config.tcl` | foundry data, metal stack, physical cells; sources the library tag's `lib_config.tcl` / `blocks_config.tcl` (library-manager output under `project(lib_tag_root)/<TAG>/`) |
| 4 | `<DISC>/config/flow/v1.0.0/flow_config.tcl` | routed by `flow(discipline,<FLOW>)`; the discipline flow_config sources `global/config/flow/v1.0.0/flow_registry.tcl` (and `descriptions_config.tcl`) first |
| 5 | `<DISC>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl` | stages, deps, subnodes, node_types, runtime; sources its tool overlay `<FLOW>_<tool>_config.tcl` (from `<flow>(tool,name)` / `default_tool`) |
| 6 | `global/config/project/<proj>/v1.0.0/mmmc_config.tcl` (+ `mmmc_node_scenarios.tcl`) | MMMC PVT building blocks, per-node scenarios |
| 7 | `<run>/setup/user_config.tcl` | user overrides; then `cbflow_reload_tool_overlay` (`tool_overlay.tcl`) loads a user-selected tool's overlay and re-sources user_config |
| 8 | `<run>/setup/override_config.tcl` → `.<stage>.tcl` → `.<branch>.tcl` → `.<node>.tcl` | per-node overrides (stage = node type without the instance number; there is no flow-name level) |

The same walk runs in three places that must stay in step:
`generate_setup.tcl::get_hierarchical_config_paths` (per-node `config.tcl`),
`global/utils/commands/config_resolver.tcl` (the engine's resolved config) and
`handler_common.tcl::handler_load_configs` (handlers).

### flow_proc hook cascade (setup.tcl)

`generate_setup.tcl` also writes `work/<FLOW>/<node>/run/setup.tcl`, which
sources hook files only (lowest → highest priority; `$CONFIG_ROOT` =
`<DISC>/config` of the flow, e.g. `PD/config`; `SETUP_VERSION` defaults to v1.0.0):

```
$CONFIG_ROOT/setup/common/v1.0.0/setup.tcl, flow_setup.tcl
$CONFIG_ROOT/setup/common/v1.0.0/<FLOW>/<vendor>/<tool>/global_setup.tcl, <stage>_setup.tcl
$CONFIG_ROOT/setup/<proj>/v1.0.0/setup.tcl, <FLOW>/flow_setup.tcl
<run>/setup/setup.tcl, flow_setup.tcl, <stage>_setup.tcl
<run>/setup/override_setup.tcl → override_setup.<stage>.tcl → override_setup.<node>.tcl
```

---

## 4. RACE Engine

`global/utils/commands/race_engine.py` (Run Automation & Control Engine) is the
Python DAG executor. There is no Make anywhere in the execution path
(`cbflow run gen-makefile` only verifies the engine DAG; the name is historical).

- **DAG** (`DagBuilder`) — built at run time from the resolved node config:
  `<flow>(stages)`, `<flow>(dependencies,<node>)`, `<flow>(subnodes,<node>)`
  (normally `setup run validate finish`; inputs nodes use one subnode per
  input type) and `subnode_dependencies`. Run-level changes from
  `add-node` / `create-branch` / `set-dep` live in
  `<run>/setup/runtime_flow_config.tcl` and are merged on top.
- **Dynamic subnodes** — a node with `<flow>(subnodes,<node>,dynamic_kind)`
  `scenario` fans out one subnode per MMMC scenario
  (`override_config.<node>.tcl` → user_config `<flow>(mmmc,setup|hold_scenarios)`
  → node-config `mmmc,scenario_set`); `rc_corner` fans out per RC corner.
- **Handler lookup** — `cmds/<FLOW>/<vendor>/<tool>/<version>/<node_type>_subnode_handler.tcl`
  under the flow's discipline root first (`CBFLOW_<DISC>_DIR`), then PD, then
  any other discipline root. Each job runs
  `tclsh <handler> <subnode> <run_dir> <node>`.
- **Per-job environment** — everything in `<run>/.run.cbflow.env`
  (`FLOW_DIR` = umbrella root, `CONFIG_ROOT` = `<DISC>/config`,
  `SCRIPTS_ROOT` = `global/utils`, `CBFLOW_*`, `*_VERSION`), plus
  `CBFLOW_ENGINE=1`, `CBFLOW_RUN_DIR`, `CBFLOW_NODE_NAME`, `CBFLOW_SUBNODE`.
- **Status DB** (`StatusDB`, SQLite, WAL) — the only status store (no stamp
  files). Path: `project(race,db_path)/<project>/<discipline>/<FLOW>/<run_dir_name>_<user>_<md5(run_dir)[:6]>.db`,
  located again through `<run>/.race_db_pointer`. `project(race,db_path)` is
  mandatory. Tables: jobs, run_info, run_config, job_order, dag_structure,
  stage_metrics, design_info, release_info, decision_outcomes, lsf_details,
  run_logs, metrics_snapshot, config_history, checklist_results.
  `workspace create` archives a stale DB (with `-wal` / `-shm`) as `<db>.stale-<ts>`.
- **Execution** — ready jobs run in parallel, capped by
  `flow(max_parallel_jobs)` (0 = unlimited); per-node `runtime,timeout`;
  logs to `work/<FLOW>/<node>/run/<job>.log`.
- **Active sync** — `retrace`, `bypass`, `force`, `forcevalidate` write the DB
  and the running engine re-reads it. A fully bypassed node gets
  `work/<FLOW>/<node>/BYPASSED` (removed on retrace / force).
- **File-change detection** — edited source inputs retrace downstream nodes.
- **Ownership** — `owner` / `owner_uid` in `run_info`; mutating commands call
  `_check_ownership()`; the dashboard returns HTTP 403 to non-owners.

---

## 5. Handlers and Launch

Every execution node has a thin subnode handler:

```tcl
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"
lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PNR"
...
handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name $cmd_file $test_mode $_tool
```

`handler_common.tcl::handler_dispatch` maps the four subnodes:

| Subnode | Proc | Does |
|---|---|---|
| setup | `handler_setup` | runs `generate_setup.tcl` → `config.tcl` + `setup.tcl` |
| run | `handler_run` (launch_utils.tcl) | `generate_launch_wrapper` + `submit_job` (tool shell from `lsf(tool_shell,<tool>)`) |
| validate | `handler_validate` | production mode: `<flow>(mandatory_outputs,<node>)` exist + non-empty and `outputs/` has ≥ 1 file; test mode short-circuits |
| finish | `handler_finish` | finish timestamp; `handler_publish_release` publishes a release node to SmartGrid when `project(release,publish)` is true |

Inputs nodes call `handler_resolve_inputs` + `handler_dispatch_inputs`
(release-tag / from_run / direct-path resolution, staging, naming).

**Launch modes** (`launch_utils.tcl::determine_launch_mode`): `flow(use_lsf)` /
`CBFLOW_USE_LSF` / `CBFLOW_BSUB_CMD`, and `flow(use_xterm)` /
`CBFLOW_USE_XTERM` → LSF + xterm, LSF batch, local xterm, or local.
Registry defaults (`flow_registry.tcl`): `test_mode=false`, `use_lsf=false`,
`use_xterm=true`. Three gates stop a run from completing "clean" without the
tool running: `start_run.py::_preflight_launch_bins` (bsub / xterm present),
`submit_job` xterm branch (`$DISPLAY`, synchronous, exit code checked), and
`handler_validate` (mandatory outputs).

### Open-source tool container

Vendor `opensource` tools run in a container via `global/bin/cbflow-oss`:

```
cbflow-oss <tool> <cmd_file> <log>   yosys | openroad | sta | magic | netgen | klayout |
                                     tclsh | fault | iverilog | verilator | rtlcheck | vplan | python3
cbflow-oss exec -- <argv…> | check | gui openroad|klayout <file> | interactive <tool> [script]
```

`global/config/flow/v1.0.0/oss_launch_config.tcl` (sourced by every
discipline's `tool_launch_config.tcl`) sets `lsf(tool_shell,<tool>)` to
`cbflow-oss <tool>`, the interactive shells, `lsf(oss,image)` (pinned digest)
and `lsf(oss,tools_dir)`. The container bind-mounts `CBFLOW_ROOT`, the run dir,
the PDK root and `CBFLOW_OSS_MOUNTS` at identical paths and passes the CBflow
environment through, so command files resolve paths as on the host.
Overrides: `CBFLOW_OSS_IMAGE`, `CBFLOW_OSS_PDK_ROOT`, `CBFLOW_OSS_MOUNTS`,
`CBFLOW_OSS_TOOLS`, `CBFLOW_OSS_MAGICRC`, `CBFLOW_OSS_ENGINE`.

---

## 6. Command Files and flow_proc

Every command file starts with the same bootstrap:

```tcl
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "place"
set NODE_NAME [cbflow_node_name]          ;# $CBFLOW_NODE_NAME (place1, place2, branch nodes …)

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME   ;# WORK_DIR / REPORTS_DIR / OUTPUTS_DIR …
```

then defines its steps with `flow_proc <name> { … }` and ends with
`flow_exec_all` (`oss_exec_all` in the RTL / DFT / DV open-source drivers) and
`exit`. `flow_exec_all` runs the procs in **definition order**.

Hooks (`utils.tcl`): `flow_proc_prepend <name> {…}` and
`flow_proc_append <name> {…}` are stored separately and run around the body;
`flow_proc_replace <name> {…}` replaces the body. Because `setup.tcl` (and so
every `override_setup*.tcl`) is sourced **before** the command file defines its
flow_procs, prepend / append from setup files always apply, while a
`flow_proc_replace` there is overwritten when the command file later defines
that proc.

Node helpers in `utils.tcl`: `cbflow_node_deps`, `cbflow_node_type`,
`cbflow_upstream_node`, `cbflow_chain_node <type>` (breadth-first over every
dependency, nearest node of that type, first-listed dependency first — reaches
each branch of a fan-in), `cbflow_source_node <types>` (first-dependency chain,
skips bypassed nodes — the source stage of an export / release),
`cbflow_dep_node`, `cbflow_release_dir`, `cbflow_require`, `cbflow_version`.

---

## 7. Release System

Layout (single definition: `cbflow_release_dir`):

```
<project(release,path)>/<phase>/<block>/<FLOW>/<tag>/
    <category>/…          netlist/ sdc/ def/ gds/ spef/ upf/ rtl/ spec/ reports/ data/ …
    MANIFEST.json  RELEASE_NOTES.md  RELEASE_COMPLETE
```

`phase` is the run's phase (`CBFLOW_PROJECT_PHASE`); `tag` is
`project(release,tag)` or else the exit name. `::CBFlow::Release` in
`global/utils/utilities/v1.0.0/release_utils.tcl`:

- `default_exit_tag` — signoff flows release the exit they verify
  (`<flow>(release,exit_from)` names the input whose tag that is); other flows
  release `<flow>(smartgrid,milestone)`, mapped to the phase's exit at or before
  it through `MILESTONE_ORDER` (PD `release_config.tcl`). Exits outside
  `MILESTONE_ORDER` (DFT / DV / RTL exits) release under their own name.
- `release_exit_for_stage` — the export / release pair releases its source
  stage (`cbflow_source_node`): place → PLACE_EXIT, cts_opt → CTS_EXIT,
  pro → PRO_EXIT, signoff → BTO / MTO (`MILESTONE_STAGE_MAPPING`).
- `check_exit_order` — earlier exits of the phase need `RELEASE_COMPLETE`.
  The exit list is `project(phase_exits)` for the phase, or, when the exit is
  not in it, the per-discipline plan `project(phase_exits,<DISC>)` that
  contains it (e.g. opensky's DV plan). Skipped in test mode and for signoff
  flows; publish to SmartGrid has its own order gate.
- `init` / `copy_file` / `copy_glob` / `validate_mandatory_files` /
  `generate_manifest` / `generate_release_notes` / `stamp_complete`.

`cbflow run release` flags: `--tag --name --dry-run --from-run --node
--clone-from --publish --no-publish --override`. Full user view:
[Exit Release Guide](../02-user-guide/exit-release-guide.md).

### Flow-to-flow handshake

`PD/config/flow/v1.0.0/release_config.tcl` section 6 holds the map for every
discipline:

```tcl
set flow_input_handshake(<DOWNSTREAM>,<input>) {<source_flow|ANY> <category> "<file pattern>"}
set flow_input_handshake(RTL_LINT,rtl)  {RTL_SPEC rtl "${design_name}.f"}
```

`resolve_inputs.tcl::resolve_flow_inputs` fills `<flow>(input,<input>)` with
priority explicit path > `<flow>(input,<input>_release_tag)` >
`<flow>(input,release_tag)`; `<flow>(input,from_run)` reads a sibling run's
`output_manifest.tcl`. Signoff flows accept only the release of their exit
(`<flow>(release,exit_exempt_inputs)` lists exceptions, e.g. LEC
`netlist_golden`).

---

## 8. Exit Milestones and Checklists

All milestones live in `global/config/exit/v1.0.0/<NAME>_config.tcl`, each with
`milestone_info(name|discipline|flow_type|stage|description|stage_node)`,
`mandatory_checks` / `optional_checks`, `mandatory_files`:

| Discipline | Milestones |
|---|---|
| PD  | FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO, STA_SIGNOFF |
| DFT | CORE_DFT_EXIT TOP_DFT_EXIT EDT_OCC_EXIT SCAN_INSERT_EXIT ATPG_PREPD_EXIT ATPG_POSTPD_EXIT |
| DV  | SPEC_RAMP_EXIT PLANNING_EXIT TB_SETUP_EXIT M1_EXIT M2_EXIT M3_EXIT M4_EXIT ECO_EXEC_EXIT DV_SIGNOFF_EXIT |
| RTL | SPEC_EXIT LINT_SIGNOFF CDC_SIGNOFF UPF_SIGNOFF |

Check scripts: `global/utils/validation/v1.0.0/checks/`. Waivers:
`global/config/exit/v1.0.0/waiver_config.tcl`. CLI: `cbflow flow checklist …`
(`PD/utils/commands/checklist_cmd.py`).

---

## 9. Dashboards

- **Run dashboard** — `cbflow run gui` registers the run with one per-user
  daemon (`global/utils/dashboard/`). Port =
  `flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)`
  (PD 9000, DFT 9300, DV 9600, RTL 9900; width 300). A foreground per-run
  dashboard uses `flow(dashboard,run_port_min..run_port_max)` (30000-59999);
  the project / run browser uses `app_port_min..app_port_max` (8080-8999).
- **SmartGrid** — `cbflow smartgrid start --project <p>`
  (`global/utils/project_dashboard/`), port `flow(smartgrid,port_base)` (25000)
  + md5(uid:project) % `flow(smartgrid,port_span)` (2500). `router.py` serves
  `/` (published runs), `/project/<p>` (one card per discipline),
  `/project/<p>/releases | checklist | schedule | team | chain`,
  `/dashboard/<DISC>` (opens or starts that discipline's run dashboard),
  `/block/…`, `/published/…`, `/api/floorplan/…`, `/api/timing/…`.
  The chain page (`chain.py`) shows the spec-to-GDS sign-off chain from
  `project(signoff_chain,<phase>)`: a step is done when its
  `<FLOW>/<tag>/RELEASE_COMPLETE` exists, and flagged stale when released
  before a step of an earlier stage.

All ports and colours come from `global/config/flow/v1.0.0/flow_registry.tcl`.

---

## 10. Versioning

Config / command / utility trees are versioned directories (`v1.0.0`, …)
selected at run time by `FLOW_CONFIG_VERSION`, `UTILITIES_VERSION`,
`TECH_CONFIG_VERSION`, `PROJECT_CONFIG_VERSION` and `<TOOL>_VERSION` /
`<flow>(tool,version)`. `cbflow flow version …` and `cbflow flow dev …` manage
copies and `current` symlinks — see [Versioning Strategy](git-strategy.md).

---

**See also:**
- [Data Flow](data-flow.md) — a run end to end
- [Component Design](component-design.md) — module map
- [Extending CBflow](../05-developer/extending.md) — adding flows, tools, exits, handshakes
