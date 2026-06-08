#!/usr/bin/env tclsh
# CBFlow PNR pro1 - Synopsys Fusion Compiler | PNR pro1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "pro"
set NODE_NAME "pro1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: configure_route_opt
# Description: Configure post-route optimization settings including PBA mode,
#              StarRC extraction, and VMF
# ==============================================================================
flow_proc configure_route_opt {
    handle_info "Configuring route_opt settings..."
    global pnr tech

    # Set QoR strategy for post_route stage
    if {[info exists pnr(compile,qor_version)] && $pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $pnr(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage post_route"
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

    # Set instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value route_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value route_opt_cts_

    # Set active scenarios for route_opt
    if {[info exists pnr(pro,active_scenarios)] && $pnr(pro,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $pnr(pro,active_scenarios)
    }

    # Configure PBA optimization mode
    if {[info exists pnr(pro,pba_mode)] && $pnr(pro,pba_mode) ne ""} {
        if {[regexp {^(none|path|exhaustive)$} $pnr(pro,pba_mode)]} {
            handle_info "Setting time.pba_optimization_mode to $pnr(pro,pba_mode)"
            set_app_options -name time.pba_optimization_mode -value $pnr(pro,pba_mode)
            if {$pnr(pro,pba_mode) eq "exhaustive"} {
                set_app_options -name time.pba_exhaustive_endpoint_path_limit -value 16
            }
        } else {
            handle_warning "Invalid PBA mode: $pnr(pro,pba_mode). Valid values: none|path|exhaustive"
        }
    }

    # Configure StarRC extraction mode
    if {[info exists pnr(pro,extraction_mode)] && $pnr(pro,extraction_mode) ne ""} {
        set_app_options -name extract.starrc_mode -value $pnr(pro,extraction_mode)
    }

    # StarRC in-design config file
    if {[info exists pnr(pro,starrc_config)] && [file exists $pnr(pro,starrc_config)]} {
        set config_path [file normalize $pnr(pro,starrc_config)]
        set starrc_cmd "set_starrc_in_design -config $config_path"
        if {[info exists pnr(pro,starrc_options)] && $pnr(pro,starrc_options) ne ""} {
            append starrc_cmd " $pnr(pro,starrc_options)"
        }
        handle_info "Running: $starrc_cmd"
        eval $starrc_cmd
    }

    # Virtual Metal Fill
    if {[info exists pnr(pro,vmf_parameter_file)] && [file exists $pnr(pro,vmf_parameter_file)]} {
        set vmf_cmd "set_extraction_options -virtual_metalfill_parameter_file $pnr(pro,vmf_parameter_file)"
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
    if {[info exists pnr(pro,redundant_via_post)] && $pnr(pro,redundant_via_post)} {
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

    if {[info exists pnr(pro,redundant_via)] && $pnr(pro,redundant_via)} {
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

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling)} {
        save_block -as $pnr(common,design_name)/pro
        handle_info "Block saved as $pnr(common,design_name)/pro"
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
    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

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
#              Only runs if pnr(pro,enable_endpoint_opt) is true.
#              Supports loop iterations via pnr(pro,endpoint_opt_loop).
# ==============================================================================
flow_proc run_endpoint_opt {
    handle_info "Checking if endpoint optimization is enabled..."
    global pnr

    if {![info exists pnr(pro,enable_endpoint_opt)] || !$pnr(pro,enable_endpoint_opt)} {
        handle_info "Endpoint optimization not enabled -- skipping"
        return
    }

    handle_info "Running targeted endpoint PBA-CCD optimization..."

    # Track DRC before endpoint_opt
    if {[get_drc_error_data -quiet zroute.err] eq ""} {open_drc_error_data zroute.err}
    set rm_drc_before_ep [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]

    # Build targeted_ep_ropt_pba_ccd arguments
    if {[info exists pnr(pro,endpoint_opt_auto)] && $pnr(pro,endpoint_opt_auto)} {
        # Auto mode: let the tool determine endpoints and metrics
        set targeted_ep_args "-auto true"
    } else {
        # Manual mode: specify paths, slack threshold, and scenarios
        set targeted_ep_args ""
        if {[info exists pnr(pro,endpoint_opt_max_paths)] && $pnr(pro,endpoint_opt_max_paths) ne ""} {
            append targeted_ep_args " -max_paths $pnr(pro,endpoint_opt_max_paths)"
        }
        if {[info exists pnr(pro,endpoint_opt_slack_threshold)] && $pnr(pro,endpoint_opt_slack_threshold) ne ""} {
            append targeted_ep_args " -slack_lesser_than $pnr(pro,endpoint_opt_slack_threshold)"
        }
        if {[info exists pnr(pro,endpoint_opt_scenarios)] && $pnr(pro,endpoint_opt_scenarios) ne ""} {
            append targeted_ep_args " -scenarios [list $pnr(pro,endpoint_opt_scenarios)]"
        }
        if {[info exists pnr(pro,endpoint_opt_path_group_filter)] && $pnr(pro,endpoint_opt_path_group_filter) ne ""} {
            append targeted_ep_args " -path_group_filter [list $pnr(pro,endpoint_opt_path_group_filter)]"
        }
    }

    # Determine loop count
    if {[info exists pnr(pro,endpoint_opt_loop)] && $pnr(pro,endpoint_opt_loop) ne ""} {
        set ep_loop $pnr(pro,endpoint_opt_loop)
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
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
