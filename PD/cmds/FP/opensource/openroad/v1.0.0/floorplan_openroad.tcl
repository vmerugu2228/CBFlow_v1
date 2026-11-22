#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — floorplan (opensource / openroad)
# Die / core, rows, tracks; child hard-macro placement (rail-pitch snapped
# for DL2 children); IO pins; well taps / endcaps.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "floorplan"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Previous stage's database, liberty from the init_design node's MMMC views.
proc fp_load {} {
    global blocks
    set_thread_count [oss_get fp oss,threads]
    oss_read_corners [oss_chain_node init_design] $blocks
    read_db [oss_prev_odb [oss_upstream_node]]
}

flow_proc floorplan {
    global blocks
    fp_load
    oss_fp_floorplan
    oss_fp_place_macros $blocks
    oss_fp_pins_taps
    oss_report "$::REPORTS_DIR/design_area.rpt" report_design_area
}

flow_proc save {
    write_db  [oss_stage_out floorplan.odb]
    write_def [oss_stage_out floorplan.def]
}

flow_exec_all
exit
