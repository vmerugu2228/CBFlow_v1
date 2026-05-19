#!/usr/bin/env tclsh
# CBFlow FP post_floorplan - Synopsys Fusion Compiler | FP post_floorplan
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP post_floorplan with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FP/post_floorplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: run_placement_check
# Description: Run a coarse placement to evaluate floorplan quality
# ==============================================================================
flow_proc run_placement_check {
    handle_info "Running placement check on floorplan..."
    global fp

    file mkdir "$::REPORTS_DIR"

    # Run a coarse global placement to evaluate floorplan viability
    handle_info "Running coarse placement for evaluation..."
    create_placement -effort low -congestion

    # Check legality after coarse placement
    handle_info "Checking placement legality..."
    redirect -file $::REPORTS_DIR/coarse_legality.rpt" {
        check_legality
    }

    # Report utilization after coarse placement
    redirect -file $::REPORTS_DIR/coarse_utilization.rpt" {
        report_utilization
    }

    # Check for unplaced cells
    set unplaced [get_cells -hierarchical -filter "is_placed == false"]
    if {[sizeof_collection $unplaced] > 0} {
        handle_warning "Found [sizeof_collection $unplaced] unplaced cells after coarse placement"
    } else {
        handle_info "All cells placed successfully in coarse placement"
    }

    handle_info "Placement check completed"
}

# ==============================================================================
# flow_proc: run_congestion_analysis
# Description: Analyze routing congestion based on the coarse placement
# ==============================================================================
flow_proc run_congestion_analysis {
    handle_info "Running congestion analysis..."
    global fp

    # Run global routing for congestion estimation
    handle_info "Executing route_global for congestion analysis..."
    route_global

    # Generate congestion reports
    redirect -file $::REPORTS_DIR/congestion_global.rpt" {
        report_congestion -routing_stage global
    }

    # Report congestion hotspots
    redirect -file $::REPORTS_DIR/congestion_hotspots.rpt" {
        report_congestion -routing_stage global -max_percentage 90
    }

    # Report routing overflow
    redirect -file $::REPORTS_DIR/routing_overflow.rpt" {
        report_routing_violations -type overflow
    }

    # Report per-layer congestion
    redirect -file $::REPORTS_DIR/congestion_per_layer.rpt" {
        report_congestion -routing_stage global -layers all
    }

    # Check for severe congestion
    handle_info "Checking congestion levels..."
    if {[info exists fc(common,max_congestion_threshold)]} {
        handle_info "Congestion threshold set to: $fc(common,max_congestion_threshold)%"
    }

    handle_info "Congestion analysis completed"
}

# ==============================================================================
# flow_proc: run_timing_estimation
# Description: Run timing estimation to evaluate floorplan timing quality
# ==============================================================================
flow_proc run_timing_estimation {
    handle_info "Running timing estimation..."
    global fp

    # Update timing with estimated parasitics
    handle_info "Updating timing with RC estimates..."
    update_timing

    # Report setup timing
    redirect -file $::REPORTS_DIR/timing_setup.rpt" {
        report_timing -max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 50}] -slack_lesser_than 0.0 -delay_type max
    }

    # Report hold timing
    redirect -file $::REPORTS_DIR/timing_hold.rpt" {
        report_timing -max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 50}] -slack_lesser_than 0.0 -delay_type min
    }

    # Report clock tree estimation
    redirect -file $::REPORTS_DIR/clock_estimation.rpt" {
        report_clock_timing -type summary
    }

    # Report QoR
    redirect -file $::REPORTS_DIR/timing_qor.rpt" {
        report_qor
    }

    # Extract WNS for decision making
    set wns [get_attribute [get_timing_paths -max_paths 1] slack]
    handle_info "Estimated WNS after floorplan: ${wns}ns"

    if {$wns < 0} {
        handle_warning "Negative WNS detected -- floorplan may need refinement"
    } else {
        handle_info "Timing looks healthy for this stage"
    }

    handle_info "Timing estimation completed"
}

# ==============================================================================
# flow_proc: generate_final_reports
# Description: Generate final post-floorplan summary reports
# ==============================================================================
flow_proc generate_final_reports {
    handle_info "Generating final post-floorplan reports..."
    global fp

    # Overall design summary
    redirect -file $::REPORTS_DIR/design_summary.rpt" {
        report_design -summary
    }

    # Power estimation
    redirect -file $::REPORTS_DIR/power_estimate.rpt" {
        report_power -analysis_effort low
    }

    # Cell count summary
    redirect -file $::REPORTS_DIR/cell_summary.rpt" {
        report_cell_count
    }

    # Report PG connectivity status
    redirect -file $::REPORTS_DIR/pg_status.rpt" {
        check_pg_connectivity
    }

    # Report area summary
    redirect -file $::REPORTS_DIR/area_summary.rpt" {
        report_utilization
    }

    # Save post-floorplan state
    handle_info "Saving post-floorplan state..."
    save_block -as $fc(common,design_lib_name):$fc(common,design_name)/post_floorplan_done

    handle_info "Final reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
