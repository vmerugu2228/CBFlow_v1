#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow UPF_CHECK — upf_report (opensource / container tclsh)
# Power-intent summary (domains, supplies, states) from the check report.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "UPF_CHECK"
set STAGE_NAME "upf_report"
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
    set _r "[cbflow_node_dir [oss_chain_node upf_check]]/reports/upf_check.rpt"
    file copy -force $_r "$::REPORTS_DIR/power_domains.rpt"
    oss_write_file [oss_stage_out upf_report.status] "DONE\n"
    handle_info "power domains [oss_report_value $_r {Power domains}], findings [oss_report_value $_r Findings]"
}

oss_exec_all
exit
