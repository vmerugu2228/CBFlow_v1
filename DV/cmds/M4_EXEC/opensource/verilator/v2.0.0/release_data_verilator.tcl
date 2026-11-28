#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M4_EXEC — release_data (opensource / container tclsh)
# Publish <release,path>/<phase>/<design>/M4_EXEC/<tag> (M4_EXIT unless
# project(release,tag)): reports — sign-off, coverage, regression, triage,
# vPlan status (plan.csv), metrics.json (handshake DV_SIGNOFF,metrics),
# results.csv — and data/merged.dat (the merged coverage database).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M4_EXEC"
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
    foreach _t {regress cov_merge triage signoff} {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node $_t]]/reports/*.rpt" reports
    }
    set _cm "[cbflow_node_dir [oss_chain_node cov_merge]]/outputs"
    ::CBFlow::Release::copy_file "$_cm/metrics.json" reports metrics.json
    ::CBFlow::Release::copy_file "$_cm/plan.csv" reports plan.csv
    ::CBFlow::Release::copy_file "[cbflow_node_dir [oss_chain_node regress]]/outputs/results.csv" reports results.csv
    ::CBFlow::Release::copy_file "$_cm/merged.dat" data merged.dat
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    oss_write_file [oss_stage_out release.manifest] "release_dir $_dir\ndesign $design_name\n"
    handle_info "Released $design_name M4 -> $_dir"
}

oss_exec_all
exit
