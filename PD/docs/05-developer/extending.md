# Extending CBflow

How to add flow_procs, checks, flows, and tool overrides in CBflow v2.0.0.

## 1. Adding a flow_proc to an Existing Stage

Add via setup hook (no editing of base command files):

```tcl
# setup/override_setup.place.tcl — appends to place_opt stage
flow_proc_append run_place_opt {
    # Extra congestion-driven placement pass
    handle_info "Running extra congestion pass..."
    create_placement -incremental -congestion
}
```

Or via prepend/replace:
```tcl
flow_proc_prepend load_design {
    handle_info "Custom pre-load setup..."
}

flow_proc_replace configure_place_opt {
    # Completely replace the configure proc
    handle_info "Using custom placement config..."
    set_app_options -name opt.common.user_instance_name_prefix -value custom_
}
```

## 2. Adding an Exit Check

Three modes via CLI:

### Script-based
```bash
cbflow flow checklist add-check --milestone PRO_EXIT \
  --name timing_clean --check-type mandatory \
  --description "Setup WNS must be non-negative" \
  --script check_timing.tcl --criteria "setup_wns >= 0"
```

### Grep-based (check report file for pattern)
```bash
cbflow flow checklist add-check --milestone BTO \
  --name drc_zero --check-type mandatory \
  --description "DRC violations must be zero" \
  --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
  --grep-pattern "Total.*0.*violation" --grep-pass-if found
```

### File existence
```bash
cbflow flow checklist add-check --milestone BTO \
  --name gds_exists --check-type file \
  --file-path 'outputs/${design_name}.gds'
```

## 3. Adding a New Design Flow

### Step 1: Create node config

The RACE engine reads node_config files to build the execution DAG. Create a new node config:

```tcl
# config/flow/v1.0.0/node_configs/MYFLOW_config.tcl
array set myflow {
    stages {inputs1 run1 export_data1 release_data1}
    dependencies,inputs1 {}
    dependencies,run1 {inputs1}
    dependencies,export_data1 {run1}
    dependencies,release_data1 {export_data1}
    stage_types,inputs1 "inputs"
    stage_types,run1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"
    node_types,inputs1 "inputs"
    node_types,run1 "myflow"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"
    runtime,timeout,inputs1 10
    runtime,timeout,run1 60
    runtime,timeout,export_data1 15
    runtime,timeout,release_data1 10
    tool,vendor "synopsys"
    tool,name "fc"
}
```

RACE will parse the `stages` and `dependencies,*` keys to construct the DAG automatically at runtime. There is no Makefile to generate.

### Step 2: Add to flow(types)
```tcl
# config/flow/v1.0.0/flow_config.tcl
set flow(types) {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR MYFLOW}
```

### Step 3: Create command files
```
cmds/MYFLOW/synopsys/fc/v1.0.0/
    inputs_fc.tcl
    run_fc.tcl
    export_data_fc.tcl
    release_data_fc.tcl
```

Each command file follows the standard pattern:
```tcl
#!/usr/bin/env tclsh
# Standard header: env, utils, tech_config, user_config
set WORK_DIR "$run_dir/work/MYFLOW/run1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities (for inputs stage)
source $FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl
source $::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl

flow_proc resolve_inputs { ... }
flow_proc do_work { ... }
flow_proc generate_reports {
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }
}

# Setup hooks
set _setup_file "$run_dir/work/MYFLOW/run1/run/setup.tcl"
if {[file exists $_setup_file]} { source -e $_setup_file }
set _override "$run_dir/setup/override_setup.tcl"
if {[file exists $_override]} { source -e $_override }

flow_exec_all
exit
```

### Step 4: Create handlers
```
cmds/MYFLOW/synopsys/fc/v1.0.0/
    inputs_subnode_handler.tcl
    run_subnode_handler.tcl
    export_data_subnode_handler.tcl
    release_data_subnode_handler.tcl
```

### Step 5: Verify the DAG

After creating the node config, verify that RACE can build a valid DAG:

```bash
cbflow run verify-dag
```

This parses the node_config and validates the dependency graph without executing anything.

## 4. Overriding Tool Selection

In `user_config.tcl`:
```tcl
# Switch PNR from Synopsys FC to Cadence Innovus
set pnr(tool,vendor) "cadence"
set pnr(tool,name)   "innovus"
```

No flow config changes needed -- RACE reads these variables and selects the correct command files.

## 5. Standard Command File Pattern

All command files follow this streamlined structure. The generated `config.tcl` consolidates all configuration sources (project, tech, flow, mmmc, tool, user, overrides) so command files source it once:

```
1.  Shebang + comment header
2.  Environment sourcing (.run.cbflow.tcl)
3.  Utils sourcing (utils.tcl)
4.  Source config.tcl (generated — single file with full config cascade)
      Path: $run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl
5.  WORK_DIR / REPORTS_DIR / OUTPUTS_DIR setup (use $::env(CBFLOW_NODE_NAME) for paths)
6.  Release utilities sourcing (inputs stages)
7.  flow_proc definitions (resolve_inputs first, generate_reports last)
8.  Setup hook sourcing:
      - setup.tcl (generated flow_proc hooks — same dynamic path as config.tcl)
      - override_setup.tcl (global user hook)
      - override_setup.<stage>.tcl (per-stage user hook)
9.  flow_exec_all
10. exit
```

**Important**: Do NOT source user_config.tcl, mmmc_config.tcl, fc_config.tcl, or override_config.tcl individually — they are already in `config.tcl`. Use `$::env(CBFLOW_NODE_NAME)` for paths, never hardcode stage names like `place1`.

### Custom Node Handler Resolution

When a custom node (e.g., `synthesis2_eco`) is executed, the RACE engine resolves the handler from the node's stored `type` field (e.g., `synthesis` → `synthesis_subnode_handler.tcl`). The `CBFLOW_NODE_NAME` env var is set to the actual node name so config.tcl and setup.tcl are read from the correct work directory.

## 6. RACE Engine Integration

When extending CBflow, keep these RACE behaviors in mind:

- **DAG from node_config**: RACE builds the DAG from node_config.tcl at runtime. Define `stages` and `dependencies,<stage>` correctly.
- **Status in SQLite DB**: Node status is tracked in `.race_<uid>.db`. Use `cbflow run status` to query.
- **File change detection**: RACE monitors input files. If a dependency output changes, downstream nodes auto-retrace.
- **Parallel subnodes**: If your flow has independent subnodes (like PV), RACE runs them in parallel automatically based on the dependency graph.
- **Dynamic subnodes**: For flows that need runtime subnode generation (like STA per-corner), implement a scenario handler and RACE will create subnodes from user_config.
- **Custom nodes**: Users can add nodes to your flow at run time via `cbflow run add-node`.

## 7. Test Your Changes

```bash
bin/cbflow-test-suite --verbose             # Full 994-test suite
bin/cbflow-test-suite --flow MYFLOW         # Test specific flow
bin/cbflow-test-suite --category 2          # RACE DAG/handler tests only
```

---

**Documentation Version**: 2.0.0
