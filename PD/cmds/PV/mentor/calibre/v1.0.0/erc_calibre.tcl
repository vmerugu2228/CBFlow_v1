#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PV ERC Command File
# Description: Electrical Rule Check using Mentor Calibre
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/erc/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global phyv project tech flow
handle_info "Starting PV ERC stage with Mentor Calibre..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/erc"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc run_erc_checks {
    handle_info "Running ERC checks..."
    file mkdir "results/erc" ; file mkdir "reports/phyv/erc"
    puts "Running power connectivity checks..."; calibre -erc -power > "$::REPORTS_DIR/power.rpt"
    puts "Running ground connectivity checks..."; calibre -erc -ground > "$::REPORTS_DIR/ground.rpt"
    puts "Running floating net checks..."; calibre -erc -floating > "$::REPORTS_DIR/floating.rpt"
    puts " ERC checks completed"
}

flow_proc generate_erc_report {
    global phyv project tech
    handle_info "Generating ERC report..."
    set rpt "$::REPORTS_DIR/erc_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - ERC Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/erc/power.rpt, ground.rpt, floating.rpt"
    close $fp
    puts " ERC report: $rpt"
}

flow_proc erc_flow {
    handle_info "Executing ERC flow..."
    flow_exec run_erc_checks
    flow_exec generate_erc_report
    handle_info " ERC Complete! Results: results/erc/erc_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec erc_flow } else { puts " PV ERC procedures loaded" }

# Exit tool after stage completion
exit
