#!/usr/bin/env tclsh
# PNR place - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "place"
set NODE_NAME "place1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ==============================================================================
# flow_proc: load_design
# Description: Restore design from init_design stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db "$run_dir/work/$::FLOW_TYPE/init_design1/outputs/init_design.enc.dat"
    if {![file exists $_db]} {
        handle_error "init_design database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}


# ═══════════════════════════════════════════════════════════════════════════════
# PLACEMENT
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc enable_mmmc {
    # Enable MMMC scenarios for placement stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for placement stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "placement" "setup"]
    set hold_scenarios [get_effective_scenarios "placement" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for placement, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "placement"]
    
    handle_info "placement MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Create analysis views for each scenario
    create_mmmc_scenarios_for_node "placement"

    foreach scenario $all_scenarios {
        if {[info exists analysis_views($scenario)]} {
            array set view_info $analysis_views($scenario)
            handle_info "Creating analysis view: $scenario"
            create_analysis_view -name $scenario \
                -constraint_file $view_info(constraint_file) \
                -library_set $view_info(lib_set) \
                -rc_corner $view_info(rc_corner)
            array unset view_info
        }
    }

    # Set active analysis views
    set_analysis_view -setup $setup_scenarios -hold $hold_scenarios

    handle_info "MMMC scenarios configured for placement stage"
}

flow_proc setup_placement {
    handle_info "Setting up placement parameters..."

    apply_vt_dont_use
    # Get placement parameters from config
    global pnr
    set place_effort  $pnr(place,effort)
    set place_density $pnr(place,density)
    set place_congestion_effort [expr {[info exists pnr(place,congestion_effort)] ? $pnr(place,congestion_effort) : "auto"}]
    set place_timing_driven     [expr {[info exists pnr(place,timing_driven)]     ? $pnr(place,timing_driven)     : "true"}]

    handle_info "Placement parameters:"
    handle_info "  Effort: $place_effort"
    handle_info "  Density: $place_density"
    handle_info "  Congestion effort: $place_congestion_effort"
    handle_info "  Timing driven: $place_timing_driven"

    # Configure Innovus placement mode
    setPlaceMode -place_detail_legalization_inst_gap 1
    setPlaceMode -place_global_place_io_pins true
    if {$place_timing_driven eq "true"} {
        setPlaceMode -place_global_timing_effort $place_effort
    }
    setPlaceMode -place_global_cong_effort $place_congestion_effort
    setPlaceMode -place_detail_activity_rising $place_density
}

flow_proc run_global_placement {
    handle_info "Running global placement..."

    # Global placement with timing-driven optimization
    placeDesign -prePlaceOpt

    handle_info "Global placement completed"
}

flow_proc optimize_placement {
    handle_info "Optimizing placement..."

    # Pre-CTS optimization
    global pnr
    set optimization_effort $pnr(place,opt_effort)

    handle_info "Optimization effort: $optimization_effort"

    # Pre-CTS timing optimization
    optDesign -preCTS -effort $optimization_effort

    handle_info "Placement optimization completed"
}

flow_proc run_detailed_placement {
    handle_info "Running detailed placement..."

    # Detailed placement legalization and refinement
    refinePlace

    handle_info "Detailed placement completed"
}

flow_proc analyze_placement {
    handle_info "Analyzing placement quality..."

    # Generate placement reports
    file mkdir "$::REPORTS_DIR"

    # Timing, area, congestion, and density reports
    catch { timeDesign -preCTS -outDir "$::REPORTS_DIR" -prefix preCTS }
    catch { report_timing -max_paths 50 > "$::REPORTS_DIR/report_timing.preCTS.rpt" }
    catch { report_area > "$::REPORTS_DIR/report_area.rpt" }
    catch { reportCongestion -overflow > "$::REPORTS_DIR/report_congestion.rpt" }
    catch { reportDensityMap > "$::REPORTS_DIR/report_cell_density.rpt" }
    catch { checkPlace -outfile "$::REPORTS_DIR/check_place.rpt" }

    handle_info "Placement analysis completed"
}

flow_proc validate_pnr_placement_results {
    global pnr project tech flow FLOW_DIR RUN_DIR ROOT_DIR

    handle_info "Running enhanced validation for PNR placement stage..."

    # Determine current working directory and flow directory
    set current_dir $::env(CBFLOW_RUN_DIR)
    set validation_flow_dir ""

    if {[info exists FLOW_DIR]} {
        set validation_flow_dir $FLOW_DIR
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set validation_flow_dir $::env(FLOW_DIR)
    } else {
        # Try to determine flow directory from current location
        set script_dir [file dirname [file normalize [info script]]]
        set validation_flow_dir [file dirname [file dirname [file dirname [file dirname $script_dir]]]]
    }

    # Enhanced validation script path
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"

    if {![file exists $enhanced_validation_script]} {
        handle_warning "Enhanced validation script not found: $enhanced_validation_script"
        handle_info "Falling back to basic validation if available..."

        # Try basic validation
        set basic_validation_script "$validation_flow_dir/utils/validation/v1.0.0/validate_run.tcl"
        if {[file exists $basic_validation_script]} {
            handle_info "Running basic validation for PNR placement..."
            if {[catch {exec tclsh $basic_validation_script PNR placement $current_dir $validation_flow_dir} validation_result]} {
                handle_error "Basic validation failed: $validation_result"
                return 0
            } else {
                handle_info "Basic validation completed successfully"
                return 1
            }
        } else {
            handle_warning "No validation script available, skipping validation"
            return 1
        }
    }

    # Run enhanced validation
    handle_info "Executing enhanced validation with critical error detection..."
    handle_info "Command: tclsh $enhanced_validation_script PNR placement $current_dir $validation_flow_dir"

    if {[catch {exec tclsh $enhanced_validation_script PNR placement $current_dir $validation_flow_dir} validation_result]} {
        handle_error "Enhanced validation failed with critical errors detected"
        handle_info "Validation output: $validation_result"

        # Check if this is a critical error failure (exit code 1) vs other errors
        if {[string match "*critical*error*" [string tolower $validation_result]] ||
            [string match "*xterm*" [string tolower $validation_result]]} {
            handle_error "Critical errors detected in PNR placement logs - check xterm display"
        }
        return 0
    } else {
        handle_info "Enhanced validation completed successfully"
        handle_info "Validation output: $validation_result"
        return 1
    }
}

flow_proc placement_complete {
    handle_info "Placement stage complete"

    # Enhanced validation with critical error detection
    handle_info "Running enhanced validation for placement stage..."
    validate_pnr_placement_results

    # Save checkpoint
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/placement.enc"

    # Final placement verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.rpt" }

    log_stage_status "placement" "COMPLETE" "Placement completed successfully"
}


# Exit tool after stage completion

flow_exec_all
exit
