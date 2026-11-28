#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/ATPG/<tag> (tag: ATPG_PREPD_EXIT for
# pd_phase pre, ATPG_POSTPD_EXIT for post, unless project(release,tag)):
# patterns/<d>.atpg.stil + <d>.patterns.json + <d>_scan_tb.v (the testbench
# GLS_SCAN_MBIST runs, flow_input_handshake(GLS_SCAN_MBIST,patterns)) +
# <d>_macro_stubs.v, scan/<d>.scandef of the ATPG netlist, and the reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
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
    set _exit [expr {[oss_get atpg pd_phase] eq "post" ? "ATPG_POSTPD_EXIT" : "ATPG_PREPD_EXIT"}]
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase] $_exit]
    set _ex "[cbflow_node_dir [oss_chain_node export_patterns]]/outputs"
    ::CBFlow::Release::copy_file "$_ex/scan_tb.v" {*}[dft_release_name GLS_SCAN_MBIST patterns]
    ::CBFlow::Release::copy_file "$_ex/patterns.stil"  patterns ${design_name}.atpg.stil
    ::CBFlow::Release::copy_file "$_ex/patterns.json"  patterns ${design_name}.patterns.json
    ::CBFlow::Release::copy_file "$_ex/macro_stubs.v"  patterns ${design_name}_macro_stubs.v
    ::CBFlow::Release::copy_file "[cbflow_node_dir [oss_chain_node init_atpg]]/outputs/scan.scandef" scan ${design_name}.scandef
    foreach _t {init_atpg pattern_gen fault_sim coverage_report zd_pattern_sim pattern_signoff} {
        set _n [oss_chain_node $_t]
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*sim.log" reports
    }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    dft_write [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\nexit $_exit\n"
    handle_info "Released $design_name ATPG patterns -> $_dir"
}

dft_exec_all
exit
