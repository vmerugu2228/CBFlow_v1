#!/usr/bin/env tclsh
# STA mmmc_setup - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "mmmc_setup"
set NODE_NAME "mmmc_setup1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting STA MMMC setup with Cadence Tempus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/mmmc_setup"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source $mmmc_config_file
} else {
    puts stderr "ERROR: MMMC config not found: $mmmc_config_file"
    exit 1
}

flow_proc setup_mmmc_dirs {
    handle_info "Setting up MMMC directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/STA/mmmc_setup/run" "work/STA/mmmc_setup/setup" "reports/sta" "results/sta" "logs/mmmc_setup"} {
        file mkdir "$run_dir/$dir"
    }
    puts " MMMC directories created"
}

flow_proc resolve_scenarios {
    handle_info "Resolving active MMMC scenario set..."
    global sta mmmc_scenario_sets analysis_views
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine scenario set: user override or default "signoff"
    if {[info exists sta(mmmc,scenario_set)]} {
        set scenario_set $sta(mmmc,scenario_set)
    } else {
        set scenario_set "signoff"
    }
    handle_info "Using scenario set: $scenario_set"

    # Retrieve scenarios from the selected set
    if {![info exists mmmc_scenario_sets($scenario_set)]} {
        puts stderr "ERROR: Unknown scenario set: $scenario_set"
        puts stderr "ERROR: Available sets: [join [array names mmmc_scenario_sets] { }]"
        exit 1
    }
    array set set_info $mmmc_scenario_sets($scenario_set)
    set active_scenarios $set_info(scenarios)
    handle_info "Resolved [llength $active_scenarios] scenarios for set '$scenario_set'"

    # Validate each scenario exists in analysis_views
    foreach scenario $active_scenarios {
        if {![info exists analysis_views($scenario)]} {
            puts stderr "ERROR: Scenario '$scenario' not found in analysis_views"
            exit 1
        }
    }

    # Write active scenarios file
    set out_file "$run_dir/work/STA/mmmc_setup/run/active_scenarios.tcl"
    file mkdir [file dirname $out_file]
    set fh [open $out_file "w"]
    puts $fh "#!/usr/bin/env tclsh"
    puts $fh "# Auto-generated MMMC active scenarios - [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fh "# Scenario set: $scenario_set"
    puts $fh "# Tool: Cadence Tempus"
    puts $fh ""
    puts $fh "set mmmc_active_scenario_set \"$scenario_set\""
    puts $fh "set mmmc_active_scenarios [list $active_scenarios]"
    puts $fh ""
    # Write per-scenario view details
    foreach scenario $active_scenarios {
        array set view_info $analysis_views($scenario)
        puts $fh "array set scenario_view_${scenario} [list [array get view_info]]"
        array unset view_info
    }
    close $fh
    handle_info "Active scenarios written to: $out_file"

    # Create Tempus analysis views for each scenario
    foreach scenario $active_scenarios {
        array set view_info $analysis_views($scenario)

        # Create Tempus analysis view
        create_analysis_view -name $scenario \
            -constraint_mode $view_info(mode) \
            -delay_corner "${view_info(corner)}_${view_info(rc_corner)}"
        handle_info "  Created analysis view: $scenario"

        file mkdir "$run_dir/work/STA/mmmc_setup/run/$scenario"
        file mkdir "$run_dir/reports/sta/$scenario"

        array unset view_info
    }

    # Set active analysis views in Tempus
    set setup_views {}
    set hold_views {}
    foreach scenario $active_scenarios {
        array set view_info $analysis_views($scenario)
        set atype $view_info(analysis_type)
        if {$atype eq "setup" || $atype eq "setup_hold"} {
            lappend setup_views $scenario
        }
        if {$atype eq "hold" || $atype eq "setup_hold"} {
            lappend hold_views $scenario
        }
        array unset view_info
    }
    set_analysis_view -setup $setup_views -hold $hold_views
    handle_info "Active analysis views configured for Tempus"

    puts " Scenario resolution completed"
}

flow_proc mmmc_setup_flow {
    handle_info "Executing STA MMMC setup flow..."
    flow_exec setup_mmmc_dirs
    flow_exec resolve_scenarios
    handle_info "STA MMMC setup completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec mmmc_setup_flow } else { puts " STA MMMC setup procedures loaded" }

# Exit tool after stage completion
exit
