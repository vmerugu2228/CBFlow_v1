#!/usr/bin/env tclsh
# CBFlow PNR pro1 - Synopsys Fusion Compiler | PNR pro1
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PNR/pro1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR pro1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/pro1"
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
# flow_proc: configure_route_opt
# Description: Configure post-route optimization settings including PBA mode,
#              StarRC extraction, and VMF
# ==============================================================================
flow_proc configure_route_opt {
    handle_info "Configuring route_opt settings..."
    global pnr tech

    # Set QoR strategy for post_route stage
    if {[info exists fc(compile,qor_version)] && $fc(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $fc(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage post_route"
    if {[info exists fc(compile,qor_metric)] && $fc(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $fc(compile,qor_metric)
    }
    if {[info exists fc(compile,qor_mode)] && $fc(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $fc(compile,qor_mode)
    }
    if {[info exists fc(compile,reduced_effort)] && $fc(compile,reduced_effort)} {
        lappend set_qor_strategy_cmd -reduced_effort
    }
    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value route_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value route_opt_cts_

    # Set active scenarios for route_opt
    if {[info exists fc(pro,active_scenarios)] && $fc(pro,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(pro,active_scenarios)
    }

    # Configure PBA optimization mode
    if {[info exists fc(pro,pba_mode)] && $fc(pro,pba_mode) ne ""} {
        if {[regexp {^(none|path|exhaustive)$} $fc(pro,pba_mode)]} {
            handle_info "Setting time.pba_optimization_mode to $fc(pro,pba_mode)"
            set_app_options -name time.pba_optimization_mode -value $fc(pro,pba_mode)
            if {$fc(pro,pba_mode) eq "exhaustive"} {
                set_app_options -name time.pba_exhaustive_endpoint_path_limit -value 16
            }
        } else {
            handle_warning "Invalid PBA mode: $fc(pro,pba_mode). Valid values: none|path|exhaustive"
        }
    }

    # Configure StarRC extraction mode
    if {[info exists fc(pro,extraction_mode)] && $fc(pro,extraction_mode) ne ""} {
        set_app_options -name extract.starrc_mode -value $fc(pro,extraction_mode)
    }

    # StarRC in-design config file
    if {[info exists fc(pro,starrc_config)] && [file exists $fc(pro,starrc_config)]} {
        set config_path [file normalize $fc(pro,starrc_config)]
        set starrc_cmd "set_starrc_in_design -config $config_path"
        if {[info exists fc(pro,starrc_options)] && $fc(pro,starrc_options) ne ""} {
            append starrc_cmd " $fc(pro,starrc_options)"
        }
        handle_info "Running: $starrc_cmd"
        eval $starrc_cmd
    }

    # Virtual Metal Fill
    if {[info exists fc(pro,vmf_parameter_file)] && [file exists $fc(pro,vmf_parameter_file)]} {
        set vmf_cmd "set_extraction_options -virtual_metalfill_parameter_file $fc(pro,vmf_parameter_file)"
        handle_info "Running: $vmf_cmd"
        eval $vmf_cmd
    }

    handle_info "route_opt configuration completed"
}

# ==============================================================================
# flow_proc: run_route_opt_pass1
# Description: First route_opt pass (hyper_route_opt)
# ==============================================================================
flow_proc run_route_opt_pass1 {
    handle_info "Running route_opt pass 1 (hyper_route_opt)..."
    global pnr

    # Compute clock latency before optimization
    compute_clock_latency

    # Track DRC before core command
    if {[get_drc_error_data -quiet zroute.err] eq ""} { open_drc_error_data zroute.err }

    # Run hyper_route_opt (main route_opt in Y-2026.03)
    handle_info "Running hyper_route_opt"
    hyper_route_opt

    handle_info "route_opt pass 1 completed"
}

# ==============================================================================
# flow_proc: run_route_opt_pass2
# Description: Second route_opt pass for incremental DRC cleanup
# ==============================================================================
flow_proc run_route_opt_pass2 {
    handle_info "Running route_opt pass 2 (incremental DRC cleanup)..."
    global pnr

    # Track DRC counts
    if {[get_drc_error_data -quiet zroute.err] eq ""} { open_drc_error_data zroute.err }
    set drc_count [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]

    if {$drc_count > 0} {
        # Run incremental route_detail to fix remaining DRC
        handle_info "Running route_detail -incremental for $drc_count DRC violations"
        route_detail -incremental true -initial_drc_from_input true
    } else {
        handle_info "No DRC violations found -- skipping incremental route_detail"
    }

    handle_info "route_opt pass 2 completed"
}

# ==============================================================================
# flow_proc: run_route_opt_pass3
# Description: Third route_opt incremental pass for final convergence
# ==============================================================================
flow_proc run_route_opt_pass3 {
    handle_info "Running route_opt pass 3 (final incremental)..."
    global pnr

    # Post-route_opt redundant via insertion
    if {[info exists fc(pro,redundant_via_post)] && $fc(pro,redundant_via_post)} {
        handle_info "Running post-route_opt add_redundant_vias"
        add_redundant_vias
    }

    # Connect PG nets
    connect_pg_net

    # Check routes
    redirect -file $::REPORTS_DIR/check_routes.rpt {
        check_routes
    }

    handle_info "route_opt pass 3 completed"
}

# ==============================================================================
# flow_proc: add_redundant_vias
# Description: Insert redundant vias for yield improvement
# ==============================================================================
flow_proc add_redundant_vias {
    handle_info "Checking redundant via insertion settings..."
    global pnr

    if {[info exists fc(pro,redundant_via)] && $fc(pro,redundant_via)} {
        handle_info "Running add_redundant_vias -timing_preserve_setup_slack_threshold 0"
        add_redundant_vias -timing_preserve_setup_slack_threshold 0
    } else {
        handle_info "Redundant via insertion not enabled -- skipping"
    }
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after route optimization
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as $fc(common,design_name)/pro
        handle_info "Block saved as $fc(common,design_name)/pro"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive post-route optimization reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating post-route optimization reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    # FC-RM: Recommended timing settings for post-route reporting
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

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Congestion
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }

    # FC-RM: Threshold voltage group (Vt distribution)
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: SI crosstalk
    redirect -file $::REPORTS_DIR/report_si.rpt {
        report_timing -crosstalk_delta -max_paths $max_paths -nosplit
    }

    # FC-RM: App options
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label route_opt -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Post-route optimization reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# flow_proc: run_endpoint_opt
# Description: Targeted PBA-CCD endpoint optimization (ported from FC-RM endpoint_opt.tcl)
#              Runs targeted_ep_ropt_pba_ccd for last-mile Fmax push after route_opt.
#              Only runs if fc(pro,enable_endpoint_opt) is true.
#              Supports loop iterations via fc(pro,endpoint_opt_loop).
# ==============================================================================
flow_proc run_endpoint_opt {
    handle_info "Checking if endpoint optimization is enabled..."
    global pnr

    if {![info exists fc(pro,enable_endpoint_opt)] || !$fc(pro,enable_endpoint_opt)} {
        handle_info "Endpoint optimization not enabled -- skipping"
        return
    }

    handle_info "Running targeted endpoint PBA-CCD optimization..."

    # Track DRC before endpoint_opt
    if {[get_drc_error_data -quiet zroute.err] eq ""} {open_drc_error_data zroute.err}
    set rm_drc_before_ep [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]

    # Build targeted_ep_ropt_pba_ccd arguments
    if {[info exists fc(pro,endpoint_opt_auto)] && $fc(pro,endpoint_opt_auto)} {
        # Auto mode: let the tool determine endpoints and metrics
        set targeted_ep_args "-auto true"
    } else {
        # Manual mode: specify paths, slack threshold, and scenarios
        set targeted_ep_args ""
        if {[info exists fc(pro,endpoint_opt_max_paths)] && $fc(pro,endpoint_opt_max_paths) ne ""} {
            append targeted_ep_args " -max_paths $fc(pro,endpoint_opt_max_paths)"
        }
        if {[info exists fc(pro,endpoint_opt_slack_threshold)] && $fc(pro,endpoint_opt_slack_threshold) ne ""} {
            append targeted_ep_args " -slack_lesser_than $fc(pro,endpoint_opt_slack_threshold)"
        }
        if {[info exists fc(pro,endpoint_opt_scenarios)] && $fc(pro,endpoint_opt_scenarios) ne ""} {
            append targeted_ep_args " -scenarios [list $fc(pro,endpoint_opt_scenarios)]"
        }
        if {[info exists fc(pro,endpoint_opt_path_group_filter)] && $fc(pro,endpoint_opt_path_group_filter) ne ""} {
            append targeted_ep_args " -path_group_filter [list $fc(pro,endpoint_opt_path_group_filter)]"
        }
    }

    # Determine loop count
    if {[info exists fc(pro,endpoint_opt_loop)] && $fc(pro,endpoint_opt_loop) ne ""} {
        set ep_loop $fc(pro,endpoint_opt_loop)
    } else {
        set ep_loop 1
    }

    # Run endpoint optimization loop
    for {set iter 1} {$iter <= $ep_loop} {incr iter} {
        set start_time [clock seconds]
        handle_info "Running targeted_ep_ropt_pba_ccd pass $iter of $ep_loop"
        handle_info "Args: $targeted_ep_args"

        targeted_ep_ropt_pba_ccd {*}$targeted_ep_args

        set elapsed [expr {[clock seconds] - $start_time}]
        set elapsed_hrs [format "%.2f" [expr {$elapsed / 3600.0}]]
        handle_info "Endpoint opt pass $iter completed in ${elapsed}s (${elapsed_hrs}h)"
    }

    # Incremental route_detail for DRC cleanup after endpoint_opt
    if {[get_drc_error_data -quiet zroute.err] eq ""} {open_drc_error_data zroute.err}
    set rm_drc_after_ep [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]

    if {$rm_drc_after_ep > $rm_drc_before_ep} {
        handle_info "DRC increased from $rm_drc_before_ep to $rm_drc_after_ep -- running incremental route_detail"
        route_detail -incremental true -initial_drc_from_input true
    }

    handle_info "Endpoint optimization completed"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/PNR/pro1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.pro.tcl"
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
