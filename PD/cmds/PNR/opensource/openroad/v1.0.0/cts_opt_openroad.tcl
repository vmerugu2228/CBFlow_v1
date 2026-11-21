#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — cts_opt (opensource / openroad)
# Post-CTS setup + hold repair across the node's MMMC corners.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts_opt"
set NODE_NAME "cts_opt1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load {
    oss_load_stage cts1
    set_propagated_clock [all_clocks]
    estimate_parasitics -placement
}

flow_proc repair {
    global pnr
    repair_timing -setup -setup_margin [oss_get pnr oss,repair,setup_margin]
    repair_timing -hold  -hold_margin  [oss_get pnr oss,repair,hold_margin]
    detailed_placement
    check_placement
    estimate_parasitics -placement
    write_db [oss_stage_out cts_opt.odb]
    oss_write_qor cts_opt
}

flow_exec_all
exit
