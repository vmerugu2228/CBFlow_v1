#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PV Merge Data Command File
# Description: Merge all physical verification results
# Tool: Mentor Calibre
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global phyv project tech flow
# Source CALIBRE tool config
set _tool_config "[file dirname [info script]]/calibre_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV merge data stage..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/merge_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc merge_verification_results {
    global phyv project tech flow
    handle_info "Merging all verification results..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/phyv"

    set summary_file "$run_dir/results/phyv/phyv_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - Physical Verification Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp "\nTool: Mentor Calibre\n"

    # Check each verification stage
    foreach {stage dir label} {
        drc "results/drc/drc_results.rpt" "DRC (Design Rule Check)"
        lvs "results/lvs/lvs_results.rpt" "LVS (Layout vs Schematic)"
        erc "results/erc/erc_results.rpt" "ERC (Electrical Rule Check)"
        perc "results/perc/perc_results.rpt" "PERC (Parasitic Extraction Rule Check)"
    } {
        set full_path "$run_dir/$dir"
        if {[file exists $full_path]} {
            puts $fp "  $label: COMPLETED - $dir"
        } else {
            puts $fp "  $label: PENDING - $dir"
        }
    }

    puts $fp "\nDetailed Reports:"
    foreach rpt [glob -nocomplain "$run_dir/reports/phyv/*/*.rpt" "$run_dir/reports/phyv/*.rpt"] {
        set rel [string range $rpt [expr {[string length $run_dir] + 1}] end]
        puts $fp "  $rel"
    }
    close $fp

    puts " Merged summary: $summary_file"
}

flow_proc merge_data_flow {
    handle_info "Executing merge data flow..."
    flow_exec merge_verification_results
    handle_info "PV merge data completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_data_flow } else { puts " PV merge data procedures loaded" }

# Exit tool after stage completion
exit
