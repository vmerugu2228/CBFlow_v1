#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 drc2 — Mentor Tessent
# DRC check — post-TPI. Compared to drc1 output; new violations fail validation.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "drc2"
set NODE_NAME "${STAGE_NAME}"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc drc_run_post_check {
    handle_info "Running post-TPI Tessent check_design_rules..."
    check_design_rules
    report_design_rule_violations > $::REPORTS_DIR/drc_post.rpt
    handle_info "DRC post-check report: $::REPORTS_DIR/drc_post.rpt"
}

flow_proc drc_delta_check {
    set pre_rpt "$::REPORTS_DIR/../drc1/drc_pre.rpt"
    set post_rpt "$::REPORTS_DIR/drc_post.rpt"
    set pre 0
    set post 0
    foreach {rpt var} [list $pre_rpt pre $post_rpt post] {
        if {[file exists $rpt]} {
            set fh [open $rpt r]
            set text [read $fh]
            close $fh
            set $var [regexp -all {^V:} $text]
        }
    }
    set threshold $::dft_insert_pass1(drc,new_violation_threshold)
    set new_viol [expr {$post > $pre ? $post - $pre : 0}]
    emit_metric drc_violation_count $post
    emit_metric drc_new_violations  $new_viol
    handle_info "DRC pre=$pre post=$post new=$new_viol (threshold=$threshold)"
    if {$new_viol > $threshold} {
        handle_error "DRC post-check introduced $new_viol new violations (>$threshold allowed)"
    }
}

flow_proc drc2_flow {
    handle_info "Executing DFT_INSERT_PASS1 drc2 flow..."
    flow_exec drc_run_post_check
    flow_exec drc_delta_check
    handle_info "DFT_INSERT_PASS1 drc2 completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec drc2_flow } else { puts "DFT_INSERT_PASS1 drc2 procedures loaded" }
exit
