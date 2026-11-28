#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT — release_data (opensource / tclsh)
# Publish <release,path>/<phase>/<design>/SCAN_INSERT/<tag> (tag: the exit,
# SCAN_INSERT_EXIT, unless project(release,tag)): netlist/<d>.v,
# sdc/<d>.scan.sdc, def/<d>.scandef, scan/<d>.scan.json — the names ATPG reads
# (flow_input_handshake(ATPG,*)) — and the scan reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SCAN_INSERT"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _ex "[cbflow_node_dir [oss_chain_node scan_export]]/outputs"
    foreach {_src _input} {scan.v netlist scan.scandef scandef} {
        ::CBFlow::Release::copy_file "$_ex/$_src" {*}[dft_release_name ATPG $_input]
    }
    ::CBFlow::Release::copy_file "$_ex/scan.sdc"  sdc  ${design_name}.scan.sdc
    ::CBFlow::Release::copy_file "$_ex/scan.json" scan ${design_name}.scan.json
    foreach _n [list [oss_chain_node init_scan] [oss_chain_node scan_stitch] [oss_chain_node scan_check]] {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports
    }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    dft_write [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name scan structure -> $_dir"
}

dft_exec_all
exit
