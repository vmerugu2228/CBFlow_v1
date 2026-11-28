#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — release_data (opensource / tclsh)
# Publish the LEC report: <release,path>/<phase>/<design>/<tag>/reports/lec/.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

set design_name [oss_get flow design_name]
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _c [oss_chain_node compare]
    set _rpt lec.rpt
    ::CBFlow::Release::copy_file "[cbflow_node_dir $_c]/outputs/$_rpt" reports/lec $_rpt
    ::CBFlow::Release::copy_glob "[cbflow_node_dir $_c]/reports/*.rpt" reports/lec
    # Signoff metrics + verdict for SmartGrid (attached to the exit it checked)
    set _fh [open "[cbflow_node_dir $_c]/outputs/$_rpt"]; set _t [read $_fh]; close $_fh
    set _res ""
    regexp -line {^result\s+(\S+)} $_t -> _res
    set _ok [regexp -- [oss_get lec signoff,result_pass] $_res]
    set _L [list "# category: lec" "LEC result : $_res" \
                 "Golden : [oss_get lec input,netlist_golden_release_tag]" \
                 "Revised : [oss_get lec input,netlist_revised_release_tag]" \
                 "# category: signoff" "Status : [expr {$_ok ? "PASS" : "FAIL"}]"]
    set _fh [open "$_dir/metrics.rpt" w]; puts $_fh [join $_L \n]; close $_fh
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "attach_to [oss_get lec input,netlist_revised_release_tag]"
    close $_fh
    handle_info "LEC report released -> $_dir/reports/lec"
}

flow_exec_all
exit
