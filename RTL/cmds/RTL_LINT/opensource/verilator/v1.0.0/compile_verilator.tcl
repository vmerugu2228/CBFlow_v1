#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_LINT — compile (opensource / container tclsh)
# Elaboration with slang (IEEE 1800 front end) from the top: errors and
# warnings go to the findings (lint stage); an elaboration error is reported,
# the sign-off fails on it.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_LINT"
set STAGE_NAME "compile"
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

flow_proc elaborate {
    set _rc [catch {oss_run "$::REPORTS_DIR/slang.log" slang --top [rtl_top] [rtl_init_out stubs.v] {*}[rtl_init_sources]} _e]
    set _fh [open "$::REPORTS_DIR/slang.log"]; set _t [read $_fh]; close $_fh
    regexp {Build (?:succeeded|failed): (\d+) errors?, (\d+) warnings?} $_t -> _ne _nw
    oss_write_file [oss_stage_out compile.status] "[expr {$_rc ? "FAIL" : "PASS"}]\n"
    handle_info "slang: [expr {[info exists _ne] ? "$_ne error(s), $_nw warning(s)" : "see $::REPORTS_DIR/slang.log"}]"
}

oss_exec_all
exit
