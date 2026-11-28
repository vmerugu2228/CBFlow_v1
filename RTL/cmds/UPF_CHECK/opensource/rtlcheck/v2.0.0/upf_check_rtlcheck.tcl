#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow UPF_CHECK — upf_check (opensource / container tclsh)
# UPF against the elaborated RTL and the block spec (rtl_check.py upf-check):
# domains / elements, supplies, connections, primary supplies, port and PST
# states, isolation on crossings, domains / supplies vs the spec -> violations.csv.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "UPF_CHECK"
set STAGE_NAME "upf_check"
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

flow_proc check {
    rtl_py "$::REPORTS_DIR/upf_check.log" upf-check --upf "[cbflow_node_dir [oss_chain_node upf_parse]]/outputs/upf.upf" \
        --design "[cbflow_node_dir [oss_chain_node compile]]/outputs/design.json" --top [rtl_top] \
        --spec [oss_input spec] -o [oss_stage_out violations.csv] --report "$::REPORTS_DIR/upf_check.rpt"
}

oss_exec_all
exit
