#!/usr/bin/env tclsh
# PNR signoff - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "signoff"
set NODE_NAME "signoff1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


# ==============================================================================
# flow_proc: load_design
# Description: Restore design from pro stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db [cbflow_resolve_head_block "$run_dir/work/$::FLOW_TYPE/pro1/outputs/post_route.enc.dat" {pro route cts_opt cts place init_design}]
    if {![file exists $_db]} {
        handle_error "pro database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}


# ═══════════════════════════════════════════════════════════════════════════════
# SIGNOFF
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc enable_mmmc {
    # Enable MMMC scenarios for signoff stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for signoff stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "signoff" "setup"]
    set hold_scenarios [get_effective_scenarios "signoff" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for signoff, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "signoff"]
    
    handle_info "signoff MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Create analysis views for each signoff scenario
    create_mmmc_scenarios_for_node "signoff"

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

    handle_info "MMMC scenarios configured for signoff stage"
}

flow_proc run_signoff_drc {
    handle_info "Running signoff DRC..."

    file mkdir "$::REPORTS_DIR"

    # Signoff DRC check
    catch { verifyDRC -report "$::REPORTS_DIR/signoff_drc.rpt" }
    catch { verify_drc -limit 10000 -report "$::REPORTS_DIR/verify_drc.rpt" }

    handle_info "Signoff DRC completed"
}

flow_proc run_signoff_lvs {
    handle_info "Running signoff LVS..."

    file mkdir "$::REPORTS_DIR"

    # LVS check
    catch { verifyLVS -report "$::REPORTS_DIR/signoff_lvs.rpt" }

    handle_info "Signoff LVS completed"
}

flow_proc run_signoff_timing {
    handle_info "Running signoff timing analysis..."

    file mkdir "$::REPORTS_DIR"

    # Extract final parasitics for signoff
    global pnr
    if {![info exists pnr(signoff,extract_effort)] || $pnr(signoff,extract_effort) eq ""} {
        handle_error "pnr(signoff,extract_effort) not set (e.g., signoff, high)"
        return
    }
    set signoff_extract_effort $pnr(signoff,extract_effort)
    setExtractRCMode -engine postRoute -effort $signoff_extract_effort
    extractRC -engine postRoute

    # Signoff timing analysis
    catch { timeDesign -signoff -outDir "$::REPORTS_DIR" -prefix signoff }

    # Signoff timing reports
    catch { report_timing -max_paths 100 > "$::REPORTS_DIR/report_timing.signoff.max.rpt" }
    catch { report_timing -delay_type min -max_paths 100 > "$::REPORTS_DIR/report_timing.signoff.min.rpt" }

    # MMMC per-scenario signoff timing reports
    if {[info procs get_effective_scenarios] ne "" && [catch {get_effective_scenarios "signoff" "setup"} setup_scenarios] == 0 && [llength $setup_scenarios] > 0} {
        handle_info "Generating per-scenario signoff timing reports..."
        set all_signoff_scenarios [get_node_all_scenarios "signoff"]

        foreach scenario $all_signoff_scenarios {
            handle_info "  Signoff timing for scenario: $scenario"
            catch { report_timing -delay_type max -scenarios $scenario -max_paths 100 > "$::REPORTS_DIR/report_timing.signoff.setup.${scenario}.rpt" }
            catch { report_timing -delay_type min -scenarios $scenario -max_paths 100 > "$::REPORTS_DIR/report_timing.signoff.hold.${scenario}.rpt" }
            catch { report_constraint -all_violators -scenarios $scenario > "$::REPORTS_DIR/report_constraint.signoff.${scenario}.rpt" }
        }

        # Consolidated MMMC signoff report
        catch { timeDesign -signoff -expandedViews > "$::REPORTS_DIR/signoff_mcmm.rpt" }
        catch { report_analysis_views > "$::REPORTS_DIR/report_analysis_views.rpt" }
    }

    handle_info "Signoff timing analysis completed"
}

flow_proc run_signoff_power {
    handle_info "Running signoff power analysis..."

    file mkdir "$::REPORTS_DIR"

    # Power analysis
    catch { report_power -rail_analysis > "$::REPORTS_DIR/report_power.signoff.rpt" }
    catch { report_power -by_hierarchy > "$::REPORTS_DIR/report_power.hierarchy.rpt" }

    handle_info "Signoff power analysis completed"
}

flow_proc generate_deliverables {
    handle_info "Generating final deliverables..."

    global project pnr tech
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set stream_map_file [expr {[info exists tech(gds_map_file)] ? $tech(gds_map_file) : ""}]

    file mkdir "$::OUTPUTS_DIR"
    file mkdir "$::OUTPUTS_DIR/netlist"
    file mkdir "$::OUTPUTS_DIR/def"
    file mkdir "$::OUTPUTS_DIR/gds"
    file mkdir "$::OUTPUTS_DIR/sdc"

    # Final netlist
    saveNetlist "$::OUTPUTS_DIR/netlist/${top_module}_final.v"

    # Final DEF
    defOut -floorplan -netlist -routing "$::OUTPUTS_DIR/def/${top_module}_final.def"

    # Final SDC
    write_sdc "$::OUTPUTS_DIR/sdc/${top_module}_final.sdc"

    # GDS generation
    if {[info exists pnr(output,gds)] && $pnr(output,gds) ne ""} {
        handle_info "Generating GDS..."
        if {$stream_map_file ne ""} {
            streamOut "$::OUTPUTS_DIR/gds/${top_module}.gds" -mapFile $stream_map_file
        } else {
            handle_warning "tech(gds_map_file) not defined - skipping GDS stream out"
        }
    }

    # SPEF generation
    rcOut -spef "$::OUTPUTS_DIR/${top_module}.spef"

    handle_info "Deliverables generated"
}

flow_proc generate_signoff_reports {
    handle_info "Generating signoff reports..."

    file mkdir "$::REPORTS_DIR"

    # Comprehensive signoff reports
    catch { summaryReport -outfile "$::REPORTS_DIR/qor_summary.rpt" }
    catch { report_area -detailed > "$::REPORTS_DIR/report_area.rpt" }
    catch { report_clock_tree -summary > "$::REPORTS_DIR/report_clock_tree.rpt" }
    catch { report_route -detailed > "$::REPORTS_DIR/report_route.rpt" }

    # Violation summary
    catch { report_constraint -all_violators -verbose > "$::REPORTS_DIR/report_constraint.all_violators.rpt" }

    # Design statistics
    catch { report_design_statistics > "$::REPORTS_DIR/report_design_statistics.rpt" }

    # Connectivity and geometry verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { checkRoute -outfile "$::REPORTS_DIR/check_route.rpt" }

    handle_info "Signoff reports generated"
}

flow_proc validate_deliverables {
    handle_info "Validating deliverables..."

    # Check required files exist
    global project pnr
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set required_files [list]
    lappend required_files "$::OUTPUTS_DIR/netlist/${top_module}_final.v"
    lappend required_files "$::OUTPUTS_DIR/def/${top_module}_final.def"
    lappend required_files "$::OUTPUTS_DIR/sdc/${top_module}_final.sdc"
    
    foreach file $required_files {
        if {![file exists $file]} {
            handle_warning "Missing deliverable: $file"
        } else {
            handle_info "Validated: [file tail $file]"
        }
    }
    
    handle_info "Deliverable validation completed"
}

flow_proc signoff_complete {
    handle_info "Signoff stage complete"

    # Save final checkpoint
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/signoff.enc"
    cbflow_record_block_state $::STAGE_NAME "$_outputs/signoff.enc.dat" $::NODE_NAME

    # Generate design manifest
    file mkdir "$::REPORTS_DIR"
    set manifest_file "$::REPORTS_DIR/design_manifest.txt"
    
    set fd [open $manifest_file "w"]
    puts $fd "# OMNI FLOW Design Manifest"
    puts $fd "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    global project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    puts $fd "# Design: $top_module"
    puts $fd ""
    set design_version [expr {[info exists project(version)] ? $project(version) : "1.0"}]
    puts $fd "DESIGN_NAME: $top_module"
    puts $fd "DESIGN_VERSION: $design_version"
    puts $fd "FLOW_VERSION: CBFLOW_v2.0.0"
    puts $fd "SIGNOFF_DATE: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    close $fd
    
    log_stage_status "signoff" "COMPLETE" "Signoff completed - design ready for tapeout"
}


# Exit tool after stage completion

flow_exec_all
exit
