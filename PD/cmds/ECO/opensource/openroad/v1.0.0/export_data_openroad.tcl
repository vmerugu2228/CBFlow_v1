#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO — export_data (opensource / tclsh)
# The signoff node's deliverables into outputs/ and the ECO'd layout streamed
# to GDS by KLayout (the PNR recipe: oss_export_views / oss_def2gds_script).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
set STAGE_NAME "export_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_design {
    global blocks
    set _so [oss_upstream_node]
    set _out "$::WORK_DIR/outputs"
    file mkdir $_out
    foreach _f {final.def final.v final.lvs.v final.lef final.cdl final.sdc final.odb} {
        file copy -force [oss_node_output $_so $_f] "$_out/$_f"
    }
    foreach _f [glob -nocomplain "[cbflow_node_dir $_so]/outputs/final__*.lib" "[cbflow_node_dir $_so]/outputs/final_*.spef" "[cbflow_node_dir $_so]/outputs/final.scandef"] {
        file copy -force $_f $_out
    }
    set ::export_def "$_out/final.def"
    lassign [oss_export_views $blocks] ::export_lefs ::export_gds
}

flow_proc stream_out {
    global design_name
    oss_def2gds_script "$::WORK_DIR/def2gds.py" $design_name $::export_def \
        $::export_lefs $::export_gds [oss_stage_out final.gds] eco
}

flow_proc save_design {
    global flow
    set _klayout [oss_get eco oss,export,klayout_batch]
    set _py "$::WORK_DIR/def2gds.py"
    if {[is_true $flow(test_mode)]} {
        puts "  TEST_CMD: $_klayout $_py"
    } else {
        set _log "$::REPORTS_DIR/export_data_klayout.log"
        if {[catch {exec {*}$_klayout $_py >& $_log} _err]} {
            error "KLayout DEF->GDS failed (see $_log): $_err"
        }
        handle_info [exec tail -1 $_log]
    }
}

flow_exec_all
exit
