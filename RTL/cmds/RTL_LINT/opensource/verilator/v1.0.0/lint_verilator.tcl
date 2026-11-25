#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_LINT — lint (opensource / container tclsh → verilator / verible)
# Verilator --lint-only (rtl_lint(oss,verilator,flags), SARIF diagnostics)
# over the whole design, Verible style lint over the designer RTL (generated
# files skipped), merged with the slang findings into violations.csv
# (generated RTL: status excluded; stubs dropped).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_LINT"
set STAGE_NAME "lint"
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

flow_proc lint {
    set _src [rtl_init_sources]
    set _gen [oss_get rtl_lint oss,generated_globs]
    catch {oss_run "$::REPORTS_DIR/verilator.log" verilator --lint-only {*}[oss_get_opt rtl_lint oss,verilator,flags] \
        --top-module [rtl_top] --diagnostics-sarif-output [oss_stage_out verilator.sarif] [rtl_init_out stubs.v] {*}$_src}
    if {![file exists [oss_stage_out verilator.sarif]]} { error "Verilator wrote no diagnostics — $::REPORTS_DIR/verilator.log" }
    set _own {}
    foreach _f $_src {
        set _g 0
        foreach _p $_gen { if {[string match $_p [file tail $_f]]} { set _g 1 } }
        if {!$_g} { lappend _own $_f }
    }
    set _rules [oss_get_opt rtl_lint oss,verible,rules]
    if {[llength $_own]} {
        catch {oss_run "$::REPORTS_DIR/verible.log" verible-verilog-lint {*}[expr {$_rules ne "" ? [list --rules=$_rules] : {}}] {*}$_own}
    }
    set _slang "[cbflow_node_dir [oss_chain_node compile]]/reports/slang.log"
    rtl_py "$::REPORTS_DIR/collect.log" lint-collect --verilator-sarif [oss_stage_out verilator.sarif] \
        --slang-log $_slang --verible-log "$::REPORTS_DIR/verible.log" \
        --verible-severity [oss_get rtl_lint oss,verible,severity] --exclude stubs.v --generated {*}$_gen \
        -o [oss_stage_out violations.csv]
}

oss_exec_all
exit
