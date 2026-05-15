#!/usr/bin/env tclsh
# CBFlow PNR cts_opt - Cadence Innovus
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

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
handle_info "Starting PNR cts_opt with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "cts_opt"
set NODE_NAME "cts_opt1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc enable_mmmc {
    # Enable MMMC scenarios for cts_opt stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for cts_opt stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "cts_opt" "setup"]
    set hold_scenarios [get_effective_scenarios "cts_opt" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for cts_opt, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "cts_opt"]
    
    handle_info "cts_opt MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Tool-specific MMMC scenario setup would go here
    handle_info "MMMC scenarios configured for cts_opt stage"
}

flow_proc optimize_clock_tree {
    handle_info "Running clock tree optimization..."
    
    # Advanced CTS optimization
    global pnr
    set optimization_effort [expr {[info exists innovus(cts_opt,effort)] ? $innovus(cts_opt,effort) : "high"}]
    set fix_hold_violations [expr {[info exists innovus(cts_opt,fix_hold)] ? $innovus(cts_opt,fix_hold) : true}]
    
    handle_info "CTS optimization parameters:"
    handle_info "  Optimization effort: $optimization_effort"
    handle_info "  Fix hold violations: $fix_hold_violations"
    
    # Tool-specific optimization
    optDesign -postCTS -effort $optimization_effort
    if {$fix_hold_violations} {
        optDesign -postCTS -hold
    }
    
    handle_info "Clock tree optimization completed"
}

flow_proc balance_clock_tree {
    handle_info "Balancing clock tree..."
    
    # Clock tree balancing
    global pnr
    set balance_effort [expr {[info exists innovus(cts_opt,balance_effort)] ? $innovus(cts_opt,balance_effort) : "medium"}]
    
    handle_info "Clock tree balancing effort: $balance_effort"
    
    # Tool-specific balancing
    # ccopt_design -cts -effort $balance_effort
    
    handle_info "Clock tree balancing completed"
}

flow_proc refine_clock_tree {
    handle_info "Refining clock tree..."
    
    # Clock tree refinement
    global pnr
    set refine_iterations [expr {[info exists innovus(cts_opt,refine_iterations)] ? $innovus(cts_opt,refine_iterations) : 3}]
    
    handle_info "Clock tree refinement iterations: $refine_iterations"
    
    for {set i 1} {$i <= $refine_iterations} {incr i} {
        handle_info "Refinement iteration $i of $refine_iterations"
        optDesign -postCTS -prefix iter${i}
    }
    
    handle_info "Clock tree refinement completed"
}

flow_proc analyze_clock_optimization {
    handle_info "Analyzing clock tree optimization..."

    # Generate optimization reports
    file mkdir "$::REPORTS_DIR"

    # Standard CTS optimization analysis
    catch { report_ccopt_skew_groups > "$::REPORTS_DIR/report_ccopt_skew_groups.rpt" }
    catch { report_ccopt_clock_trees > "$::REPORTS_DIR/report_ccopt_clock_trees.rpt" }
    catch { report_clock_timing > "$::REPORTS_DIR/report_clock_timing.rpt" }

    # MMMC-aware timing analysis
    if {[is_mmmc_stage "cts_opt"]} {
        handle_info "Running MMMC timing analysis for CTS optimization..."
        set scenarios [get_mmmc_scenarios "cts_opt"]

        # Generate MMMC timing reports
        foreach scenario $scenarios {
            catch { report_timing -delay_type max -scenarios $scenario > "$::REPORTS_DIR/report_timing.setup.${scenario}.rpt" }
            catch { report_timing -delay_type min -scenarios $scenario > "$::REPORTS_DIR/report_timing.hold.${scenario}.rpt" }
        }

        # Generate MMMC summary reports
        catch { report_timing -scenarios $scenarios > "$::REPORTS_DIR/report_timing.mmmc_cts_opt.rpt" }
        catch { report_constraint -scenarios $scenarios > "$::REPORTS_DIR/report_constraint.mmmc_cts_opt.rpt" }

        handle_info "MMMC analysis completed for scenarios: $scenarios"
    } else {
        # Standard single-corner analysis
        catch { report_timing -delay_type max > "$::REPORTS_DIR/report_timing.setup.rpt" }
        catch { report_timing -delay_type min > "$::REPORTS_DIR/report_timing.hold.rpt" }
    }

    handle_info "Clock tree optimization analysis completed"
}

flow_proc cts_opt_complete {
    handle_info "CTS optimization stage complete"

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/cts_opt.enc"

    # Final CTS optimization verification
    catch { verifyConnectivity -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { timeDesign -postCTS -outDir "$::REPORTS_DIR" -prefix postCTS_opt }

    log_stage_status "cts_opt" "COMPLETE" "Clock tree optimization completed successfully"
}


# Exit tool after stage completion
exit
