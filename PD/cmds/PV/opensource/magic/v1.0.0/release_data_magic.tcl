#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — release_data (opensource / tclsh)
# Publish the PV reports next to the block's SYNTH_PNR release
# (<release,path>/<phase>/<design>/<tag>/reports/pv/).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::run_dir [oss_get project release,phase]]
    foreach _f {drc1/outputs/drc.rpt lvs1/outputs/lvs.rpt merge_data1/outputs/verification_summary.rpt} {
        ::CBFlow::Release::copy_file "$::run_dir/work/PV/$_f" reports/pv [file tail $_f]
    }
    foreach _n {drc1 lvs1} { ::CBFlow::Release::copy_glob "$::run_dir/work/PV/$_n/reports/*.rpt" reports/pv }
    set _fh [open [oss_stage_out release.manifest] w]; puts $_fh "release_dir $_dir"; close $_fh
    handle_info "PV reports released -> $_dir/reports/pv"
}

flow_exec_all
exit
