#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FCFP Post-Floorplan Command File (Innovus)
# Description: Placement check, congestion analysis, pre-place timing, and
#              post-floorplan reporting
# Tool: Cadence Innovus
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/FCFP/fc_post_floorplan/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/fc_post_floorplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting FCFP fc_post_floorplan stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN PLACEMENT CHECK                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_placement_check {
    global fcfp project tech flow
    handle_info "Running placement legality checks..."

    file mkdir "$::REPORTS_DIR"

    # Check placement legality
    set place_rpt "$::REPORTS_DIR/placement_check.rpt"
    check_place -report $place_rpt
    handle_info "  Placement check: $place_rpt"

    # Check for overlaps
    set overlap_rpt "$::REPORTS_DIR/overlap_check.rpt"
    checkPlace -report $overlap_rpt
    handle_info "  Overlap check: $overlap_rpt"

    # Verify floorplan constraints
    set fp_check_rpt "$::REPORTS_DIR/floorplan_check.rpt"
    checkFPlan -report $fp_check_rpt
    handle_info "  Floorplan check: $fp_check_rpt"

    # Check pin accessibility
    set pin_rpt "$::REPORTS_DIR/pin_access_check.rpt"
    checkPinAssignment -report $pin_rpt
    handle_info "  Pin access check: $pin_rpt"

    puts " Placement checks completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN CONGESTION ANALYSIS                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_congestion {
    global fcfp project tech flow
    handle_info "Running congestion analysis with trial route..."

    # Run trial route for congestion estimation
    puts "Running trial route..."
    if {[info exists fcfp(post_floorplan,trial_route_effort)]} {
        set effort $fcfp(post_floorplan,trial_route_effort)
    } else {
        set effort "medium"
    }

    routeDesign -globalDetail -viaOpt
    # Alternative: route_trial for quick congestion check
    # route_trial -effort $effort

    # Generate congestion report
    set congestion_rpt "$::REPORTS_DIR/congestion.rpt"
    reportCongestion -report $congestion_rpt
    handle_info "  Congestion report: $congestion_rpt"

    # Generate congestion map
    set cong_map_rpt "$::REPORTS_DIR/congestion_map.rpt"
    reportCongestion -hotSpot -report $cong_map_rpt
    handle_info "  Congestion hotspot map: $cong_map_rpt"

    # Check congestion threshold from config
    if {[info exists fcfp(post_floorplan,congestion_threshold)]} {
        puts "   Congestion threshold: $fcfp(post_floorplan,congestion_threshold)%"
    }

    puts " Congestion analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN TIMING ANALYSIS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_timing {
    global fcfp project tech flow
    handle_info "Running pre-place timing analysis..."

    # Run pre-placement timing analysis
    set timing_rpt "$::REPORTS_DIR/timing_preplace.rpt"
    timeDesign -prePlace -outDir "$::REPORTS_DIR/timing"
    handle_info "  Pre-place timing: $::REPORTS_DIR/timing/"

    # Generate detailed timing report
    if {[info exists fcfp(post_floorplan,max_timing_paths)]} {
        set max_paths $fcfp(post_floorplan,max_timing_paths)
    } else {
        set max_paths 50
    }

    report_timing -max_paths $max_paths \
        -late > "$::REPORTS_DIR/timing_setup.rpt"
    handle_info "  Setup timing ($max_paths paths): $::REPORTS_DIR/timing_setup.rpt"

    report_timing -max_paths $max_paths \
        -early > "$::REPORTS_DIR/timing_hold.rpt"
    handle_info "  Hold timing ($max_paths paths): $::REPORTS_DIR/timing_hold.rpt"

    # Report clock tree estimation
    set clock_rpt "$::REPORTS_DIR/clock_tree_estimate.rpt"
    reportClockTree -report $clock_rpt
    handle_info "  Clock tree estimate: $clock_rpt"

    puts " Pre-place timing analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORTS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_reports {
    global fcfp project tech flow
    handle_info "Generating post-floorplan summary reports..."

    # Area and utilization report
    report_area > "$::REPORTS_DIR/area_report.rpt"

    # Design summary
    report_design > "$::REPORTS_DIR/design_summary.rpt"

    # Power grid report (post power plan)
    report_power_grid > "$::REPORTS_DIR/power_grid.rpt"

    # Summary file
    set summary_file "$::REPORTS_DIR/post_floorplan_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow FCFP Post-Floorplan Summary - Innovus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Innovus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Checks Performed:"
    puts $fp "  Placement:  reports/fcfp/post_floorplan/placement_check.rpt"
    puts $fp "  Floorplan:  reports/fcfp/post_floorplan/floorplan_check.rpt"
    puts $fp "  Congestion: reports/fcfp/post_floorplan/congestion.rpt"
    puts $fp "  Timing:     reports/fcfp/post_floorplan/timing_setup.rpt"
    puts $fp "  Hold:       reports/fcfp/post_floorplan/timing_hold.rpt"
    puts $fp "  Area:       reports/fcfp/post_floorplan/area_report.rpt"
    puts $fp "  Clock:      reports/fcfp/post_floorplan/clock_tree_estimate.rpt"
    close $fp

    handle_info "  Summary: $summary_file"
    puts " Post-floorplan reports generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow FCFP fc_post_floorplan with Innovus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc fc_post_floorplan_flow {
    handle_info "Executing FCFP fc_post_floorplan flow..."
    flow_exec run_placement_check
    flow_exec run_congestion
    flow_exec run_timing
    flow_exec generate_reports
    handle_info "FCFP fc_post_floorplan completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_post_floorplan_flow } else { puts " FCFP fc_post_floorplan procedures loaded" }

# Exit tool after stage completion
exit
