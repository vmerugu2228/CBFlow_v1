#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PV DRC Command File
# Description: Design Rule Check using Mentor Calibre
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/drc/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global phyv project tech flow
handle_info "Starting PV DRC stage with Mentor Calibre..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/drc"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc run_drc_checks {
    handle_info "Running DRC checks..."
    file mkdir "results/drc" ; file mkdir "reports/phyv/drc"
    puts "Running spacing checks..."; calibre -drc -spacing > "$::REPORTS_DIR/spacing.rpt"
    puts "Running width checks...";   calibre -drc -width > "$::REPORTS_DIR/width.rpt"
    puts "Running density checks..."; calibre -drc -density > "$::REPORTS_DIR/density.rpt"
    puts "Running via checks...";     calibre -drc -via > "$::REPORTS_DIR/via.rpt"
    puts " DRC checks completed"
}

flow_proc generate_drc_report {
    global phyv project tech
    handle_info "Generating DRC report..."
    set rpt "$::REPORTS_DIR/drc_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - DRC Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/drc/spacing.rpt, width.rpt, density.rpt, via.rpt"
    close $fp
    puts " DRC report: $rpt"
}

flow_proc drc_flow {
    handle_info "Executing DRC flow..."
    flow_exec run_drc_checks
    flow_exec generate_drc_report
    handle_info " DRC Complete! Results: results/drc/drc_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec drc_flow } else { puts " PV DRC procedures loaded" }

# Exit tool after stage completion
exit
