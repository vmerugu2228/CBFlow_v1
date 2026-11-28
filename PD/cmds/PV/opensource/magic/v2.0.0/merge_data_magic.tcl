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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: the drc and lvs nodes' results (outputs/drc.rpt, outputs/lvs.rpt)
flow_proc load_design {
    set ::pv_sections {}
    foreach _t {drc lvs} _f {drc.rpt lvs.rpt} {
        set _n [cbflow_dep_node $_t]
        set _p "[cbflow_node_dir $_n]/outputs/$_f"
        if {[file exists $_p]} {
            set _ih [open $_p]; lappend ::pv_sections "\n== $_n\n[read $_ih]"; close $_ih
        } else {
            lappend ::pv_sections "\n== $_n\n(missing: $_p)"
        }
    }
}

# No operation / report step: the summary is the stage's deliverable (save_design).

# Save the verification summary -> outputs/verification_summary.rpt
flow_proc save_design {
    global design_name
    set _fh [open [oss_stage_out verification_summary.rpt] w]
    puts $_fh "PV verification summary — $design_name (Magic DRC + Netgen LVS)"
    foreach _s $::pv_sections { puts $_fh $_s }
    close $_fh
}

flow_exec_all
exit
