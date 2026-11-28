#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow TB_SETUP — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/TB_SETUP/<tag> (TB_SETUP_EXIT unless
# project(release,tag)): tb/ — every testbench file, tb.f rewritten to the
# released paths (handshake M<n>_EXEC,tb), rtl.f — spec/<d>_vplan.xlsx (the
# vPlan the milestones close, handshake M<n>_EXEC,vplan) and the reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "TB_SETUP"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_DV_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dv_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _tb "[cbflow_node_dir [oss_chain_node tb_gen]]/outputs/tb"
    foreach _f [glob -directory $_tb *] {
        if {[file tail $_f] ne "tb.f"} { ::CBFlow::Release::copy_file $_f tb [file tail $_f] }
    }
    set _fh [open "$_tb/tb.f"]; set _t [read $_fh]; close $_fh
    oss_write_file "$::WORK_DIR/outputs/tb.f" [string map [list $_tb "$_dir/tb"] $_t]
    ::CBFlow::Release::copy_file "$::WORK_DIR/outputs/tb.f" {*}[oss_release_name M1_EXEC tb]
    ::CBFlow::Release::copy_file [oss_input vplan] {*}[oss_release_name M1_EXEC vplan]
    foreach _t {tb_gen sanity} {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node $_t]]/reports/*.rpt" reports
    }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    oss_write_file [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name UVM testbench -> $_dir"
}

oss_exec_all
exit
