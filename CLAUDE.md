# CBflow Physical Design Automation Framework

## What is CBflow
CBflow v2.0.0 is a Physical Design flow automation framework supporting 12 design flows (SYNTH, PNR, SYNTH_PNR, FP, FCFP, STA, LEC, CLP, PV, EMIR, POPT, ECO) with a Python-native RACE DAG execution engine, SQLite status tracking, and a web GUI dashboard.

## Project Structure
```
PD/                              Core framework
  bin/cbflow                     Main CLI entry point
  config/flow/v1.0.0/           Flow configs (flow_config, node_configs, mmmc_config, release_config)
  config/project/<name>/        Project configs (ravendrive, phoenix)
  config/tech/<node>/           Technology configs (gf_22nm, tsmc_5nm, tsmc_7nm)
  cmds/<FLOW>/<vendor>/<tool>/  Stage handlers (TCL)
  utils/commands/               Python command handlers (run_cmd, workspace_cmd, race_engine)
  utils/utilities/              TCL utilities (error_utils, resolve_inputs, release_utils)
  utils/validation/             Validation scripts (validate_run, validate_config)
  utils/dashboard/              Web GUI (race_dashboard.py + templates)
  ai/                           AI agent (MCP server + agent runner)
```

## CBflow Commands

### Workspace (from workarea)
```bash
cbflow workspace create --config uc_SYNTH_PNR.tcl
cbflow workspace status
cbflow workspace list-runs
```

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

### Flow info
```bash
cbflow flow types                 # List all 12 flows
cbflow flow stages --flow PNR     # Show stage list
cbflow flow check                 # Verify installation
```

## User Configs
Located in `workarea_test/`: uc_SYNTH.tcl, uc_PNR.tcl, uc_SYNTH_PNR.tcl, uc_STA.tcl, uc_LEC.tcl, uc_CLP.tcl

## Config Cascade (14 levels, lowest to highest priority)
project_init → project → team → tech → flow → node → mmmc → tool_config → user → override (global → flow → type → branch → node)

## Key Architecture Decisions
- RACE engine replaces GNU Make — pure Python DAG executor with SQLite
- Config consolidated into single generated config.tcl per node
- CBFLOW_NODE_NAME env var enables dynamic paths for custom nodes/branches
- Milestone-gated release: predefined tags (FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO)
- Flow-to-flow handoff via output_manifest.tcl + resolve_inputs.tcl
- Dynamic RC corner extraction subnodes for STA
- Branch-level config overrides: override_config.<branch_name>.tcl

## Test Mode
All flows run in test_mode=true which creates dummy output files matching real EDA tool naming. Set `flow(test_mode) "true"` in user_config.

## When Running CBflow Commands
- Always cd to the correct directory first (workspace for workspace cmds, run dir for run cmds)
- The cbflow binary is at: PD/bin/cbflow
- For parallel operations, use separate terminal sessions (RACE handles parallelism internally)
