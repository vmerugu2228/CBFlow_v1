#!/usr/bin/env tclsh
# CBFlow PNR cts_opt1 - Synopsys Fusion Compiler | PNR cts_opt1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts_opt"
set NODE_NAME "cts_opt1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: configure_data_opt
# Description: Configure data path optimization options for post-CTS opto
# ==============================================================================
flow_proc configure_data_opt {
    handle_info "Configuring post-CTS opto options..."
    global pnr

    # Set QoR strategy for post_cts_opto stage
    if {[info exists pnr(compile,qor_version)] && $pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $pnr(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage post_cts_opto"
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
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_opto_
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_opto_cts_

    # Set active scenarios for this step
    if {[info exists pnr(cts_opt,active_scenarios)] && $pnr(cts_opt,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $pnr(cts_opt,active_scenarios)
    }

    # Propagate clocks to newly activated scenarios
    if {[info exists pnr(cts_opt,active_scenarios)] && $pnr(cts_opt,active_scenarios) ne ""} {
        handle_info "Propagating clocks to opto scenarios..."
        synthesize_clock_trees -propagate_only
        compute_clock_latency -verbose
    }

    # GRE - Global route focused scenario
    if {[info exists pnr(route,focused_scenario)] && $pnr(route,focused_scenario) ne ""} {
        set_app_options -name route.common.focus_scenario -value $pnr(route,focused_scenario)
    }

    handle_info "Post-CTS opto configuration completed"
}

# ==============================================================================
# flow_proc: run_clock_opt_opto
# Description: Run clock_opt final_opto phase for data path optimization
# ==============================================================================
flow_proc run_clock_opt_opto {
    handle_info "Running clock_opt final_opto..."

    handle_info "Running clock_opt -from final_opto -to final_opto"
    clock_opt -from final_opto -to final_opto

    handle_info "clock_opt final_opto completed"
}

# ==============================================================================
# flow_proc: run_global_route
# Description: Run global route for congestion estimation
# ==============================================================================
flow_proc run_global_route {
    handle_info "Running global route for congestion estimation..."

    # Connect PG nets
    connect_pg_net

    # Run check_routes
    redirect -file $::REPORTS_DIR/check_routes.rpt {
        check_routes
    }

    handle_info "Global route completed"
}

# ==============================================================================
# flow_proc: compute_latency
# Description: Compute clock latency for all scenarios
# ==============================================================================
flow_proc compute_latency {
    handle_info "Computing clock latency..."

    compute_clock_latency

    handle_info "Clock latency computation completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after CTS optimization
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling)} {
        save_block -as $pnr(common,design_name)/cts_opt
        handle_info "Block saved as $pnr(common,design_name)/cts_opt"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive post-CTS optimization reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS optimization reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

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

    # FC-RM: Clock QoR
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }
    redirect -file $::REPORTS_DIR/report_clock_timing.rpt {
        report_clock_timing -type summary -scenarios [all_scenarios]
    }

    # FC-RM: Design
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Threshold voltage group
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: Congestion after opto
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }

    # FC-RM: App options
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label clock_opt_opto -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "CTS optimization reports generated in: $::REPORTS_DIR"
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
set _stage_override "$run_dir/setup/override_setup.cts_opt.tcl"
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
