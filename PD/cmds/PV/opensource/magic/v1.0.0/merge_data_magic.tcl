#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — merge_data (opensource / tclsh)
# Verification summary from the DRC and LVS stages.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "merge_data"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "merge_data1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc summarize {
    global design_name
    set _fh [open [oss_stage_out verification_summary.rpt] w]
    puts $_fh "PV verification summary — $design_name (Magic DRC + Netgen LVS)"
    foreach _n {drc1 lvs1} _f {drc.rpt lvs.rpt} {
        set _p "$::DIRS(run)/work/PV/$_n/outputs/$_f"
        if {[file exists $_p]} {
            set _ih [open $_p]; puts $_fh "\n== $_n\n[read $_ih]"; close $_ih
        } else {
            puts $_fh "\n== $_n\n(missing: $_p)"
        }
    }
    close $_fh
}

flow_exec_all
exit
