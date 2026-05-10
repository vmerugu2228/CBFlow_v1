#!/usr/bin/env tclsh
# CBFlow POPT post_merge - Synopsys Power Compiler | Post-merge validation
set run_dir $::env(CBFLOW_RUN_DIR)
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/POPT/post_merge/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global popt project tech flow
handle_info "Starting POPT post_merge with Synopsys Power Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/POPT/post_merge"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: validate_results
# Validate post-optimization timing and power results
# ---------------------------------------------------------------------------
flow_proc validate_results {
    handle_info "Validating Power Compiler post-merge results..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    # Full timing update
    update_timing -full

    # Resolve config-driven defaults
    set _max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}]

    # Setup timing
    report_timing -delay max -max_paths $_max_paths -nworst 5 \
        > "$::REPORTS_DIR/setup_timing.rpt"

    # Hold timing
    report_timing -delay min -max_paths $_max_paths -nworst 5 \
        > "$::REPORTS_DIR/hold_timing.rpt"

    # Constraint violations
    report_constraint -all_violators > "$::REPORTS_DIR/violations.rpt"

    # Max transition
    report_constraint -max_transition -all_violators \
        > "$::REPORTS_DIR/max_transition.rpt"

    # Max capacitance
    report_constraint -max_capacitance -all_violators \
        > "$::REPORTS_DIR/max_capacitance.rpt"

    # Power summary after merge
    report_power -hierarchy > "$::REPORTS_DIR/power_hier.rpt"
    report_power > "$::REPORTS_DIR/power_summary.rpt"

    # Area check
    report_area -hierarchy > "$::REPORTS_DIR/area.rpt"

    # QoR
    report_qor > "$::REPORTS_DIR/qor.rpt"

    # Check for timing violations
    set viol_file "$::REPORTS_DIR/violations.rpt"
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

    handle_info "Post-merge validation completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_report
# Generate consolidated post-merge summary report
# ---------------------------------------------------------------------------
flow_proc generate_report {
    handle_info "Generating Power Compiler post-merge report..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # Design stats
    report_design -physical > "$::REPORTS_DIR/$1"

    # Clock gating summary
    report_clock_gating -summary > "$::REPORTS_DIR/$1"

    # Vt distribution
    report_threshold_voltage_group > "$::REPORTS_DIR/$1"

    # Summary
    set fp [open "$res_dir/pc_post_merge_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "Power Compiler Post-Merge Summary"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Validation checks:"
    puts $fp "  1. Setup timing (max delay)"
    puts $fp "  2. Hold timing (min delay)"
    puts $fp "  3. Constraint violations"
    puts $fp "  4. Power analysis"
    puts $fp "  5. Area analysis"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/$1"] {
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
    handle_info "Executing Power Compiler post_merge flow..."
    flow_exec validate_results
    flow_exec generate_report
    handle_info "Power Compiler post_merge completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec post_merge_flow } else { puts " POPT Power Compiler post_merge procedures loaded" }

# Exit tool after stage completion
exit
