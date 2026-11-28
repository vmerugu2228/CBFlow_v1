#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_FUNC — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/<FLOW>/<netlist tag> (signoff-style:
# the tag of the netlist release it verified, unless project(release,tag)):
# the simulation / coverage reports and the testbench that ran.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "GLS_FUNC"
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
    foreach _t {init_sim compile run_sim coverage} {
        set _n [oss_chain_node $_t]
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/run_sim.log" reports
    }
    set _tb [dft_input [oss_get [oss_flow_arr] oss,tb_input]]
    ::CBFlow::Release::copy_file $_tb sim [file tail $_tb]
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    dft_write [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name $::FLOW_TYPE results -> $_dir"
}

dft_exec_all
exit
