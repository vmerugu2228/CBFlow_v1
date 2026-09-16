#!/usr/bin/env tclsh
# PNR route - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "route"
set NODE_NAME "route1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ==============================================================================
# flow_proc: load_design
# Description: Restore design from cts_opt stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db [cbflow_resolve_head_block "$run_dir/work/$::FLOW_TYPE/cts_opt1/outputs/cts_opt.enc.dat" {cts_opt cts place init_design}]
    if {![file exists $_db]} {
        handle_warning "cts_opt database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}


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
    
    # View definitions live in init_design only (saved into the
    # restored .enc.dat). Here we only ACTIVATE the subset for this
    # node. Deactivate every existing view first so the activation
    # is exactly the requested set — no leakage from prior stages.
    set_analysis_view -setup {} -hold {}
    set_analysis_view -setup $setup_scenarios -hold $hold_scenarios

    handle_info "MMMC scenarios configured for route stage"
}

flow_proc setup_routing {
    handle_info "Setting up routing parameters..."

    apply_vt_dont_use
    # Get routing parameters from config
    global pnr
    set route_effort   $pnr(route,effort)
    set route_layers   $pnr(route,layers)
    set via_opt        $pnr(route,via_opt)
    set si_aware       $pnr(route,si_aware)
    set timing_driven  [expr {[info exists pnr(route,timing_driven)]  ? $pnr(route,timing_driven)  : "true"}]

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
    set optimization_effort $pnr(route,post_opt_effort)

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
    set fix_antenna $pnr(route,fix_antenna)
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
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/route.enc"
    cbflow_record_block_state $::STAGE_NAME "$_outputs/route.enc.dat" $::NODE_NAME

    # Final route verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.rpt" }
    catch { timeDesign -postRoute -outDir "$::REPORTS_DIR" -prefix postRoute }

    log_stage_status "route" "COMPLETE" "Routing completed successfully"
}


# Exit tool after stage completion

flow_exec_all
exit
