#!/usr/bin/env tclsh
# CBFlow POPT power_opt - Synopsys PrimeTime | Power optimization analysis and insertion
set run_dir $::env(CBFLOW_RUN_DIR)
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/POPT/power_opt/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global popt project tech flow
# Source PT tool config
set _tool_config "[file dirname [info script]]/pt_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting POPT power_opt with Synopsys PrimeTime..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/POPT/power_opt"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: analyze_power
# Run hierarchical power analysis before optimization
# ---------------------------------------------------------------------------
flow_proc analyze_power {
    handle_info "Running pre-optimization power analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::OUTPUTS_DIR/popt"

    # Set switching activity defaults
    if {[info exists ::popt(SWITCHING_ACTIVITY)]} {
        set_switching_activity -static_probability $::popt(SWITCHING_ACTIVITY)
    } else {
        set_switching_activity -static_probability 0.5 -toggle_rate 0.1
    }

    # Read switching activity file if provided
    if {[info exists ::popt(SAIF_FILE)]} {
        read_saif $::popt(SAIF_FILE)
        handle_info "Loaded SAIF: $::popt(SAIF_FILE)"
    }

    # Hierarchical power report
    report_power -hierarchy -levels 3 > "$::REPORTS_DIR/pre_opt_power_hier.rpt"

    # Detailed power breakdown
    report_power -cell > "$::REPORTS_DIR/pre_opt_power_cell.rpt"
    report_power -net  > "$::REPORTS_DIR/pre_opt_power_net.rpt"

    # Leakage power report
    report_power -leakage > "$::REPORTS_DIR/pre_opt_leakage.rpt"

    # Summary report
    report_power > "$::REPORTS_DIR/pre_opt_power_summary.rpt"

    handle_info "Pre-optimization power analysis completed"
}

# ---------------------------------------------------------------------------
# flow_proc: optimize_clock_gating
# Insert and optimize clock gating for dynamic power reduction
# ---------------------------------------------------------------------------
flow_proc optimize_clock_gating {
    handle_info "Running clock gating optimization..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Configure clock gating options
    if {[info exists ::popt(CG_MIN_BITWIDTH)]} {
        set_clock_gating_style -minimum_bitwidth $::popt(CG_MIN_BITWIDTH)
    } else {
        set_clock_gating_style -minimum_bitwidth 4
    }

    if {[info exists ::popt(CG_MAX_FANOUT)]} {
        set_clock_gating_style -max_fanout $::popt(CG_MAX_FANOUT)
    }

    # Insert clock gating globally
    handle_info "Inserting clock gating cells..."
    insert_clock_gating -global

    # Verify clock gating insertion
    report_clock_gating > "$rpt_dir/clock_gating_insertion.rpt"
    report_clock_gating -summary > "$rpt_dir/clock_gating_summary.rpt"

    # Report post-CG power
    report_power > "$rpt_dir/post_cg_power.rpt"

    handle_info "Clock gating optimization completed"
}

# ---------------------------------------------------------------------------
# flow_proc: optimize_leakage
# Optimize leakage power through multi-Vt swap and power gating
# ---------------------------------------------------------------------------
flow_proc optimize_leakage {
    handle_info "Running leakage power optimization..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Set leakage power budget
    if {[info exists ::popt(MAX_LEAKAGE_POWER)]} {
        set_max_leakage_power $::popt(MAX_LEAKAGE_POWER)
        handle_info "Leakage budget: $::popt(MAX_LEAKAGE_POWER)"
    } else {
        set_max_leakage_power 0
        handle_info "Leakage budget: minimize (target 0)"
    }

    # Set timing margin for Vt swap
    if {[info exists ::popt(LEAKAGE_TIMING_MARGIN)]} {
        set_app_var power_cg_auto_identify_timing_margin $::popt(LEAKAGE_TIMING_MARGIN)
    }

    # Run multi-Vt optimization
    handle_info "Running multi-Vt cell swapping..."
    set_multi_vth_constraint -lvth_percentage 0.0
    optimize_power -leakage

    # Report post-leakage-opt power
    report_power -leakage > "$rpt_dir/post_leakage_opt_leakage.rpt"

    # Report Vt distribution
    report_threshold_voltage_group > "$rpt_dir/vt_distribution.rpt"

    # Verify timing after leakage opt
    report_timing -delay max -max_paths [expr {[info exists pt(analysis,max_paths)] ? $pt(analysis,max_paths) : 100}] > "$rpt_dir/post_leakage_opt_timing.rpt"

    handle_info "Leakage optimization completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_power_report
# Generate final power optimization reports and summary
# ---------------------------------------------------------------------------
flow_proc generate_power_report {
    handle_info "Generating final power optimization reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # Final power analysis after all optimizations
    report_power -hierarchy -levels 3 > "$rpt_dir/post_opt_power_hier.rpt"
    report_power > "$rpt_dir/post_opt_power_summary.rpt"

    # Final timing check
    set _max_paths [expr {[info exists pt(analysis,max_paths)] ? $pt(analysis,max_paths) : 100}]
    report_timing -delay max -max_paths $_max_paths > "$rpt_dir/post_opt_setup_timing.rpt"
    report_timing -delay min -max_paths $_max_paths > "$rpt_dir/post_opt_hold_timing.rpt"

    # Create summary results file
    set fp [open "$res_dir/power_opt.rpt" w]
    puts $fp "================================================================"
    puts $fp "POPT Power Optimization Summary - PrimeTime"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Optimization stages:"
    puts $fp "  1. Pre-optimization power analysis"
    puts $fp "  2. Clock gating insertion"
    puts $fp "  3. Leakage optimization (multi-Vt)"
    puts $fp ""
    puts $fp "Reports generated:"
    foreach f [glob -nocomplain "$rpt_dir/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Power optimization reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all power_opt flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc power_opt_flow {
    handle_info "Executing POPT power_opt flow..."
    flow_exec analyze_power
    flow_exec optimize_clock_gating
    flow_exec optimize_leakage
    flow_exec generate_power_report
    handle_info "POPT power_opt completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec power_opt_flow } else { puts " POPT power_opt procedures loaded" }

# Exit tool after stage completion
exit
