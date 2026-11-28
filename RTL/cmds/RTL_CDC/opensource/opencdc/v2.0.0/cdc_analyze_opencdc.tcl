#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_CDC — cdc_analyze (opensource / container tclsh → opencdc)
# opencdc on the converted RTL (profile rtl_cdc(oss,cdc,profile), clocks from
# cdc.sdc) -> cdc.json + cdc.log (its notes, e.g. blocks not analysed).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_CDC"
set STAGE_NAME "cdc_analyze"
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

flow_proc analyze {
    set _su "[cbflow_node_dir [oss_chain_node cdc_setup]]/outputs"
    catch {oss_run "$::REPORTS_DIR/cdc.log" opencdc check --top [rtl_top] --format json \
        --profile [oss_get rtl_cdc oss,cdc,profile] --constraints "$_su/cdc.sdc" \
        --out [oss_stage_out cdc.json] [rtl_init_out stubs.v] "$_su/design_sv2v.v"}
    if {![file exists [oss_stage_out cdc.json]]} { error "opencdc wrote no report — $::REPORTS_DIR/cdc.log" }
}

oss_exec_all
exit
