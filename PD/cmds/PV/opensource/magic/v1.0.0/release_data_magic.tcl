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
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "release_data1"}]

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
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [oss_get project release,phase]]
    foreach _f {drc1/outputs/drc.rpt lvs1/outputs/lvs.rpt merge_data1/outputs/verification_summary.rpt} {
        ::CBFlow::Release::copy_file "$::run_dir/work/PV/$_f" reports/pv [file tail $_f]
    }
    foreach _n {drc1 lvs1} { ::CBFlow::Release::copy_glob "$::run_dir/work/PV/$_n/reports/*.rpt" reports/pv }
    # Signoff metrics + verdict for SmartGrid (attached to the exit it checked)
    set _fh [open "$::run_dir/work/PV/merge_data1/outputs/verification_summary.rpt"]; set _t [read $_fh]; close $_fh
    set _drc ""; set _lvs ""
    regexp -line {^drc_errors\s+(\d+)} $_t -> _drc
    regexp -line {^result\s+(.+)$} $_t -> _lvs
    set _ok [expr {$_drc ne "" && $_drc <= [oss_get pv signoff,max_drc]
                   && [regexp -- [oss_get pv signoff,lvs_pass] $_lvs]}]
    set _L [list "# category: drc" "DRC errors : $_drc" "# category: lvs" "LVS result : $_lvs" \
                 "# category: signoff" "Status : [expr {$_ok ? "PASS" : "FAIL"}]"]
    set _fh [open "$_dir/metrics.rpt" w]; puts $_fh [join $_L \n]; close $_fh
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "attach_to [oss_get pv input,release_tag]"
    close $_fh
    handle_info "PV reports released -> $_dir/reports/pv"
}

flow_exec_all
exit
