# CBflow Physical Design Automation Framework

## What is CBflow
CBflow v2.0.0 is a Physical Design flow automation framework supporting 12 design flows with a Python-native RACE DAG execution engine, SQLite status tracking, web GUI dashboard, and per-scenario MMMC parallelism.

## Supported Flows
SYNTH, PNR, SYNTH_PNR, FP, FCFP, STA, LEC, CLP, PV, EMIR, POPT, ECO

Each flow supports dual tools: Synopsys (FC, PT, Formality, ICV, RedHawk) + Cadence (Innovus, Genus, Tempus, Conformal, Voltus, Calibre)

## Project Structure
```
PD/
  bin/cbflow                              Main CLI entry point
  config/
    flow/v1.0.0/
      flow_config.tcl                     Flow settings (110 lines — mandatory vars, dispatcher, milestones)
      mmmc_config.tcl                     Auto-generated MMMC scenarios from PVT building blocks
      release_config.tcl                  Release exits × phases, flow handshake, milestone criteria
      lsf_config.tcl                      LSF queues (XS/S/M/L/XL/ultra) + per-flow stage→queue mapping
      descriptions_config.tcl             Flow/phase/milestone descriptions (moved from flow_config)
      dir_config.tcl                      Directory structures per flow
      edit_restricted_config.tcl          Protected variables (tech identity, tool selection, milestones)
      ml_config.tcl                       ML analytics config
      node_configs/
        <FLOW>_config.tcl                 Common: stages, deps, subnodes, node_types, MMMC, runtime
        <FLOW>_<tool>_config.tcl          Tool-specific: app settings, compile/place/cts/route options
    project/<name>/v1.0.0/                Project configs (ravendrive, phoenix)
    tech/<node>/v1.0.0/                   Technology configs (gf_22nm, tsmc_5nm, tsmc_7nm)
    exit/v1.0.0/                          Exit milestone checklist configs
  cmds/<FLOW>/<vendor>/<tool>/v1.0.0/     Stage command files (TCL) + subnode handlers
  utils/
    commands/                             Python: race_engine, run_cmd, workspace_cmd, config_resolver
    utilities/v1.0.0/                     TCL: utils.tcl, resolve_inputs.tcl, release_utils.tcl
    dashboard/                            Web GUI (race_dashboard.py + templates)
    validation/                           Validation scripts
    generation/                           Config/setup file generators
  ai/                                     SmartGenie AI agent
```

## Config Architecture

### Single Array Per Flow
Each flow uses ONE array: `synth_pnr()`, `synth()`, `pnr()`, `fp()`, `sta()`, `lec()`, `clp()`, `pv()`, `emir()`, `eco()`, `popt()`, `fcfp()`. No tool-specific arrays (`fc()`, `pt()`, `genus()`, etc.) — all merged into the flow array.

### Config Cascade (generated config.tcl per node)
project_init → project → team → tech → flow → node_common → node_tool → mmmc → user → overrides

### Tech Config Structure
- Track-categorized libraries: `tech(<track>,ndm,stdcell)` + shared `tech(ndm,memory/io/analog)`
- Auto-build combined: `tech(<track>,ndm)` via foreach loop
- Per-RC-corner parasitics: `tech(rcx,<rc_corner>,<format>)` where format = tluplus/qrc/nxtgrd
- Physical cells: clock_buffers, clock_inverters, hold_buffers, delay_cells, icg_cells, power_switch, isolation, level_shifter, tie_cells, fillers, well_tap, endcap, decap

### MMMC Auto-Generation
- PVT building blocks: `mmmc(pvt,ss)`, `mmmc(pvt,tt)`, `mmmc(pvt,ff)` + RC pairing rules
- Analysis views auto-generated: modes × corners × PVT points
- Scenario sets auto-filtered: setup, hold, signoff, all, power
- Operating modes define per-mode SDC: `operating_modes(func,constraint_file)`

### Node Config Split
- `<FLOW>_config.tcl` — common: stages, dependencies, subnodes (foreach loop), node_types, MMMC, runtime
- `<FLOW>_<tool>_config.tcl` — tool-specific: app settings, compile/place/cts/route options, required_inputs

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
cbflow run release-check --tag BTO --project ravendrive
cbflow run gui                    # Web dashboard
```

### Checklist
```bash
cbflow flow checklist list                                    # Show all milestones
cbflow flow checklist generate --milestone PLACE_EXIT         # Generate checklist
cbflow flow checklist status --milestone BTO --run-dir .      # Check status
cbflow flow checklist signoff --milestone BTO --run-dir .     # Sign off
```

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

## Flow-to-Flow Handoff
Three mechanisms:
1. **Direct paths**: `sta(input,netlist) "/path/to/netlist.v"`
2. **from_run**: `sta(input,from_run) "/path/to/SYNTH_PNR_run"` — reads output_manifest.tcl
3. **release_tag**: `sta(input,netlist_release_tag) "P0_BTO"` — reads from release directory

SDC per mode (dynamic from operating_modes): `sta(input,sdc,func)`, `sta(input,sdc,test)`

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
- The cbflow binary is at: `PD/bin/cbflow`
