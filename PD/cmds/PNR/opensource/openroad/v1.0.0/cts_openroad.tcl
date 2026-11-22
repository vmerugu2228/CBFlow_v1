#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — cts (opensource / openroad)
# Clock tree synthesis on the placed database.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load { oss_load_stage [oss_upstream_node] }

flow_proc clock_tree {
    clock_tree_synthesis -root_buf [oss_trk clock_root_buffer] -buf_list [oss_trk clock_buffers] \
        -apply_ndr [oss_get pnr oss,cts,apply_ndr]
    set_propagated_clock [all_clocks]
    repair_clock_nets
    detailed_placement
    estimate_parasitics -placement
    oss_report "$::REPORTS_DIR/cts.rpt" report_cts
    write_db [oss_stage_out cts.odb]
    oss_write_qor cts
}

flow_exec_all
exit
