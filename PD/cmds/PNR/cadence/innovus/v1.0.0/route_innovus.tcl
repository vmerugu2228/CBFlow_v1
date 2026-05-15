#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PNR Route Stage with MMMC Support
# Description: Global and detailed routing with multi-corner awareness
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
if {[file exists "work/PNR/route/run/config.tcl"]} {
    source "work/PNR/route/run/config.tcl"
} else {
    handle_error "Cannot find generated config file. Run 'make route_setup' first."
}

# Source generated setup file (from setup stage)
if {[file exists "work/PNR/route/run/setup.tcl"]} {
    source "work/PNR/route/run/setup.tcl"
} else {
    handle_error "Cannot find generated setup file. Run 'make route_setup' first."
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
# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR route with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "route"
set NODE_NAME "route1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ═══════════════════════════════════════════════════════════════════════════════
# ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc enable_mmmc {
    # Enable MMMC scenarios for route stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for route stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "route" "setup"]
    set hold_scenarios [get_effective_scenarios "route" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for route, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "route"]
    
    handle_info "route MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Create analysis views for each routing scenario
    create_mmmc_scenarios_for_node "route"

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

    handle_info "MMMC scenarios configured for route stage"
}

flow_proc setup_routing {
    handle_info "Setting up routing parameters..."

    # Get routing parameters from config
    global pnr
    set route_effort   $innovus(route,effort)
    set route_layers   $innovus(route,layers)
    set via_opt        $innovus(route,via_opt)
    set si_aware       $innovus(route,si_aware)
    set timing_driven  [expr {[info exists innovus(route,timing_driven)]  ? $innovus(route,timing_driven)  : "true"}]

    handle_info "Routing parameters:"
    handle_info "  Effort: $route_effort"
    handle_info "  Layers: $route_layers"
    handle_info "  Via optimization: $via_opt"
    handle_info "  SI-aware: $si_aware"
    handle_info "  Timing driven: $timing_driven"

    # Configure NanoRoute
    setNanoRouteMode -routeTopRoutingLayer [lindex [split $route_layers ":"] 1]
    setNanoRouteMode -routeBottomRoutingLayer [lindex [split $route_layers ":"] 0]
    setNanoRouteMode -drouteUseMultiCutViaEffort $route_effort
    setNanoRouteMode -routeWithViaInPin $via_opt
    setNanoRouteMode -routeWithTimingDriven $timing_driven
    setNanoRouteMode -routeWithSiDriven $si_aware
}

flow_proc run_global_route {
    handle_info "Running global routing..."

    # Global routing
    globalRoute

    handle_info "Global routing completed"
}

flow_proc run_detailed_route {
    handle_info "Running detailed routing..."

    # Detailed routing
    detailRoute

    handle_info "Detailed routing completed"
}

flow_proc optimize_routing {
    handle_info "Optimizing routing..."

    # Post-route optimization
    global pnr
    set optimization_effort $innovus(route,post_opt_effort)

    handle_info "Post-route optimization effort: $optimization_effort"

    # Post-route timing optimization
    optDesign -postRoute -effort $optimization_effort

    handle_info "Routing optimization completed"
}

flow_proc fix_violations {
    handle_info "Fixing routing violations..."

    # DRC fixing
    ecoRoute -fix_drc

    # Antenna fixing
    global pnr
    set fix_antenna $innovus(route,fix_antenna)
    if {$fix_antenna eq "true"} {
        handle_info "Fixing antenna violations..."
        addAntennaDiode
    }

    handle_info "Violation fixing completed"
}

flow_proc analyze_routing {
    handle_info "Analyzing routing quality..."

    # Generate routing reports
    file mkdir "$::REPORTS_DIR"

    # Route analysis reports
    catch { report_route > "$::REPORTS_DIR/report_route.rpt" }
    catch { verify_drc -report "$::REPORTS_DIR/verify_drc.rpt" }
    catch { checkRoute -outfile "$::REPORTS_DIR/check_route.rpt" }
    catch { report_timing -max_paths 50 > "$::REPORTS_DIR/report_timing.postRoute.rpt" }
    catch { reportCongestion -overflow > "$::REPORTS_DIR/report_congestion.rpt" }

    handle_info "Routing analysis completed"
}

flow_proc validate_pnr_route_results {
    global pnr project tech flow FLOW_DIR RUN_DIR ROOT_DIR

    handle_info "Running enhanced validation for PNR route stage..."

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
            handle_info "Running basic validation for PNR route..."
            if {[catch {exec tclsh $basic_validation_script PNR route $current_dir $validation_flow_dir} validation_result]} {
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
    handle_info "Command: tclsh $enhanced_validation_script PNR route $current_dir $validation_flow_dir"

    if {[catch {exec tclsh $enhanced_validation_script PNR route $current_dir $validation_flow_dir} validation_result]} {
        handle_error "Enhanced validation failed with critical errors detected"
        handle_info "Validation output: $validation_result"

        # Check if this is a critical error failure (exit code 1) vs other errors
        if {[string match "*critical*error*" [string tolower $validation_result]] ||
            [string match "*xterm*" [string tolower $validation_result]]} {
            handle_error "Critical errors detected in PNR route logs - check xterm display"
        }
        return 0
    } else {
        handle_info "Enhanced validation completed successfully"
        handle_info "Validation output: $validation_result"
        return 1
    }
}

flow_proc route_complete {
    handle_info "Route stage complete"

    # Enhanced validation with critical error detection
    handle_info "Running enhanced validation for route stage..."
    validate_pnr_route_results

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/route.enc"

    # Final route verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.rpt" }
    catch { timeDesign -postRoute -outDir "$::REPORTS_DIR" -prefix postRoute }

    log_stage_status "route" "COMPLETE" "Routing completed successfully"
}



# Exit tool after stage completion
exit
