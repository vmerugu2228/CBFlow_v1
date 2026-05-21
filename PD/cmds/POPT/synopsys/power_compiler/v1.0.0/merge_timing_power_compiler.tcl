#!/usr/bin/env tclsh
# CBFlow POPT merge_timing - Synopsys Power Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "POPT"
set STAGE_NAME "merge_timing"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
        report_timing -delay max -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] > "$::REPORTS_DIR/$1"

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
    set _max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}]
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
