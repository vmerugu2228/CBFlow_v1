#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M1_EXEC — signoff (opensource / container tclsh)
# M1 sign-off: pass rate, code / functional / vPlan coverage against
# project(dv,targets,M1) -> reports/dv_signoff.rpt (+ coverage, triage); a
# target not met fails the stage (no M1_EXIT release).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M1_EXEC"
set STAGE_NAME "signoff"
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
flow_proc signoff {
    set _ms [oss_get m1_exec oss,milestone]
    set _cm [cbflow_node_dir [oss_chain_node cov_merge]]
    dv_tool "$::REPORTS_DIR/signoff.log" signoff --metrics "$_cm/outputs/metrics.json" --milestone $_ms \
        --targets {*}[dv_targets $_ms] -o "$::REPORTS_DIR/dv_signoff.rpt"
    foreach _r [list "$_cm/reports/coverage.rpt" "[cbflow_node_dir [oss_chain_node triage]]/reports/triage.rpt"] {
        set _fh [open $_r]; set _t [read $_fh]; close $_fh
        set _fh [open "$::REPORTS_DIR/dv_signoff.rpt" a]; puts $_fh "\n$_t"; close $_fh
    }
    set _st [dv_status "$::REPORTS_DIR/dv_signoff.rpt"]
    oss_write_file [oss_stage_out signoff.status] "$_st\n"
    if {$_st ne "PASS"} { error "$_ms sign-off FAILED — $::REPORTS_DIR/dv_signoff.rpt" }
    handle_info "$_ms sign-off PASS"
}

oss_exec_all
exit
