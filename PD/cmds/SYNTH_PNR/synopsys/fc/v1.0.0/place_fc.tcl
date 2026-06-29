#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR place (place_opt) - Synopsys Fusion Compiler
# FC-RM: place_opt.tcl -- Two-pass placement optimization (SPG and non-SPG flows)
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "place"
set NODE_NAME "place1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from compile, link_block,
#         set_early_data_check_policy, hier abstract swap
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for place_opt..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$synth_pnr(common,design_lib_name) ne "" ? $synth_pnr(common,design_lib_name) : "${design_name}.nlib"}]

    # FC-RM: open_lib, copy_block from compile to place_opt
    open_lib $lib_name
    copy_block -from ${design_name}/compile -to ${design_name}/place_opt
    current_block ${design_name}/place_opt

    # FC-RM: set_early_data_check_policy
    set qor_mode "balanced"
    if {[info exists synth_pnr(common,compile,qor_mode)] && $synth_pnr(common,compile,qor_mode) ne ""} { set qor_mode $synth_pnr(common,compile,qor_mode) }
    if {$qor_mode eq "early_design"} {
        set_early_data_check_policy -policy lenient -if_not_exist
    }

    link_block

    # FC-RM: Hierarchical — swap abstracts for place_opt
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {[info exists synth_pnr(common,block_abstract_for_place_opt)] && $synth_pnr(common,block_abstract_for_place_opt) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $synth_pnr(common,block_abstract_for_place_opt) 0] \
                -view [lindex $synth_pnr(common,block_abstract_for_place_opt) 1]
            report_abstracts
        }
        # Ensure sub-block editability is false
        foreach_in_collection c [get_blocks -hierarchical] {
            if {[get_editability -blocks $c] == true} {
                set_editability -blocks $c -value false
            }
        }
        report_editability -blocks [get_blocks -hierarchical]
    }

    handle_info "Design loaded: ${design_name}/place_opt"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status, hold scenario check
