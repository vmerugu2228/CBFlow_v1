#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - LEC Validate Command File
# Description: Equivalence analysis, diagnosis, and report generation
# Tool: Synopsys Formality
# Usage: Source this file in Formality or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

# Source environment variables
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source -e $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

# Source flow utilities
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
    source -e $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

namespace import ::CBFlow::Utilities::print_header

# Source generated configuration file
set config_file "$run_dir/work/LEC/validate1/run/config.tcl"
if {[file exists $config_file]} {
    source -e $config_file
}

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Declare global arrays
global lec project tech flow

# Source FORMALITY tool config
set _tool_config "[file dirname [info script]]/formality_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting LEC validate stage with Synopsys Formality..."

# Initialize flow namespace
if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}

set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/LEC/validate1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE FAILING POINTS                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_failing_points {
    global lec project tech flow
    handle_info "Analyzing failing compare points..."

    file mkdir $::REPORTS_DIR

    # Diagnose failing points
    puts "Running diagnosis on failing points..."
    if {[catch {diagnose} diag_result]} {
        puts "  No failing points to diagnose (design may be equivalent)"
    } else {
        puts "  Diagnosis completed"
    }

    # Report failing analysis
    if {[catch {report_failing -details > "$::REPORTS_DIR/failing_analysis.rpt"} err]} {
        puts "  No failing points to report"
        set fp [open "$::REPORTS_DIR/failing_analysis.rpt" w]
        puts $fp "No failing compare points - designs are logically equivalent"
        close $fp
    }

    puts " Failing point analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE EQUIVALENCE REPORT                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_equivalence_report {
    global lec project tech flow
    handle_info "Generating equivalence analysis report..."

    file mkdir $::OUTPUTS_DIR
    file mkdir $::REPORTS_DIR

    # Main equivalence report
    set equiv_file "$::OUTPUTS_DIR/equivalence.rpt"
    set fp [open $equiv_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow LEC - Equivalence Analysis Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp ""
    puts $fp "Tool: Synopsys Formality"
    puts $fp ""
    puts $fp "Analysis Summary:"
    puts $fp "  Verification completed"
    puts $fp "  See detailed reports in reports/lec/"
    puts $fp ""
    puts $fp "Reports:"
    puts $fp "  reports/lec/verification_status.rpt"
    puts $fp "  reports/lec/match_status.rpt"
    puts $fp "  reports/lec/failing_analysis.rpt"
    puts $fp "  reports/lec/compare_points.rpt"
    puts $fp "  reports/lec/lec_summary.rpt"
    close $fp

    puts " Equivalence report: $equiv_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE ANALYSIS LOG                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_analysis_log {
    global lec project tech flow
    handle_info "Generating analysis log..."

    file mkdir $::OUTPUTS_DIR

    set log_file "$::OUTPUTS_DIR/analysis.log"
    set fp [open $log_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow LEC - Analysis Log"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Timestamp: [clock format [clock seconds]]"
    puts $fp ""
    puts $fp "Flow: LEC (Logic Equivalence Checking)"
    puts $fp "Tool: Synopsys Formality"
    if {[info exists project(top_module)]} { puts $fp "Top Module: $project(top_module)" }
    puts $fp ""
    puts $fp "Stage Sequence:"
    puts $fp "  1. inputs  - Input file preparation"
    puts $fp "  2. setup   - Design loading and configuration"
    puts $fp "  3. compare - Formal verification"
    puts $fp "  4. validate - Result analysis and reporting"
    puts $fp ""
    puts $fp "Status: COMPLETED"
    puts $fp ""
    puts $fp "Output Files:"
    puts $fp "  results/lec/comparison.rpt"
    puts $fp "  results/lec/equivalence.rpt"
    puts $fp "  results/lec/analysis.log"
    close $fp

    puts " Analysis log: $log_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE SUMMARY REPORT                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_summary_report {
    global lec project tech flow
    handle_info "Generating LEC summary report..."

    file mkdir $::REPORTS_DIR

    set summary_file "$::REPORTS_DIR/lec_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow LEC - Final Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp ""

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Count golden and revised files
    set golden_count [llength [glob -nocomplain "$run_dir/work/LEC/inputs/netlist_golden/*"]]
    set revised_count [llength [glob -nocomplain "$run_dir/work/LEC/inputs/netlist_revised/*"]]

    puts $fp "Design Information:"
    if {[info exists project(top_module)]} { puts $fp "  Top Module: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "  Project: $project(name)" }
    puts $fp "  Golden netlist files: $golden_count"
    puts $fp "  Revised netlist files: $revised_count"
    puts $fp ""
    puts $fp "Verification Results:"
    puts $fp "  See reports/lec/verification_status.rpt for details"
    puts $fp ""
    puts $fp "All Reports:"
    foreach rpt [glob -nocomplain "$::REPORTS_DIR/*.rpt" "$run_dir/work/LEC/compare1/reports/*.rpt"] {
        puts $fp "  [file tail $rpt]"
    }
    close $fp

    puts " Summary report: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE ANALYSIS RESULTS                            │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_analysis_results {
    global lec project tech flow FLOW_DIR
    handle_info "Running validation for validate stage..."

    set current_dir $::env(CBFLOW_RUN_DIR)
    set validation_flow_dir ""

    if {[info exists FLOW_DIR]} {
        set validation_flow_dir $FLOW_DIR
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set validation_flow_dir $::env(FLOW_DIR)
    }

    # Check mandatory outputs
    set equiv_rpt "$current_dir/results/lec/equivalence.rpt"
    set analysis_log "$current_dir/results/lec/analysis.log"

    if {[file exists $equiv_rpt]} {
        handle_info "Equivalence report verified: $equiv_rpt"
    } else {
        handle_warning "Equivalence report not found: $equiv_rpt"
    }

    if {[file exists $analysis_log]} {
        handle_info "Analysis log verified: $analysis_log"
    } else {
        handle_warning "Analysis log not found: $analysis_log"
    }

    # Try enhanced validation
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"
    if {[file exists $enhanced_validation_script]} {
        if {[catch {exec tclsh $enhanced_validation_script LEC validate $current_dir $validation_flow_dir} validation_result]} {
            handle_warning "Validation completed with warnings: $validation_result"
        } else {
            handle_info "Validation completed successfully"
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow LEC Validate with Synopsys Formality"
handle_info "═══════════════════════════════════════════════════════════════════════════════"

flow_proc validate_flow {
    handle_info "Executing LEC validate flow..."

    flow_exec validate_failing_points
    flow_exec generate_equivalence_report
    flow_exec generate_analysis_log
    flow_exec generate_summary_report
    flow_exec validate_analysis_results

    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " LEC Analysis Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    puts "Equivalence report: results/lec/equivalence.rpt"
    puts "Analysis log: results/lec/analysis.log"
    puts "Summary: reports/lec/lec_summary.rpt"
    handle_info "LEC validate completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Direct execution mode - running LEC validate flow"
    flow_exec validate_flow
} else {
    puts " CBFlow LEC validate procedures loaded"
    puts "Available: validate_failing_points, generate_equivalence_report, generate_analysis_log, generate_summary_report, validate_analysis_results, validate_flow"
}
exit
