#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PNR Placement Stage with MMMC Support
# Description: Standard cell placement with multi-mode multi-corner analysis
# Usage: Source this file in PNR tool
# ═══════════════════════════════════════════════════════════════════════════════

# Validate required version environment variables
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

# Source flow utilities using release version
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find flow utilities at: $utils_path"
    exit 1
}

# Source generated configuration file (from setup stage)
if {[file exists "work/PNR/placement/run/config.tcl"]} {
    source "work/PNR/placement/run/config.tcl"
} else {
    handle_error "Cannot find generated config file. Run 'make placement_setup' first."
}

# Source generated setup file (from setup stage)
if {[file exists "work/PNR/placement/run/setup.tcl"]} {
    source "work/PNR/placement/run/setup.tcl"
} else {
    handle_error "Cannot find generated setup file. Run 'make placement_setup' first."
}

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global pnr project tech flow
handle_info "Starting PNR place with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "place"
set NODE_NAME "place1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

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
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/placement.enc"

    # Final placement verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.rpt" }

    log_stage_status "placement" "COMPLETE" "Placement completed successfully"
}



# Exit tool after stage completion
exit
