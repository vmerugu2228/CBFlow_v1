#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_LINT — waiver_apply (opensource / container tclsh)
# Waivers (<arr>(oss,waivers): rule / file / line / message, reason, owner,
# expires) applied to the findings -> violations_final.csv, waivers.rpt
# (expired / malformed / unused waivers listed).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_LINT"
set STAGE_NAME "waiver_apply"
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

flow_proc waive {
    rtl_waive "[cbflow_node_dir [oss_chain_node lint]]/outputs/violations.csv"
}

oss_exec_all
exit
