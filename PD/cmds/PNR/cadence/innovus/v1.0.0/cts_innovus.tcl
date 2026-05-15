#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PNR Clock Tree Synthesis Stage with MMMC Support
# Description: Clock tree synthesis and optimization across multiple scenarios
# Usage: Source this file in PNR tool
# ═══════════════════════════════════════════════════════════════════════════════

# Source flow utilities (includes flow procedure management)
if {[file exists "$FLOW_DIR/utils/utils.tcl"]} {
    source "$FLOW_DIR/utils/utils.tcl"
} else {
    handle_error "Cannot find flow utilities"
}

# Source generated configuration file (from setup stage)
if {[file exists "work/PNR/cts/run/config.tcl"]} {
    source "work/PNR/cts/run/config.tcl"
} else {
    handle_error "Cannot find generated config file. Run 'make cts_setup' first."
}

# Source generated setup file (from setup stage)
if {[file exists "work/PNR/cts/run/setup.tcl"]} {
    source "work/PNR/cts/run/setup.tcl"
} else {
    handle_error "Cannot find generated setup file. Run 'make cts_setup' first."
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
handle_info "Starting PNR cts with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load MMMC configuration if enabled
if {[is_mmmc_stage "cts"]} {
    load_mmmc_config
    handle_info "MMMC mode enabled for CTS stage"
}

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "cts"
set NODE_NAME "cts1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ═══════════════════════════════════════════════════════════════════════════════
# CLOCK TREE SYNTHESIS
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc enable_mmmc {
    # Enable MMMC scenarios for cts stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for cts stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "cts" "setup"]
    set hold_scenarios [get_effective_scenarios "cts" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for cts, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "cts"]
    
    handle_info "cts MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Create analysis views for each CTS scenario
    create_mmmc_scenarios_for_node "cts"

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

    handle_info "MMMC scenarios configured for cts stage"
}

flow_proc setup_cts {
    handle_info "Setting up CTS parameters..."

    # Get CTS parameters from config
    global pnr
    set cts_target_skew $innovus(cts,target_skew)
    set cts_max_trans   $innovus(cts,max_trans)
    set cts_max_cap     $innovus(cts,max_cap)

    handle_info "CTS parameters:"
    handle_info "  Target skew: ${cts_target_skew}ps"
    handle_info "  Max transition: ${cts_max_trans}ps"
    handle_info "  Max capacitance: ${cts_max_cap}fF"

    # Configure CTS engine properties
    set_ccopt_property target_skew $cts_target_skew
    set_ccopt_property max_transition $cts_max_trans
    set_ccopt_property max_capacitance $cts_max_cap
}

flow_proc create_clock_spec {
    handle_info "Creating clock tree specification..."
    
    # Get clock information from hierarchical configuration
    global project pnr
    if {[info exists project(clock,period)]} {
        handle_info "Clock period: $project(clock,period)ns"
    }
    
    if {[info exists project(clock,ports)]} {
        handle_info "Clock ports: $project(clock,ports)"
        # create_ccopt_clock_tree -name MAIN_CLK -source $project(clock,ports)
    }
    
    # Configure clock tree cells
    if {[info exists innovus(cts,buffer_cells)]} {
        handle_info "CTS buffer cells: $innovus(cts,buffer_cells)"
        set_ccopt_property buffer_cells $innovus(cts,buffer_cells)
    }

    if {[info exists innovus(cts,inverter_cells)]} {
        handle_info "CTS inverter cells: $innovus(cts,inverter_cells)"
        set_ccopt_property inverter_cells $innovus(cts,inverter_cells)
    }
}

flow_proc run_cts {
    handle_info "Running clock tree synthesis..."

    # Run CTS engine
    ccopt_design

    handle_info "Clock tree synthesis completed"
}

flow_proc optimize_cts {
    handle_info "Optimizing clock tree..."

    # Post-CTS optimization
    global pnr
    set optimization_effort $innovus(cts,opt_effort)

    handle_info "CTS optimization effort: $optimization_effort"

    # Post-CTS timing optimization
    optDesign -postCTS -effort $optimization_effort

    handle_info "Clock tree optimization completed"
}

flow_proc setup_mmmc_cts {
    handle_info "Setting up MMMC scenarios for CTS..."
    
    if {![is_mmmc_stage "cts"]} {
        handle_info "MMMC not enabled for CTS stage"
        return
    }
    
    global mmmc_config analysis_views
    set scenarios [get_mmmc_scenarios "cts"]
    
    # Create MMMC setup script
    set mmmc_dir "scripts"
    ensure_directory $mmmc_dir
    set mmmc_script "${mmmc_dir}/mmmc_setup_cts.tcl"
    
    set fp [open $mmmc_script "w"]
    puts $fp "# MMMC Setup for CTS Stage"
    puts $fp "# Auto-generated by OMNI FLOW"
    puts $fp ""
    
    # Setup analysis views for CTS scenarios
    foreach scenario $scenarios {
        if {[info exists analysis_views($scenario)]} {
            array set view_info $analysis_views($scenario)
            puts $fp "# Analysis view: $scenario"
            puts $fp "# Description: $view_info(description)"
            puts $fp "create_analysis_view -name $scenario \\"
            puts $fp "    -constraint_file $view_info(constraint_file) \\"
            puts $fp "    -library_set $view_info(lib_set) \\"
            puts $fp "    -rc_corner $view_info(rc_corner)"
            puts $fp ""
        }
    }
    
    puts $fp "# Set active scenarios for CTS"
    puts $fp "set_analysis_view -setup [list $scenarios]"
    puts $fp "set_analysis_view -hold [list $scenarios]"
    puts $fp ""
    puts $fp "puts \"MMMC setup completed for CTS with scenarios: $scenarios\""
    
    close $fp
    handle_info "MMMC setup script created: $mmmc_script"
    
    # Source the MMMC setup script in tool
    # source $mmmc_script
}

flow_proc analyze_cts {
    handle_info "Analyzing clock tree..."

    # Generate CTS reports
    file mkdir "$::REPORTS_DIR"

    # Standard CTS analysis
    catch { report_ccopt_skew_groups > "$::REPORTS_DIR/report_ccopt_skew_groups.rpt" }
    catch { report_ccopt_clock_trees > "$::REPORTS_DIR/report_ccopt_clock_trees.rpt" }
    catch { report_clock_timing -type summary > "$::REPORTS_DIR/report_clock_timing.rpt" }

    # MMMC-aware timing analysis
    if {[is_mmmc_stage "cts"]} {
        handle_info "Running MMMC timing analysis for CTS..."
        set scenarios [get_mmmc_scenarios "cts"]

        # Generate MMMC timing reports per scenario
        foreach scenario $scenarios {
            catch { report_timing -delay_type max -scenarios $scenario > "$::REPORTS_DIR/report_timing.setup.${scenario}.rpt" }
            catch { report_timing -delay_type min -scenarios $scenario > "$::REPORTS_DIR/report_timing.hold.${scenario}.rpt" }
        }

        # Generate MMMC summary reports
        catch { report_timing -scenarios $scenarios > "$::REPORTS_DIR/report_timing.mmmc_cts.rpt" }
        catch { report_constraint -scenarios $scenarios > "$::REPORTS_DIR/report_constraint.mmmc_cts.rpt" }
        catch { report_analysis_views > "$::REPORTS_DIR/report_analysis_views.rpt" }

        handle_info "MMMC analysis completed for scenarios: $scenarios"
    } else {
        # Standard single-corner analysis
        catch { report_timing -delay_type max > "$::REPORTS_DIR/report_timing.setup.rpt" }
        catch { report_timing -delay_type min > "$::REPORTS_DIR/report_timing.hold.rpt" }
    }

    handle_info "Clock tree analysis completed"
}

flow_proc fix_hold_violations {
    handle_info "Fixing hold violations..."

    # Post-CTS hold fixing
    optDesign -postCTS -hold

    handle_info "Hold violation fixing completed"
}

flow_proc cts_complete {
    handle_info "CTS stage complete"

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/cts.enc"

    # Final CTS verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { timeDesign -postCTS -outDir "$::REPORTS_DIR" -prefix postCTS }

    log_stage_status "cts" "COMPLETE" "Clock tree synthesis completed successfully"
}



# Exit tool after stage completion
exit
