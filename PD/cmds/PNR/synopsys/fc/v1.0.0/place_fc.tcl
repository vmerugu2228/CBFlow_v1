#!/usr/bin/env tclsh
# CBFlow PNR place1 - Synopsys Fusion Compiler | PNR place1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "place"
set NODE_NAME "place1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: set_stage_qor_strategy
# Description: Set QoR strategy for compile/placement stage
# ==============================================================================
flow_proc set_stage_qor_strategy {
    handle_info "Setting QoR strategy for compile stage..."
    global pnr

    # Set QoR strategy version if specified
    if {[info exists pnr(compile,qor_version)] && $pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $pnr(compile,qor_version)
    }

    set set_qor_strategy_cmd "set_qor_strategy -stage compile_initial"
    if {[info exists pnr(compile,qor_metric)] && $pnr(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $pnr(compile,qor_metric)
    }
    if {[info exists pnr(compile,qor_mode)] && $pnr(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $pnr(compile,qor_mode)
    }
    if {[info exists pnr(compile,reduced_effort)] && $pnr(compile,reduced_effort)} {
        lappend set_qor_strategy_cmd -reduced_effort
    } elseif {[info exists pnr(compile,high_effort_timing)] && $pnr(compile,high_effort_timing)} {
        lappend set_qor_strategy_cmd -high_effort_timing
    }
    if {[info exists pnr(compile,congestion_effort)] && $pnr(compile,congestion_effort) ne ""} {
        lappend set_qor_strategy_cmd -congestion_effort $pnr(compile,congestion_effort)
    }

    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set routing layer constraints
    if {[info exists pnr(common,route_max_layer)] && $pnr(common,route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $pnr(common,route_max_layer)
    }
    if {[info exists pnr(common,route_min_layer)] && $pnr(common,route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $pnr(common,route_min_layer)
    }

    handle_info "QoR strategy for compile stage set successfully"
}

# ==============================================================================
# flow_proc: configure_compile
# Description: Set application options for compile_fusion
# ==============================================================================
flow_proc configure_compile {
    handle_info "Configuring compile settings..."
    global pnr

    # Set instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value compile_
    set_app_options -name cts.common.user_instance_name_prefix -value compile_cts_

    # Set active scenarios for compile if specified
    if {[info exists pnr(compile,active_scenarios)] && $pnr(compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $pnr(compile,active_scenarios)
    }

    # Clock NDR modeling at compile_fusion
    handle_info "Running mark_clock_trees -routing_rules to model clock NDR impact"
    mark_clock_trees -routing_rules

    # MV cells insertion
    handle_info "Running create_mv_cells"
    create_mv_cells -verbose

    handle_info "Compile configuration completed"
}

# ==============================================================================
# flow_proc: run_compile
# Description: Run compile_fusion -- unified flow or stage-by-stage
# ==============================================================================
flow_proc run_compile {
    handle_info "Running compile_fusion..."
    global pnr

    if {[info exists pnr(compile,unified_flow)] && $pnr(compile,unified_flow)} {
        # Unified compile flow: runs all stages end-to-end
        handle_info "Running compile_fusion (unified flow)"
        compile_fusion
    } else {
        # Stage-by-stage compile through initial_opto
        handle_info "Running compile_fusion -to initial_opto"
        compile_fusion -to initial_opto
    }

    handle_info "compile_fusion completed"
}

# ==============================================================================
# flow_proc: run_classic_place_opt
# Description: Run classic place_opt flow (ported from FC-RM place_opt.tcl)
#              Two-pass placement, clock NDR, ideal network, high-util support
#              Only runs if NOT unified compile flow
# ==============================================================================
flow_proc run_classic_place_opt {
    handle_info "Checking if classic place_opt is needed..."
    global pnr

    if {[info exists pnr(compile,unified_flow)] && $pnr(compile,unified_flow)} {
        handle_info "Unified flow enabled -- skipping classic place_opt"
        return
    }

    # Set QoR strategy for place_initial stage
    set set_qor_strategy_cmd "set_qor_strategy -stage place_initial"
    if {[info exists pnr(compile,qor_metric)] && $pnr(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $pnr(compile,qor_metric)
    }
    if {[info exists pnr(compile,qor_mode)] && $pnr(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $pnr(compile,qor_mode)
    }
    if {[info exists pnr(compile,reduced_effort)] && $pnr(compile,reduced_effort)} {
        lappend set_qor_strategy_cmd -reduced_effort
    }
    if {[info exists pnr(compile,congestion_effort)] && $pnr(compile,congestion_effort) ne ""} {
        lappend set_qor_strategy_cmd -congestion_effort $pnr(compile,congestion_effort)
    }
    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set instance name prefixes for place_opt
    set_app_options -name opt.common.user_instance_name_prefix -value place_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value place_opt_cts_

    # Mark clock network as ideal (from FC-RM place_opt.tcl)
    handle_info "Marking clock network as ideal"
    set currentMode [current_mode]
    foreach_in_collection mode [all_modes] {
        current_mode $mode
        set clock_tree [remove_from_collection [all_fanout -flat -clock_tree] [all_registers -clock_pins]]
        if {[sizeof_collection $clock_tree] > 0} {
            set_ideal_network $clock_tree
            remove_propagated_clock [get_pins -hierarchical]
            remove_propagated_clock [get_ports]
            remove_propagated_clock [get_clocks -filter !is_virtual]
        }
    }
    current_mode $currentMode

    # Clock NDR modeling -- make place_opt recognize clock NDR for congestion impact
    handle_info "Running mark_clock_trees -routing_rules to model clock NDR impact during place_opt"
    mark_clock_trees -routing_rules

    # High-utilization flow support (from FC-RM place_opt.tcl)
    if {[info exists pnr(place,high_utilization_flow)] && $pnr(place,high_utilization_flow)} {
        handle_info "High-utilization flow enabled"
        handle_info "Disabling AWP, running remove_buffer_trees, create_placement -buffering_aware_timing_driven, and initial_drc"
        reset_app_options time.delay_calc_wareform_analysis_mode
        remove_buffer_trees -all
        create_placement -buffering_aware_timing_driven
        place_opt -from initial_drc -to initial_drc
    }

    ##########################################################################
    ## Two-pass place_opt: first pass (from FC-RM place_opt.tcl)
    ##########################################################################
    handle_info "Running place_opt -from initial_place -to initial_place (pass 1 -- buffering-aware with CDR)"
    place_opt -from initial_place -to initial_place

    handle_info "Running place_opt -from initial_drc -to initial_drc"
    place_opt -from initial_drc -to initial_drc

    handle_info "Running update_timing -full"
    update_timing -full

    ##########################################################################
    ## Two-pass place_opt: second pass (from FC-RM place_opt.tcl)
    ##########################################################################
    handle_info "Running create_placement -incremental -timing_driven -congestion (pass 2)"
    create_placement -incremental -timing_driven -congestion

    handle_info "Running place_opt -from initial_drc (full second pass)"
    place_opt -from initial_drc

    # Extra place_opt pass for high-utilization flow
    if {[info exists pnr(place,high_utilization_flow)] && $pnr(place,high_utilization_flow)} {
        handle_info "High-utilization flow: running extra place_opt -from final_place"
        place_opt -from final_place
    }

    # SPG flow support
    if {[info exists pnr(compile,enable_spg)] && $pnr(compile,enable_spg)} {
        handle_info "SPG flow enabled -- running full place_opt"
        place_opt
    }

    handle_info "Classic place_opt stages completed"
}

# ==============================================================================
# flow_proc: connect_pg
# Description: Connect PG nets after compile
# ==============================================================================
flow_proc connect_pg {
    handle_info "Connecting power/ground nets..."

    connect_pg_net

    handle_info "Power/ground nets connected"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after placement
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling)} {
        save_block -as $pnr(common,design_name)/place
        handle_info "Block saved as $pnr(common,design_name)/place"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate placement quality and timing reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating placement reports..."
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

    # FC-RM: Design/physical
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion -rerun_global_router }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Legality check
    redirect -file $::REPORTS_DIR/check_legality.rpt { check_legality }

    # FC-RM: Threshold voltage group
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: App options snapshot
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label place_opt -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Placement reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
