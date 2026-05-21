#!/usr/bin/env tclsh
# CBFlow PNR route1 - Synopsys Fusion Compiler | PNR route1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "route"
set NODE_NAME "route1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {[info exists pnr(common,route_max_layer)] && $pnr(common,route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $pnr(common,route_max_layer)
    }
    if {[info exists pnr(common,route_min_layer)] && $pnr(common,route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $pnr(common,route_min_layer)
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
        save_block -as $pnr(common,design_name)/route
        handle_info "Block saved as $pnr(common,design_name)/route"
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
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
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
