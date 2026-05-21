#!/usr/bin/env tclsh
# CBFlow POPT merge_timing - Synopsys PrimeTime

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
flow_proc load_scenarios {
    handle_info "Loading multi-scenario timing data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/popt"
    file mkdir "$::REPORTS_DIR"

    # Determine scenarios from config or auto-discovery
    if {[info exists ::popt(SCENARIOS)]} {
        set scenarios $::popt(SCENARIOS)
    } else {
        set scenarios [list "func_ss_0p72v_125c" "func_ff_0p88v_m40c" "func_tt_0p80v_25c"]
        handle_info "Using default scenario list"
    }

    set loaded 0
    foreach scenario $scenarios {
        handle_info "Loading scenario: $scenario"

        # Source per-scenario timing setup if available
        set scenario_file "$run_dir/work/POPT/inputs/scenarios/${scenario}.tcl"
        if {[file exists $scenario_file]} {
            source $scenario_file
            incr loaded
        } else {
            handle_warning "Scenario file not found: $scenario_file"
        }

        # Read scenario-specific SPEF if available
        set scenario_spef "$run_dir/work/POPT/inputs/spef/${scenario}.spef"
        if {[file exists $scenario_spef]} {
            read_parasitics -format spef $scenario_spef
            handle_info "Loaded SPEF for scenario: $scenario"
        }

        # Read scenario-specific SDC if available
        set scenario_sdc "$run_dir/work/POPT/inputs/sdc/${scenario}.sdc"
        if {[file exists $scenario_sdc]} {
            read_sdc $scenario_sdc
            handle_info "Loaded SDC for scenario: $scenario"
        }
    }

    handle_info "Loaded $loaded scenario(s) out of [llength $scenarios]"
}

# ---------------------------------------------------------------------------
# flow_proc: merge_timing_data
# Merge timing across all loaded corners with full update
# ---------------------------------------------------------------------------
flow_proc merge_timing_data {
    handle_info "Merging timing data across scenarios..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Determine scenarios
    if {[info exists ::popt(SCENARIOS)]} {
        set scenarios $::popt(SCENARIOS)
    } else {
        set scenarios [list "func_ss_0p72v_125c" "func_ff_0p88v_m40c" "func_tt_0p80v_25c"]
    }

    # Perform full timing update for each corner
    foreach scenario $scenarios {
        handle_info "Updating timing for corner: $scenario"
        update_timing -full
        report_timing -delay max -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] > "$rpt_dir/setup_${scenario}.rpt"
        report_timing -delay min -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] > "$rpt_dir/hold_${scenario}.rpt"
    }

    # Run cross-scenario timing merge
    handle_info "Running cross-scenario timing merge..."
    update_timing -full

    # Generate per-corner slack summary
    set fp [open "$rpt_dir/corner_slack_summary.rpt" w]
    puts $fp "Corner Slack Summary - [clock format [clock seconds]]"
    puts $fp "======================================================="
    foreach scenario $scenarios {
        puts $fp [format "  %-30s : merged" $scenario]
    }
    close $fp

    handle_info "Timing merge completed across [llength $scenarios] scenarios"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_merged_report
# Generate consolidated timing reports across all scenarios
# ---------------------------------------------------------------------------
flow_proc generate_merged_report {
    handle_info "Generating merged timing reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # Setup timing report across all scenarios
    report_timing -delay max -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] -nworst 3 \
        > "$rpt_dir/merged_setup_timing.rpt"
    handle_info "Generated merged setup timing report"

    # Hold timing report across all scenarios
    report_timing -delay min -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] -nworst 3 \
        > "$rpt_dir/merged_hold_timing.rpt"
    handle_info "Generated merged hold timing report"

    # QoR summary
    report_qor > "$rpt_dir/merged_qor.rpt"

    # Constraint violations
    report_constraint -all_violators > "$rpt_dir/merged_violations.rpt"

    # Clock summary
    report_clock -skew > "$rpt_dir/merged_clock_skew.rpt"

    # Create consolidated summary
    set fp [open "$res_dir/merge_timing_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "POPT Merge Timing Summary - PrimeTime"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Reports generated:"
    foreach f [glob -nocomplain "$rpt_dir/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Merged timing reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all merge_timing flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc merge_timing_flow {
    handle_info "Executing POPT merge_timing flow..."
    flow_exec load_scenarios
    flow_exec merge_timing_data
    flow_exec generate_merged_report
    handle_info "POPT merge_timing completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_timing_flow } else { puts " POPT merge_timing procedures loaded" }

# Exit tool after stage completion
exit
