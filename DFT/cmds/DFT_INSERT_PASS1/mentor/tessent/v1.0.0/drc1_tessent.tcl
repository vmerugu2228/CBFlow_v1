#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 drc1 — Mentor Tessent
# DRC check — pre-TPI. Any violation fails validation per drc,level=strict.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "drc1"
set NODE_NAME "${STAGE_NAME}"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc drc_run_check {
    handle_info "Running Tessent check_design_rules..."
    check_design_rules
    report_design_rule_violations > $::REPORTS_DIR/drc_pre.rpt
    handle_info "DRC pre-check report: $::REPORTS_DIR/drc_pre.rpt"
}

flow_proc drc_count_and_report {
    set rpt "$::REPORTS_DIR/drc_pre.rpt"
    set count 0
    if {[file exists $rpt]} {
        set fh [open $rpt r]
        set text [read $fh]
        close $fh
        # Count violation lines — standard Tessent format uses "V:" prefix.
        set count [regexp -all {^V:} $text]
    }
    emit_metric drc_violation_count $count
    handle_info "DRC pre-check: $count violations"
    if {$count > 0 && $::dft_insert_pass1(drc,level) eq "strict"} {
        handle_info "WARNING: $count DRC violations in strict mode — TPI stage must resolve them"
    }
}

flow_proc drc1_flow {
    handle_info "Executing DFT_INSERT_PASS1 drc1 flow..."
    flow_exec drc_run_check
    flow_exec drc_count_and_report
    handle_info "DFT_INSERT_PASS1 drc1 completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec drc1_flow } else { puts "DFT_INSERT_PASS1 drc1 procedures loaded" }
exit
