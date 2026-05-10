#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PNR Post Route Stage with MMMC Support
# Description: Post-route optimization and ECO with multi-corner analysis
# Usage: Source this file in PNR tool
# ═══════════════════════════════════════════════════════════════════════════════

# Source flow utilities (includes flow procedure management)
if {[file exists "$FLOW_DIR/utils/utils.tcl"]} {
    source "$FLOW_DIR/utils/utils.tcl"
} else {
    handle_error "Cannot find flow utilities"
}

# Source generated configuration file (from setup stage)
if {[file exists "work/PNR/post_route/run/config.tcl"]} {
    source "work/PNR/post_route/run/config.tcl"
} else {
    handle_error "Cannot find generated config file. Run 'make post_route_setup' first."
}

# Source generated setup file (from setup stage)
if {[file exists "work/PNR/post_route/run/setup.tcl"]} {
    source "work/PNR/post_route/run/setup.tcl"
} else {
    handle_error "Cannot find generated setup file. Run 'make post_route_setup' first."
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
handle_info "Starting PNR post_route with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "post_route"
set NODE_NAME "pro1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

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
    
    # Create analysis views for each post_route scenario
    create_mmmc_scenarios_for_node "post_route"

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

    handle_info "MMMC scenarios configured for post_route stage"
}

flow_proc extract_parasitics {
    handle_info "Extracting parasitics..."

    # Get extraction parameters from config
    global pnr
    set extraction_mode $pnr(extract,mode)
    set rc_corner       $pnr(extract,rc_corner)
    set extract_effort  [expr {[info exists pnr(extract,effort)] ? $pnr(extract,effort) : "high"}]

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
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/post_route.enc"

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
exit
