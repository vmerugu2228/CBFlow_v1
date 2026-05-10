#!/usr/bin/env tclsh
# CBFlow PNR route1 - Synopsys Fusion Compiler | PNR route1
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PNR/route1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow
handle_info "Starting PNR route1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/route1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source -e $mmmc_config_file }

# ==============================================================================
# flow_proc: configure_routing
# Description: Set routing options, layer constraints, and antenna rules
# ==============================================================================
flow_proc configure_routing {
    handle_info "Configuring routing options..."
    global pnr tech

    # Set QoR strategy for route stage
    if {[info exists pnr(compile,qor_version)] && $pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $pnr(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage route"
    if {[info exists pnr(compile,qor_metric)] && $pnr(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $pnr(compile,qor_metric)
    }
    if {[info exists pnr(compile,qor_mode)] && $pnr(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $pnr(compile,qor_mode)
    }
    if {[info exists pnr(compile,reduced_effort)] && $pnr(compile,reduced_effort)} {
        lappend set_qor_strategy_cmd -reduced_effort
    }
    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set instance name prefix
    set_app_options -name opt.common.user_instance_name_prefix -value route_auto_

    # Set active scenarios for routing
    if {[info exists pnr(route,active_scenarios)] && $pnr(route,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $pnr(route,active_scenarios)
    }

    # Set routing layer constraints
    if {[info exists pnr(route_max_layer)] && $pnr(route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $pnr(route_max_layer)
    }
    if {[info exists pnr(route_min_layer)] && $pnr(route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $pnr(route_min_layer)
    }

    # Antenna rules
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Reading antenna rules: $tech(antenna_rule_file)"
        source -e $tech(antenna_rule_file)
    }

    handle_info "Routing configuration completed"
}

# ==============================================================================
# flow_proc: run_route_auto
# Description: Run automatic routing (route_auto)
# ==============================================================================
flow_proc run_route_auto {
    handle_info "Running route_auto..."

    route_auto

    handle_info "route_auto completed"
}

# ==============================================================================
# flow_proc: create_shields
# Description: Create shields on clock/signal nets if enabled
# ==============================================================================
flow_proc create_shields {
    handle_info "Checking shield creation settings..."
    global pnr

    if {[info exists pnr(route,enable_shields)] && $pnr(route,enable_shields)} {
        handle_info "Creating shields..."
        set_extraction_options -virtual_shield_extraction false

        set create_shields_cmd "create_shields"
        if {[info exists pnr(route,shields_options)] && $pnr(route,shields_options) ne ""} {
            append create_shields_cmd " $pnr(route,shields_options)"
        }
        if {[info exists pnr(route,shields_ground_net)] && $pnr(route,shields_ground_net) ne ""} {
            lappend create_shields_cmd -with_ground $pnr(route,shields_ground_net)
        }
        handle_info "Running: $create_shields_cmd"
        eval $create_shields_cmd
        handle_info "Shields created successfully"
    } else {
        handle_info "Shield creation not enabled -- skipping"
    }

    # Redundant via insertion after routing
    if {[info exists pnr(route,redundant_via)] && $pnr(route,redundant_via)} {
        handle_info "Running add_redundant_vias"
        add_redundant_vias
    }

    # Connect PG nets
    connect_pg_net

    # Check routes
    redirect -file $::REPORTS_DIR/check_routes.rpt {
        check_routes
    }

    handle_info "Post-routing shields and checks completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after routing
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling)} {
        save_block -as $pnr(design_name)/route
        handle_info "Block saved as $pnr(design_name)/route"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive routing reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating routing reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

    # FC-RM: Recommended timing settings for routed designs
    set_app_options -name time.delay_calc_waveform_analysis_mode -value full_design
    set_app_options -name time.enable_ccs_rcv_cap -value true

    # FC-RM: Timing
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min -nosplit
    }

    # FC-RM: QoR
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary -nosplit }

    # FC-RM: Design
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }

    # FC-RM: Routing-specific reports
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Clock QoR post-route
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }

    # FC-RM: Threshold voltage group
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: App options
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label route_auto -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Routing reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/PNR/route1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.route.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
