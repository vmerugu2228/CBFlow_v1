#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_CDC — cdc_report (opensource / container tclsh)
# CDC findings -> violations.csv (+ blocks opencdc could not analyse, info;
# an incomplete analysis is an error) and cdc_findings.rpt.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_CDC"
set STAGE_NAME "cdc_report"
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

flow_proc report {
    set _an "[cbflow_node_dir [oss_chain_node cdc_analyze]]"
    set _su "[cbflow_node_dir [oss_chain_node cdc_setup]]/outputs"
    rtl_py "$::REPORTS_DIR/collect.log" cdc-collect --json "$_an/outputs/cdc.json" --log "$_an/reports/cdc.log" \
        --sdc "$_su/cdc.sdc" -o [oss_stage_out violations.csv]
    file copy -force "$_an/outputs/cdc.json" "$::REPORTS_DIR/cdc_findings.json"
}

oss_exec_all
exit
