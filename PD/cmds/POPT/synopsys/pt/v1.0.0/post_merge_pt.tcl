#!/usr/bin/env tclsh
# CBFlow POPT post_merge - Synopsys PrimeTime

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "POPT"
set STAGE_NAME "post_merge"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc validate_merged_timing {
    handle_info "Validating merged timing across all corners..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    # Full timing update to ensure merged state is current
    update_timing -full

    # Resolve config-driven defaults
    set _max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}]
    set _sig_digits [expr {[info exists popt(analysis,significant_digits)] ? $popt(analysis,significant_digits) : 4}]

    # Setup timing analysis (max delay)
    handle_info "Running setup (max delay) analysis..."
    report_timing -delay max -max_paths $_max_paths -nworst 5 \
        -significant_digits $_sig_digits \
        > "$::REPORTS_DIR/setup_timing.rpt"

    # Hold timing analysis (min delay)
    handle_info "Running hold (min delay) analysis..."
    report_timing -delay min -max_paths $_max_paths -nworst 5 \
        -significant_digits $_sig_digits \
        > "$::REPORTS_DIR/hold_timing.rpt"

    # Transition violations
    report_timing -delay max -max_paths $_max_paths -group *transition* \
        > "$::REPORTS_DIR/transition_violations.rpt"

    # Capacitance violations
    report_timing -delay max -max_paths $_max_paths -group *capacitance* \
        > "$::REPORTS_DIR/capacitance_violations.rpt"

    # Slack histogram
    report_timing -delay max -slack_lesser_than 0 -max_paths $_max_paths \
        > "$::REPORTS_DIR/negative_slack_paths.rpt"

    handle_info "Merged timing validation completed"
}

# ---------------------------------------------------------------------------
# flow_proc: check_constraints
# Check all constraint violations across merged scenarios
# ---------------------------------------------------------------------------
flow_proc check_constraints {
    handle_info "Checking constraints across merged data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # All constraint violations
    report_constraint -all > "$rpt_dir/all_constraints.rpt"

    # Violators only
    report_constraint -all_violators > "$rpt_dir/constraint_violators.rpt"

    # Max transition violations
    report_constraint -max_transition -all_violators \
        > "$rpt_dir/max_transition_violators.rpt"

    # Max capacitance violations
    report_constraint -max_capacitance -all_violators \
        > "$rpt_dir/max_capacitance_violators.rpt"

    # Max fanout violations
    report_constraint -max_fanout -all_violators \
        > "$rpt_dir/max_fanout_violators.rpt"

    # Clock gating check
    report_clock_gating -verbose > "$rpt_dir/clock_gating_check.rpt"

    # Case analysis check
    report_case_analysis > "$rpt_dir/case_analysis.rpt"

    handle_info "Constraint checking completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_post_merge_report
# Generate consolidated post-merge QoR and summary reports
# ---------------------------------------------------------------------------
flow_proc generate_post_merge_report {
    handle_info "Generating post-merge summary reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # QoR report
    report_qor > "$rpt_dir/post_merge_qor.rpt"

    # Design statistics
    report_design -physical > "$rpt_dir/design_stats.rpt"

    # Power summary
    report_power > "$rpt_dir/post_merge_power.rpt"

    # Area summary
    report_area -hierarchy > "$rpt_dir/post_merge_area.rpt"

    # Create consolidated summary
    set fp [open "$res_dir/post_merge_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "POPT Post-Merge Validation Summary - PrimeTime"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Validation steps completed:"
    puts $fp "  1. Setup timing analysis (max delay)"
    puts $fp "  2. Hold timing analysis (min delay)"
    puts $fp "  3. Constraint violation checking"
    puts $fp "  4. QoR reporting"
    puts $fp ""
    puts $fp "Reports generated:"
    foreach f [glob -nocomplain "$rpt_dir/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Post-merge reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all post_merge flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc post_merge_flow {
    handle_info "Executing POPT post_merge flow..."
    flow_exec validate_merged_timing
    flow_exec check_constraints
    flow_exec generate_post_merge_report
    handle_info "POPT post_merge completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec post_merge_flow } else { puts " POPT post_merge procedures loaded" }

# Exit tool after stage completion
exit
