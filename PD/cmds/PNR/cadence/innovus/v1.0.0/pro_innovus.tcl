#!/usr/bin/env tclsh
# PNR pro (post-route optimization) - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "pro"
set NODE_NAME "pro1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ==============================================================================
# flow_proc: load_design
# Description: Restore design from route stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db [cbflow_resolve_head_block "$run_dir/work/$::FLOW_TYPE/route1/outputs/route.enc.dat" {route cts_opt cts place init_design}]
    if {![file exists $_db]} {
        handle_warning "route database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}


# ═══════════════════════════════════════════════════════════════════════════════
# POST ROUTE
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc enable_mmmc {
    # Enable MMMC scenarios for post_route stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for post_route stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "post_route" "setup"]
    set hold_scenarios [get_effective_scenarios "post_route" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for post_route, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "post_route"]
    
    handle_info "post_route MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # View definitions live in init_design only (saved into the
    # restored .enc.dat). Here we only ACTIVATE the subset for this
    # node. Deactivate every existing view first so the activation
    # is exactly the requested set — no leakage from prior stages.
    set_analysis_view -setup {} -hold {}
    set_analysis_view -setup $setup_scenarios -hold $hold_scenarios

    handle_info "MMMC scenarios configured for post_route stage"
}

flow_proc extract_parasitics {
    handle_info "Extracting parasitics..."

    apply_vt_dont_use
    # Get extraction parameters from config
    global pnr
    if {![info exists pnr(extract,mode)] || $pnr(extract,mode) eq ""} {
        handle_error "pnr(extract,mode) not set (e.g., postRoute, signoff)"
        return
    }
    if {![info exists pnr(extract,effort)] || $pnr(extract,effort) eq ""} {
        handle_error "pnr(extract,effort) not set (e.g., low, medium, high, signoff)"
        return
    }
    set extraction_mode $pnr(extract,mode)
    set rc_corner       $pnr(extract,rc_corner)
    set extract_effort  $pnr(extract,effort)

    handle_info "Extraction parameters:"
    handle_info "  Mode: $extraction_mode"
    handle_info "  RC corner: $rc_corner"
    handle_info "  Effort: $extract_effort"

    # Configure and run parasitic extraction
    setExtractRCMode -engine postRoute -effort $extract_effort
    extractRC -engine postRoute

    handle_info "Parasitic extraction completed"
}

flow_proc run_post_route_opt {
    handle_info "Running post-route optimization..."

    # Post-route timing optimization from config
    global pnr
    set opt_effort   $pnr(route,post_opt_effort)
    set setup_margin $pnr(opt,setup_margin)
    set hold_margin  $pnr(opt,hold_margin)

    handle_info "Post-route optimization parameters:"
    handle_info "  Effort: $opt_effort"
    handle_info "  Setup margin: ${setup_margin}ns"
    handle_info "  Hold margin: ${hold_margin}ns"

    # Setup optimization with margin
    setOptMode -setupTargetSlack $setup_margin
    optDesign -postRoute -setup -effort $opt_effort

    # Hold optimization with margin
    setOptMode -holdTargetSlack $hold_margin
    optDesign -postRoute -hold -effort $opt_effort

    handle_info "Post-route optimization completed"
}

flow_proc run_eco_fixes {
    handle_info "Running ECO fixes..."

    # ECO fixing for timing violations
    ecoDesign -fix_timing

    # ECO fixing for DRC violations
    ecoRoute -fix_drc

    # Metal fill insertion
    global pnr
    set insert_metal_fill $pnr(opt,insert_metal_fill)
    if {$insert_metal_fill eq "true"} {
        handle_info "Inserting metal fill..."
        addMetalFill
    }

    handle_info "ECO fixes completed"
}

flow_proc verify_design {
    handle_info "Verifying design integrity..."

    file mkdir "$::REPORTS_DIR"

    # Connectivity verification
    catch { verifyConnectivity -type all -report "$::REPORTS_DIR/verify_connectivity.pre_eco.rpt" }

    # Geometry verification
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.pre_eco.rpt" }

    # Process antenna check
    catch { verifyProcessAntenna -report "$::REPORTS_DIR/verify_antenna.rpt" }

    handle_info "Design verification completed"
}

flow_proc final_timing_analysis {
    handle_info "Running final timing analysis..."

    # Generate comprehensive timing reports
    file mkdir "$::REPORTS_DIR"

    # Post-route timing analysis
    catch { timeDesign -postRoute -outDir "$::REPORTS_DIR" -prefix postRoute }
    catch { report_timing -max_paths 100 > "$::REPORTS_DIR/report_timing.setup.rpt" }
    catch { report_timing -delay_type min -max_paths 100 > "$::REPORTS_DIR/report_timing.hold.rpt" }
    catch { report_constraint -all_violators > "$::REPORTS_DIR/report_constraint.violations.rpt" }

    handle_info "Final timing analysis completed"
}

flow_proc generate_final_reports {
    handle_info "Generating final reports..."

    file mkdir "$::REPORTS_DIR"

    # Comprehensive reporting
    catch { report_area > "$::REPORTS_DIR/report_area.rpt" }
    catch { report_power > "$::REPORTS_DIR/report_power.rpt" }
    catch { report_clock_tree > "$::REPORTS_DIR/report_clock_tree.rpt" }
    catch { report_route > "$::REPORTS_DIR/report_route.rpt" }
    catch { verify_drc -report "$::REPORTS_DIR/verify_drc.rpt" }
    catch { checkRoute -outfile "$::REPORTS_DIR/check_route.rpt" }

    # Generate QOR summary
    catch { summaryReport -outfile "$::REPORTS_DIR/qor_summary.rpt" }

    handle_info "Final reports generated"
}

flow_proc post_route_complete {
    handle_info "Post-route stage complete"

    # Save final checkpoint
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/post_route.enc"
    cbflow_record_block_state $::STAGE_NAME "$_outputs/post_route.enc.dat" $::NODE_NAME

    # Generate final database
    global project
    set top_module $project(top_module)
    file mkdir "$::OUTPUTS_DIR"
    file mkdir "$::OUTPUTS_DIR/netlist"
    file mkdir "$::OUTPUTS_DIR/def"

    # Export final netlist
    saveNetlist "$::OUTPUTS_DIR/netlist/${top_module}_post_route.v"

    # Export final DEF
    defOut -floorplan -netlist -routing "$::OUTPUTS_DIR/def/${top_module}_post_route.def"

    # Final verification reports
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verifyGeometry -report "$::REPORTS_DIR/verify_geometry.rpt" }

    log_stage_status "post_route" "COMPLETE" "Post-route optimization completed successfully"
}


# Exit tool after stage completion

flow_exec_all
exit
