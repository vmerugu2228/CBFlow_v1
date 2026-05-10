#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - STA Timing Command File
# Description: Static timing analysis and sign-off verification
# Tool: Cadence Tempus
# Usage: Source this file in Tempus or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    puts stderr "ERROR: FLOW_DIR not found in environment"
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts stderr "ERROR: UTILITIES_VERSION not set."
    exit 1
}

set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/STA/timing/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow

handle_info "Starting STA timing stage with Cadence Tempus..."

if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/timing"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       LOAD PARASITICS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc load_parasitics {
    global sta project tech flow
    handle_info "Loading parasitic data..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Load SPEF from extraction stage or inputs
    set extraction_spef "$run_dir/results/extraction/parasitic.spef"
    set input_spef_files [glob -nocomplain "$run_dir/work/STA/inputs/spef/*.spef"]

    if {[file exists $extraction_spef]} {
        puts "Loading extraction SPEF: $extraction_spef"
        read_spef $extraction_spef
        puts " Extraction parasitics loaded"
    } elseif {[llength $input_spef_files] > 0} {
        foreach spef $input_spef_files {
            puts "Loading input SPEF: [file tail $spef]"
            read_spef $spef
        }
        puts " Input parasitics loaded"
    } else {
        handle_warning "No SPEF files available - timing may be inaccurate"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       CONFIGURE TIMING ANALYSIS                            │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc configure_timing_analysis {
    global sta project tech flow
    handle_info "Configuring timing analysis..."

    # Configure analysis modes
    if {[info exists sta(timing,mode)]} {
        puts "Timing mode: $sta(timing,mode)"
    } else {
        puts "Timing mode: default (signoff)"
    }

    # Configure MMMC if enabled
    if {[info exists flow(mmmc,enabled)] && $flow(mmmc,enabled) eq "true"} {
        puts "MMMC analysis: enabled"
    }

    # OCV/AOCV/POCV settings
    if {[info exists sta(timing,ocv_mode)]} {
        puts "OCV mode: $sta(timing,ocv_mode)"
    }

    # SI analysis
    if {[info exists sta(timing,si_aware)] && $sta(timing,si_aware) eq "true"} {
        puts "Signal integrity analysis: enabled"
        set_si_mode -enable_delay_report true
    }

    puts " Timing analysis configured"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       RUN TIMING ANALYSIS                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_timing_analysis {
    global sta project tech flow
    handle_info "Running static timing analysis..."

    file mkdir "$::OUTPUTS_DIR/timing"
    file mkdir "$::REPORTS_DIR"

    # Update timing
    puts "Updating timing graph..."
    update_timing

    # Setup timing analysis
    puts "Running setup timing check..."
    report_timing -late -max_paths 100 -path_type full > "$::REPORTS_DIR/setup_timing.rpt"
    report_timing -late -max_paths 10 -path_type summary > "$::REPORTS_DIR/setup_timing_summary.rpt"

    # Hold timing analysis
    puts "Running hold timing check..."
    report_timing -early -max_paths 100 -path_type full > "$::REPORTS_DIR/hold_timing.rpt"
    report_timing -early -max_paths 10 -path_type summary > "$::REPORTS_DIR/hold_timing_summary.rpt"

    puts " Timing analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       CHECK TIMING VIOLATIONS                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc check_timing_violations {
    global sta project tech flow
    handle_info "Checking timing violations..."

    file mkdir "results/timing"

    # Check constraint violations
    puts "Checking constraint violations..."
    report_constraint -all_violators > "$::REPORTS_DIR/constraint_violations.rpt"

    # Check clock domain crossings
    puts "Checking clock domain crossings..."
    if {[catch {report_clock_timing -type summary > "$::REPORTS_DIR/clock_summary.rpt"}]} {
        puts "  Clock summary report skipped"
    }

    # Generate violations summary
    set violations_file "$::OUTPUTS_DIR/timing/violations.rpt"
    set fp [open $violations_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow STA - Timing Violations Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Violation Reports:"
    puts $fp "  Setup violations: reports/timing/setup_timing.rpt"
    puts $fp "  Hold violations:  reports/timing/hold_timing.rpt"
    puts $fp "  Constraints:      reports/timing/constraint_violations.rpt"
    close $fp

    puts " Violations check completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE TIMING REPORTS                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_timing_reports {
    global sta project tech flow
    handle_info "Generating timing reports..."

    file mkdir "reports/timing"
    file mkdir "results/timing"

    # QoR report
    puts "Generating QoR report..."
    report_qor > "$::REPORTS_DIR/timing_qor.rpt"

    # Power analysis
    puts "Generating power report..."
    if {[catch {report_power > "$::REPORTS_DIR/timing_power.rpt"}]} {
        puts "  Power report skipped"
    }

    # Main timing report
    set timing_file "$::OUTPUTS_DIR/timing/timing.rpt"
    set fp [open $timing_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow STA - Final Timing Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp ""
    puts $fp "Tool: Cadence Tempus"
    puts $fp ""
    puts $fp "Analysis Reports:"
    puts $fp "  Setup Timing:     reports/timing/setup_timing.rpt"
    puts $fp "  Hold Timing:      reports/timing/hold_timing.rpt"
    puts $fp "  Violations:       results/timing/violations.rpt"
    puts $fp "  QoR:              reports/timing/timing_qor.rpt"
    puts $fp "  Clock Summary:    reports/timing/clock_summary.rpt"
    puts $fp "  Constraints:      reports/timing/constraint_violations.rpt"
    puts $fp ""
    puts $fp "Extraction:"
    puts $fp "  SPEF:             results/extraction/parasitic.spef"
    close $fp

    puts " Timing reports generated"
    puts " Check reports in: reports/timing/"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE TIMING RESULTS                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_timing_results {
    global sta project tech flow FLOW_DIR
    handle_info "Validating timing results..."

    set current_dir $::env(CBFLOW_RUN_DIR)

    # Check mandatory outputs
    foreach {desc path} {
        "Timing report" "results/timing/timing.rpt"
        "Violations report" "results/timing/violations.rpt"
    } {
        set full_path "$current_dir/$path"
        if {[file exists $full_path]} {
            handle_info "$desc verified: $path"
        } else {
            handle_warning "$desc not found: $path"
        }
    }

    set validation_flow_dir [expr {[info exists FLOW_DIR] ? $FLOW_DIR : $::env(FLOW_DIR)}]
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"
    if {[file exists $enhanced_validation_script]} {
        if {[catch {exec tclsh $enhanced_validation_script STA timing $current_dir $validation_flow_dir} result]} {
            handle_warning "Validation completed with warnings: $result"
        } else {
            handle_info "Validation completed successfully"
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow STA Timing Analysis with Cadence Tempus"
handle_info "═══════════════════════════════════════════════════════════════════════════════"

flow_proc timing_flow {
    handle_info "Executing STA timing flow..."

    flow_exec load_parasitics
    flow_exec configure_timing_analysis
    flow_exec run_timing_analysis
    flow_exec check_timing_violations
    flow_exec generate_timing_reports
    flow_exec validate_timing_results

    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " STA Timing Analysis Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    puts "Timing report: results/timing/timing.rpt"
    puts "Violations: results/timing/violations.rpt"
    puts "Check reports in: reports/timing/"
    handle_info "STA timing completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    flow_exec timing_flow
} else {
    puts " CBFlow STA timing procedures loaded"
    puts "Available: load_parasitics, configure_timing_analysis, run_timing_analysis, check_timing_violations, generate_timing_reports, validate_timing_results, timing_flow"
}

# Exit tool after stage completion
exit
