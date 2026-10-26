#!/usr/bin/env tclsh
# CBFlow FP post_floorplan - Synopsys Fusion Compiler | FP post_floorplan

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "post_floorplan"
set NODE_NAME "post_floorplan1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {[info exists fp(common,max_congestion_threshold)]} {
        handle_info "Congestion threshold set to: $fp(common,max_congestion_threshold)%"
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
        report_timing -max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 50}] -slack_lesser_than 0.0 -delay_type max
    }

    # Report hold timing
    redirect -file $::REPORTS_DIR/timing_hold.rpt" {
        report_timing -max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 50}] -slack_lesser_than 0.0 -delay_type min
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
    save_block -as $fp(common,design_lib_name):$fp(common,design_name)/post_floorplan_done

    handle_info "Final reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
