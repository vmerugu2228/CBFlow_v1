#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — export_data (opensource / openroad)
# Floorplan deliverables for PNR: DEF (die, rows, tracks, placed macros,
# pins, taps, power grid), database, netlist (with physical cells), SDC, UPF.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "export_data"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "export_data1"}]

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
    read_sdc [oss_sdc_file]          ;# timing estimate for the FP_EXIT checklist
}

flow_proc export {
    global design_name
    fp_load
    write_def     [oss_stage_out final.def]
    write_db      [oss_stage_out final.odb]
    write_verilog [oss_stage_out final.v]
    file copy -force [oss_sdc_file] [oss_stage_out final.sdc]
    set _upf [lindex [glob -nocomplain "$::UPF_DIR/${design_name}.upf" "$::UPF_DIR/*.upf"] 0]
    if {$_upf ne ""} { file copy -force $_upf [oss_stage_out final.upf] }
    oss_report "$::REPORTS_DIR/design_area.rpt" report_design_area
    oss_checklist_safe fp
}

flow_exec_all
exit
