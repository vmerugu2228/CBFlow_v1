#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — powerplan (opensource / openroad)
# Power intent (UPF supplies, domains, global connections) and the
# hierarchical power grid (leaf / middle / top / standalone).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "powerplan"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: previous stage's database, liberty from the init_design node's MMMC views
flow_proc load_design {
    global blocks
    set_thread_count [oss_get fp oss,threads]
    oss_read_corners [oss_chain_node init_design] $blocks
    read_db [oss_prev_odb [oss_upstream_node]]
}

# Power intent (UPF) + hierarchical power grid + connectivity check
flow_proc power_grid {
    global design_name blocks
    oss_fp_power $design_name $blocks
}

# No report step: oss_apply_upf writes upf_subset.rpt as it applies the
# intent (kept there so it exists when the grid check fails); PDN results go to the log.

# Save the database + DEF with the power grid
flow_proc save_design {
    write_db  [oss_stage_out powerplan.odb]
    write_def [oss_stage_out powerplan.def]
}

flow_exec_all
exit
