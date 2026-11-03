#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 tpi — Mentor Tessent
# Test-point insertion to resolve pre-TPI DRC violations + coverage boost.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "tpi"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc tpi_apply {
    if {![string is true -strict $::dft_insert_pass1(tpi,enabled)]} {
        handle_info "TPI disabled — skipping"
        return
    }
    set mode   $::dft_insert_pass1(tpi,mode)
    set target $::dft_insert_pass1(tpi,coverage_target)
    handle_info "Inserting test points (mode=$mode, coverage target=$target%)..."
    add_test_points -mode $mode -coverage_target $target
    report_test_points > $::REPORTS_DIR/tpi.rpt
    handle_info "TPI report: $::REPORTS_DIR/tpi.rpt"
}

flow_proc tpi_metrics {
    set rpt "$::REPORTS_DIR/tpi.rpt"
    set count 0
    if {[file exists $rpt]} {
        set fh [open $rpt r]
        set text [read $fh]
        close $fh
        set count [regexp -all {^TP:} $text]
    }
    emit_metric test_points_inserted $count
    handle_info "Test points inserted: $count"
}

flow_proc tpi_flow {
    handle_info "Executing DFT_INSERT_PASS1 tpi flow..."
    flow_exec tpi_apply
    flow_exec tpi_metrics
    handle_info "DFT_INSERT_PASS1 tpi completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec tpi_flow } else { puts "DFT_INSERT_PASS1 tpi procedures loaded" }
exit
