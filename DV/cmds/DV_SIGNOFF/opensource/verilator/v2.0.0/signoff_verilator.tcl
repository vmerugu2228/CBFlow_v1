#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV_SIGNOFF — signoff (opensource / container tclsh)
# DV sign-off: every DV exit of the phase released with sign-off PASS and the
# M4 metrics (input metrics) with every vPlan feature closed or waived ->
# reports/dv_signoff.rpt; anything open fails the stage.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DV_SIGNOFF"
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
    set _fh [open "[cbflow_node_dir [oss_chain_node collect]]/reports/collect.rpt"]; set _c [read $_fh]; close $_fh
    # exit rows "  <EXIT> : <status> <dir>" whose status is not PASS
    set _bad 0
    foreach _l [split $_c \n] {
        if {[regexp {^\s+(\S+)\s*:\s*(\S+)} $_l -> _e _st] && $_st ne "PASS"} { incr _bad }
    }
    set _fh [open [oss_input metrics]]; set _m [read $_fh]; close $_fh
    regexp {"plan_coverage":\s*([\d.]+)} $_m -> _pc
    regexp {"pass_rate":\s*([\d.]+)} $_m -> _pr
    set _ok [expr {$_bad == 0 && $_pc >= 100.0}]
    oss_write_file "$::REPORTS_DIR/dv_signoff.rpt" [join [list "DV sign-off — $::design_name [cbflow_run_phase]" \
        "  Exits not PASS  : $_bad" "  M4 pass rate    : $_pr" "  vPlan coverage  : $_pc" \
        "  Status          : [expr {$_ok ? "PASS" : "FAIL"}]" "" $_c] \n]
    oss_write_file [oss_stage_out signoff.status] "[expr {$_ok ? "PASS" : "FAIL"}]\n"
    if {!$_ok} { error "DV sign-off FAILED — $::REPORTS_DIR/dv_signoff.rpt" }
    handle_info "DV sign-off PASS"
}

oss_exec_all
exit