# ==============================================================================
}
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for place_opt..."
    global synth_pnr

    # Priority: synth_pnr user override > mmmc_config get_node_scenarios("placement")
    if {[info exists synth_pnr(place,opt_active_scenarios)] && $synth_pnr(place,opt_active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $synth_pnr(place,opt_active_scenarios)
        handle_info "Active scenarios (user override): $synth_pnr(place,opt_active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "placement" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/placement): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file
    if {[info exists synth_pnr(common,mcmm_adjustment_file)] && $synth_pnr(common,mcmm_adjustment_file) ne "" && [file exists $synth_pnr(common,mcmm_adjustment_file)]} {
        source $synth_pnr(common,mcmm_adjustment_file)
    }

    # FC-RM: Check hold scenarios for CCD
    if {[sizeof_collection [get_scenarios -filter "hold && active"]] == 0} {
        handle_warning "No active hold scenario. Recommended for CCD skewing in place_opt."
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage place_initial, routing layers,
#         disable power scenarios for timing metric
# ==============================================================================
}
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for place_opt..."
    global synth_pnr

    # FC-RM: Build set_qor_strategy command
    set cmd "set_qor_strategy -stage place_initial"
    set metric "timing"
    set mode "balanced"
    if {[info exists synth_pnr(common,compile,qor_metric)] && $synth_pnr(common,compile,qor_metric) ne ""} { set metric $synth_pnr(common,compile,qor_metric) }
    if {[info exists synth_pnr(common,compile,qor_mode)] && $synth_pnr(common,compile,qor_mode) ne ""}   { set mode $synth_pnr(common,compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {[info exists synth_pnr(common,compile,reduced_effort)] && $synth_pnr(common,compile,reduced_effort) ne "" && $synth_pnr(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }
    if {[info exists synth_pnr(common,compile,congestion_effort)] && $synth_pnr(common,compile,congestion_effort) ne ""} {
        lappend cmd -congestion_effort $synth_pnr(common,compile,congestion_effort)
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: Routing layer constraints
    if {[info exists synth_pnr(common,route_max_layer)] && $synth_pnr(common,route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $synth_pnr(common,route_max_layer)
    }
    if {[info exists synth_pnr(common,route_min_layer)] && $synth_pnr(common,route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $synth_pnr(common,route_min_layer)
    }

    # FC-RM: Disable power scenarios for timing metric optimization
    if {$metric eq "timing"} {
        set ::rm_leakage_scenarios [get_object_name [get_scenarios -filter "active==true&&leakage_power==true"]]
        set ::rm_dynamic_scenarios [get_object_name [get_scenarios -filter "active==true&&dynamic_power==true"]]
        if {[llength $::rm_leakage_scenarios] > 0 || [llength $::rm_dynamic_scenarios] > 0} {
            handle_info "Disabling power analysis for timing optimization"
            set_scenario_status -leakage_power false -dynamic_power false \
                [get_scenarios "$::rm_leakage_scenarios $::rm_dynamic_scenarios"]
        }
    } elseif {$metric eq "leakage_power"} {
        set ::rm_dynamic_scenarios [get_object_name [get_scenarios -filter "active==true&&dynamic_power==true"]]
        if {[llength $::rm_dynamic_scenarios] > 0} {
            set_scenario_status -dynamic_power false [get_scenarios $::rm_dynamic_scenarios]
        }
    }

    handle_info "QoR strategy set: metric=$metric, mode=$mode"
}

# ==============================================================================
# flow_proc: insert_low_power_cells
# Optional UPF-driven low-power insertion: power switches, isolation cells,
# level shifters, always-on buffers. Gated on <flow>(place,lowpower_enable)
# OR <flow>(common,lowpower_enable) == "true". UPF must already have been
# loaded by init_design's load_constraints step. Default OFF.
# ==============================================================================
flow_proc insert_low_power_cells {
    if {![lowpower_enabled place]} {
        handle_info "Low-power insertion disabled (place,lowpower_enable != true) — skipping"
        return
    }
    handle_info "Low-power insertion enabled — staging globals for place"
    lowpower_stage_globals place
    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/lowpower_fc.tcl"
    if {![file exists $_recipe]} {
        set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/lowpower_fc.tcl"
    }
    handle_info "Sourcing low-power recipe: $_recipe"
    source $_recipe
}

# ==============================================================================
# flow_proc: configure_place_opt
# FC-RM: Instance prefixes, non-persistent settings, multi-Vt, CTS primary
#         corner, spare cells, freeze ports, mark ideal clocks, mark_clock_trees
# ==============================================================================
flow_proc configure_place_opt {
    handle_info "Configuring place_opt settings..."
    global flow synth_pnr tech
    apply_vt_dont_use

    # FC-RM: Instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value place_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value place_opt_cts_

    # FC-RM: Non-persistent settings
    if {[info exists synth_pnr(common,non_persistent_script)] && $synth_pnr(common,non_persistent_script) ne "" && [file exists $synth_pnr(common,non_persistent_script)]} {
        source $synth_pnr(common,non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists synth_pnr(common,multi_vt_constraint_file)] && $synth_pnr(common,multi_vt_constraint_file) ne "" && [file exists $synth_pnr(common,multi_vt_constraint_file)]} {
        source $synth_pnr(common,multi_vt_constraint_file)
    }

    # FC-RM: Lib cell purpose
    if {[info exists synth_pnr(common,lib_cell_purpose_file)] && $synth_pnr(common,lib_cell_purpose_file) ne "" && [file exists $synth_pnr(common,lib_cell_purpose_file)]} {
        source $synth_pnr(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS primary corner
    if {[info exists synth_pnr(common,cts_primary_corner)] && $synth_pnr(common,cts_primary_corner) ne ""} {
        set_app_options -name cts.compile.primary_corner -value $synth_pnr(common,cts_primary_corner)
    }

    # FC-RM: Spare cells before place_opt
    if {[info exists synth_pnr(common,spare_cell_pre_script)] && $synth_pnr(common,spare_cell_pre_script) ne "" && [file exists $synth_pnr(common,spare_cell_pre_script)]} {
        source $synth_pnr(common,spare_cell_pre_script)
    }

    # FC-RM: Freeze ports for DFT hierarchy preservation
    if {[info exists synth_pnr(common,optimization_freeze_port_list)] && $synth_pnr(common,optimization_freeze_port_list) ne ""} {
        set_app_options -name opt.dft.hier_preservation -value true
        set_freeze_port -all [get_cells $synth_pnr(common,optimization_freeze_port_list)]
    }

    # FC-RM: User pre-place_opt script
    if {[info exists synth_pnr(place,place_opt_pre_script)] && $synth_pnr(place,place_opt_pre_script) ne "" && [file exists $synth_pnr(place,place_opt_pre_script)]} {
        source $synth_pnr(place,place_opt_pre_script)
    }

    # FC-RM: Pre-place_opt reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }

    # FC-RM: Mark clock network as ideal and remove propagated clocks
    handle_info "Marking clock network as ideal"
    set cur_mode [current_mode]
    foreach_in_collection mode [all_modes] {
        current_mode $mode
        catch {
            set clock_tree [remove_from_collection [all_fanout -flat -clock_tree] [all_registers -clock_pins]]
            if {[sizeof_collection $clock_tree] > 0} {
                set_ideal_network $clock_tree
                remove_propagated_clock [get_pins -hierarchical]
                remove_propagated_clock [get_ports]
                remove_propagated_clock [get_clocks -filter "!is_virtual"]
            }
        }
    }
    current_mode $cur_mode

    # FC-RM: Disable timing paths for hierarchical sub-blocks
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    # FC-RM: Mark clock trees for NDR impact modeling
    handle_info "Running mark_clock_trees -routing_rules"
    mark_clock_trees -routing_rules

    handle_info "Place_opt configuration completed"
# ==============================================================================
# flow_proc: run_place_opt
# FC-RM: place_opt — SPG or non-SPG (two-pass) flow,
#         high utilization flow support
# ==============================================================================
}
flow_proc run_place_opt {
    handle_info "Running place_opt..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: SVF
    set_svf $::OUTPUTS_DIR/${design_name}_place_opt.svf

    set enable_spg false
    if {[info exists synth_pnr(synthesis,compile,enable_spg)] && $synth_pnr(synthesis,compile,enable_spg) ne ""} { set enable_spg $synth_pnr(synthesis,compile,enable_spg) }

    if {$enable_spg} {
        # ── SPG flow ──────────────────────────────────────────────────────────
        handle_info "Running place_opt (SPG flow)"
        place_opt
    } else {
        # ── Non-SPG two-pass flow ─────────────────────────────────────────────

        # FC-RM: High utilization flow (pre-pass)
        set high_util false
        if {[info exists synth_pnr(place,place_opt,high_utilization_flow)] && $synth_pnr(place,place_opt,high_utilization_flow) ne ""} {
            set high_util $synth_pnr(place,place_opt,high_utilization_flow)
        }
        if {$high_util} {
            handle_info "High utilization flow: running pre-placement steps"
            reset_app_options time.delay_calc_wareform_analysis_mode
            remove_buffer_trees -all
            create_placement -buffering_aware_timing_driven
            place_opt -from initial_drc -to initial_drc
        }

        # FC-RM: First pass — initial_place
        handle_info "place_opt -from initial_place -to initial_place"
        place_opt -from initial_place -to initial_place

        # FC-RM: Initial DRC
        handle_info "place_opt -from initial_drc -to initial_drc"
        place_opt -from initial_drc -to initial_drc
        update_timing -full

        # FC-RM: Second pass — incremental congestion-driven placement
        handle_info "create_placement -incremental -timing_driven -congestion"
        create_placement -incremental -timing_driven -congestion
        save_block -as ${design_name}/place_opt_two_pass

        # FC-RM: User script between passes
        if {[info exists synth_pnr(place,place_opt_incremental_post_script)] && $synth_pnr(place,place_opt_incremental_post_script) ne "" && [file exists $synth_pnr(place,place_opt_incremental_post_script)]} {
            source $synth_pnr(place,place_opt_incremental_post_script)
        }

        # FC-RM: Final place_opt from initial_drc
        handle_info "place_opt -from initial_drc"
        place_opt -from initial_drc

        # FC-RM: Extra pass for high utilization
        if {$high_util} {
            handle_info "High utilization: extra place_opt -from final_place"
            place_opt -from final_place
        }
    }

    handle_info "place_opt completed"
# ==============================================================================
# flow_proc: post_place_opt
# FC-RM: User post script, spare cells, connect_pg_net,
#         re-enable power scenarios
# ==============================================================================
}
flow_proc post_place_opt {
    handle_info "Running post-place_opt tasks..."
    global flow synth_pnr

    # FC-RM: User post-place_opt script
    if {[info exists synth_pnr(place,place_opt_post_script)] && $synth_pnr(place,place_opt_post_script) ne "" && [file exists $synth_pnr(place,place_opt_post_script)]} {
        source $synth_pnr(place,place_opt_post_script)
    }

    # FC-RM: Spare cell insertion after place_opt
    if {[info exists synth_pnr(common,spare_cell_post_script)] && $synth_pnr(common,spare_cell_post_script) ne "" && [file exists $synth_pnr(common,spare_cell_post_script)]} {
        source $synth_pnr(common,spare_cell_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists synth_pnr(common,connect_pg_net_script)] && $synth_pnr(common,connect_pg_net_script) ne "" && [file exists $synth_pnr(common,connect_pg_net_script)]} {
        source $synth_pnr(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # FC-RM: Re-enable power analysis
    if {[info exists ::rm_leakage_scenarios] && [llength $::rm_leakage_scenarios] > 0} {
        handle_info "Re-enabling leakage power analysis"
        set_scenario_status -leakage_power true [get_scenarios $::rm_leakage_scenarios]
    }
    if {[info exists ::rm_dynamic_scenarios] && [llength $::rm_dynamic_scenarios] > 0} {
        handle_info "Re-enabling dynamic power analysis"
        set_scenario_status -dynamic_power true [get_scenarios $::rm_dynamic_scenarios]
    }

    handle_info "Post-place_opt tasks completed"
# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical designs
# ==============================================================================
}
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global flow synth_pnr

    set _run_type $flow(run_type)

    if {$_run_type eq "hier"} {
        set hier_level "bottom"
        if {[info exists synth_pnr(common,physical_hierarchy_level)] && $synth_pnr(common,physical_hierarchy_level) ne ""} { set hier_level $synth_pnr(common,physical_hierarchy_level) }
        if {$hier_level ne "top"} {
            handle_info "Creating abstract and frame (level=$hier_level)"
            create_abstract -read_only
            create_frame -block_all true
        }
    }

    handle_info "Abstracts completed"
# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block, set_svf -off
# ==============================================================================
}
flow_proc save_design {
    handle_info "Saving place_opt design..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists synth_pnr(common,output,block_labeling)] && $synth_pnr(common,output,block_labeling) ne "" && $synth_pnr(common,output,block_labeling)} {
        save_block -as ${design_name}/place_opt
        handle_info "Block saved: ${design_name}/place_opt"
        cbflow_record_block_state $::STAGE_NAME "place_opt" $::NODE_NAME
    }

    set_svf -off
    handle_info "Place_opt design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_congestion, report_power,
#         write_qor_data, run_end
# ==============================================================================
}
flow_proc generate_reports {
    handle_info "Generating place_opt reports..."
    global synth_pnr

    set max_paths [expr {$synth_pnr(common,analysis,max_paths) ne "" ? $synth_pnr(common,analysis,max_paths) : 100}]

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

    # FC-RM: Clock QoR
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }

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

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Place_opt reports generated in: $::REPORTS_DIR"
# ==============================================================================
# ==============================================================================
}
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
