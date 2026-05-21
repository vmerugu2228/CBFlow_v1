#!/usr/bin/env tclsh
# CBFlow STA timing - Synopsys PrimeTime

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc configure_timing {
    handle_info "Configuring timing analysis settings..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/timing"
    file mkdir "$::REPORTS_DIR"

    # Set timing analysis mode
    if {[info exists ::sta(ANALYSIS_TYPE)]} {
        set_app_var timing_report_unconstrained_paths true
        handle_info "Analysis type: $::sta(ANALYSIS_TYPE)"
    }

    # Enable POCV/AOCV based on ocv_mode config
    set_app_var timing_pocvm_enable_analysis [expr {$sta(analysis,ocv_mode) eq "pocv"}]
    if {[expr {$sta(analysis,ocv_mode) eq "pocv"}]} {
        handle_info "POCV analysis enabled"
    }
    set_app_var timing_aocvm_enable_analysis [expr {$sta(analysis,ocv_mode) eq "aocv"}]
    if {[expr {$sta(analysis,ocv_mode) eq "aocv"}]} {
        handle_info "AOCV analysis enabled"
    }

    # Set SI analysis options
    set_app_var si_enable_analysis $sta(analysis,si_aware)
    if {$sta(analysis,si_aware)} {
        set_app_var si_xtalk_delay_analysis_mode bottom_up
        handle_info "Signal integrity analysis enabled"
    }

    # Set derating factors
    if {[info exists ::sta(DERATE_EARLY)]} {
        set_timing_derate -early $::sta(DERATE_EARLY)
    }
    if {[info exists ::sta(DERATE_LATE)]} {
        set_timing_derate -late $::sta(DERATE_LATE)
    }

    # Set clock uncertainty
    if {[info exists ::sta(CLOCK_UNCERTAINTY_SETUP)]} {
        set_clock_uncertainty -setup $::sta(CLOCK_UNCERTAINTY_SETUP) [all_clocks]
    }
    if {[info exists ::sta(CLOCK_UNCERTAINTY_HOLD)]} {
        set_clock_uncertainty -hold $::sta(CLOCK_UNCERTAINTY_HOLD) [all_clocks]
    }

    # Set max paths for reporting
    set ::sta_max_paths $sta(analysis,max_paths)

    handle_info "Timing analysis configuration completed"
}

# ---------------------------------------------------------------------------
# flow_proc: run_sta
# Execute full static timing analysis with setup and hold checks
# ---------------------------------------------------------------------------
flow_proc run_sta {
    handle_info "Running static timing analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    if {![info exists ::sta_max_paths]} { set ::sta_max_paths $sta(analysis,max_paths) }

    # Full timing update
    update_timing -full
    handle_info "Timing updated"

    # Setup (max delay) analysis
    handle_info "Running setup analysis..."
    report_timing -delay max -max_paths $::sta_max_paths -nworst 5 \
        -significant_digits $sta(analysis,significant_digits) \
        > "$rpt_dir/setup_timing.rpt"

    # Hold (min delay) analysis
    handle_info "Running hold analysis..."
    report_timing -delay min -max_paths $::sta_max_paths -nworst 5 \
        -significant_digits $sta(analysis,significant_digits) \
        > "$rpt_dir/hold_timing.rpt"

    # Path group analysis
    report_timing -delay max -max_paths $sta(analysis,max_paths) -group reg2reg \
        > "$rpt_dir/reg2reg_timing.rpt"
    report_timing -delay max -max_paths $sta(analysis,max_paths) -group in2reg \
        > "$rpt_dir/in2reg_timing.rpt"
    report_timing -delay max -max_paths $sta(analysis,max_paths) -group reg2out \
        > "$rpt_dir/reg2out_timing.rpt"

    # Clock domain crossing paths
    report_timing -delay max -max_paths $sta(analysis,max_paths) -path_type full_clock \
        > "$rpt_dir/clock_domain_timing.rpt"

    # Clock latency and skew
    report_clock_timing -type skew > "$rpt_dir/clock_skew.rpt"
    report_clock_timing -type latency > "$rpt_dir/clock_latency.rpt"

    # QoR summary
    report_qor > "$rpt_dir/timing_qor.rpt"

    handle_info "STA analysis completed"
}

# ---------------------------------------------------------------------------
# flow_proc: check_violations
# Check and categorize all timing violations
# ---------------------------------------------------------------------------
flow_proc check_violations {
    handle_info "Checking timing violations..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # All constraint violators
    report_constraint -all_violators > "$rpt_dir/violations.rpt"

    # Max transition violations
    report_constraint -max_transition -all_violators \
        > "$rpt_dir/max_transition_violations.rpt"

    # Max capacitance violations
    report_constraint -max_capacitance -all_violators \
        > "$rpt_dir/max_capacitance_violations.rpt"

    # Max fanout violations
    report_constraint -max_fanout -all_violators \
        > "$rpt_dir/max_fanout_violations.rpt"

    # Negative slack paths
    report_timing -delay max -slack_lesser_than 0 -max_paths $sta(analysis,max_paths) \
        > "$rpt_dir/negative_slack_setup.rpt"
    report_timing -delay min -slack_lesser_than 0 -max_paths $sta(analysis,max_paths) \
        > "$rpt_dir/negative_slack_hold.rpt"

    # Noise violations (if SI enabled)
    if {[info exists ::sta(ENABLE_SI)] && $::sta(ENABLE_SI)} {
        report_noise -all_violators > "$rpt_dir/noise_violations.rpt"
        handle_info "SI noise violation report generated"
    }

    # Parse violations for summary
    set viol_file "$rpt_dir/violations.rpt"
    if {[file exists $viol_file]} {
        set fp [open $viol_file r]
        set content [read $fp]
        close $fp
        if {[string match "*VIOLATED*" $content]} {
            handle_warning "Timing violations detected - review $viol_file"
        } else {
            handle_info "No timing violations found"
        }
    }

    handle_info "Violation checking completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_report
# Generate consolidated STA summary report
# ---------------------------------------------------------------------------
flow_proc generate_report {
    handle_info "Generating STA summary report..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/timing"

    # Design summary
    report_design > "$rpt_dir/design_summary.rpt"

    # Create results summary
    set fp [open "$res_dir/timing.rpt" w]
    puts $fp "================================================================"
    puts $fp "STA Timing Analysis Summary - PrimeTime"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Analysis steps:"
    puts $fp "  1. Timing configuration (OCV, SI, derating)"
    puts $fp "  2. Setup analysis (max delay)"
    puts $fp "  3. Hold analysis (min delay)"
    puts $fp "  4. Violation checking"
    puts $fp ""
    puts $fp "Reports generated:"
    foreach f [glob -nocomplain "$rpt_dir/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    # Create violations summary
    set fp2 [open "$res_dir/violations.rpt" w]
    puts $fp2 "Violations Summary - [clock format [clock seconds]]"
    puts $fp2 "================================================================"
    puts $fp2 "See detailed reports in: $rpt_dir/"
    close $fp2

    handle_info "STA summary reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all timing flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc timing_flow {
    handle_info "Executing STA timing flow..."
    flow_exec configure_timing
    flow_exec run_sta
    flow_exec check_violations
    flow_exec generate_report
    handle_info "STA timing completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec timing_flow } else { puts " STA timing procedures loaded" }
exit
