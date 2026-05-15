#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PV LVS Command File
# Description: Layout vs Schematic check using Mentor Calibre
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/lvs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

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
handle_info "Starting PV LVS stage with Mentor Calibre..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/lvs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc run_lvs_comparison {
    handle_info "Running LVS comparison..."
    file mkdir "results/lvs" ; file mkdir "reports/phyv/lvs"
    puts "Extracting layout netlist..."; calibre -lvs -extract > "$::REPORTS_DIR/extract.rpt"
    puts "Comparing layout vs schematic..."; calibre -lvs -compare > "$::REPORTS_DIR/comparison.rpt"
    puts " LVS comparison completed"
}

flow_proc generate_lvs_report {
    global phyv project tech
    handle_info "Generating LVS report..."
    set rpt "$::REPORTS_DIR/lvs_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - LVS Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/lvs/extract.rpt, comparison.rpt"
    close $fp
    puts " LVS report: $rpt"
}

flow_proc lvs_flow {
    handle_info "Executing LVS flow..."
    flow_exec run_lvs_comparison
    flow_exec generate_lvs_report
    handle_info " LVS Complete! Results: results/lvs/lvs_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec lvs_flow } else { puts " PV LVS procedures loaded" }

# Exit tool after stage completion
exit
