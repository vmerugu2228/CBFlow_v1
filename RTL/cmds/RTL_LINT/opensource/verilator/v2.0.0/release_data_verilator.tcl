#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_LINT — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/RTL_LINT/<tag> (LINT_SIGNOFF unless
# project(release,tag)): rtl/ — the lint-clean sources and <d>.f at their
# released paths (SYNTH reads it: handshake SYNTH,rtl, SystemVerilog through
# the slang front end) — and the lint reports / violations / waivers.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_LINT"
set STAGE_NAME "release_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_RTL_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_rtl_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _rel {}
    foreach _f [rtl_init_sources] {
        ::CBFlow::Release::copy_file $_f rtl [file tail $_f]
        lappend _rel "$_dir/rtl/[file tail $_f]"
    }
    oss_write_file "$::WORK_DIR/outputs/${design_name}.f" "[join $_rel \n]\n"
    ::CBFlow::Release::copy_file "$::WORK_DIR/outputs/${design_name}.f" {*}[oss_release_name SYNTH rtl]
    ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node report]]/reports/*.rpt" reports
    ::CBFlow::Release::copy_file "[cbflow_node_dir [oss_chain_node waiver_apply]]/outputs/violations_final.csv" reports violations_final.csv
    rtl_release_reports
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    oss_write_file [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name lint-clean RTL -> $_dir"
}

oss_exec_all
exit
