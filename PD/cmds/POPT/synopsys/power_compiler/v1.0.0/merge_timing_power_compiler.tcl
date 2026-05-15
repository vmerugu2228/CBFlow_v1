#!/usr/bin/env tclsh
# CBFlow POPT merge_timing - Synopsys Power Compiler | Merge timing for power analysis
set run_dir $::env(CBFLOW_RUN_DIR)
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/POPT/merge_timing/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global popt project tech flow
# Source POWER_COMPILER tool config
set _tool_config "[file dirname [info script]]/power_compiler_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting POPT merge_timing with Synopsys Power Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/POPT/merge_timing"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: load_timing
# Load timing data from PT or other STA runs for power correlation
# ---------------------------------------------------------------------------
flow_proc load_timing {
    handle_info "Loading timing data for Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/popt"
    file mkdir "$::REPORTS_DIR"

    # Read parasitic data for accurate power
    set spef_dir "$run_dir/work/POPT/inputs/spef"
    if {[info exists ::popt(SPEF_FILES)]} {
        set spef_files $::popt(SPEF_FILES)
    } else {
        set spef_files [glob -nocomplain "$spef_dir/*.spef" "$spef_dir/*.spef.gz"]
    }

    foreach spef $spef_files {
        handle_info "Reading SPEF: $spef"
        read_parasitics -format spef $spef
    }

    # Source timing database from PT if available
    if {[info exists ::popt(PT_TIMING_DB)]} {
        handle_info "Reading PT timing database: $::popt(PT_TIMING_DB)"
        read_db $::popt(PT_TIMING_DB)
    }

    # Update timing
    update_timing -full
    handle_info "Timing data loaded for power analysis"
}

# ---------------------------------------------------------------------------
# flow_proc: merge_scenarios
# Merge multi-scenario timing for power-aware analysis
# ---------------------------------------------------------------------------
flow_proc merge_scenarios {
    handle_info "Merging scenario timing for Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Determine scenarios
    if {[info exists ::popt(SCENARIOS)]} {
        set scenarios $::popt(SCENARIOS)
    } else {
        set scenarios [list "func_ss_0p72v_125c" "func_ff_0p88v_m40c" "func_tt_0p80v_25c"]
    }

    foreach scenario $scenarios {
        handle_info "Processing scenario: $scenario"

        # Source scenario-specific setup
        set scenario_file "$run_dir/work/POPT/inputs/scenarios/${scenario}.tcl"
        if {[file exists $scenario_file]} {
            source $scenario_file
        }

        # Update timing for this corner
        update_timing -full

        # Report per-scenario timing
        report_timing -delay max -max_paths [expr {[info exists power_compiler(analysis,max_paths)] ? $power_compiler(analysis,max_paths) : 100}] > "$::REPORTS_DIR/$1"

        # Report per-scenario power
        report_power > "$::REPORTS_DIR/$1"
    }

    handle_info "Scenario merge completed for [llength $scenarios] corners"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_report
# Generate merged timing summary for power optimization
# ---------------------------------------------------------------------------
flow_proc generate_report {
    handle_info "Generating merge timing report for Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # Merged timing summary
    set _max_paths [expr {[info exists power_compiler(analysis,max_paths)] ? $power_compiler(analysis,max_paths) : 100}]
    report_timing -delay max -max_paths $_max_paths > "$::REPORTS_DIR/$1"
    report_timing -delay min -max_paths $_max_paths > "$::REPORTS_DIR/$1"

    # Merged power summary
    report_power -hierarchy > "$::REPORTS_DIR/$1"

    # QoR
    report_qor > "$::REPORTS_DIR/$1"

    # Summary file
    set fp [open "$res_dir/pc_merge_timing_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "Power Compiler Merge Timing Summary"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/$1"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Merge timing reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all merge_timing flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc merge_timing_flow {
    handle_info "Executing Power Compiler merge_timing flow..."
    flow_exec load_timing
    flow_exec merge_scenarios
    flow_exec generate_report
    handle_info "Power Compiler merge_timing completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_timing_flow } else { puts " POPT Power Compiler merge_timing procedures loaded" }

# Exit tool after stage completion
exit
