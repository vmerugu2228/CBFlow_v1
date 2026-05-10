#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR place (place_opt) - Synopsys Fusion Compiler
# FC-RM: place_opt.tcl -- Two-pass placement optimization (SPG and non-SPG flows)
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/SYNTH_PNR/place1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global synth_pnr project tech flow
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"

# Source tech_config (BUG FIX #1)
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
handle_info "Starting SYNTH_PNR place_opt (FC-RM Y-2026.03 aligned)..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/SYNTH_PNR/place1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from compile, link_block,
#         set_early_data_check_policy, hier abstract swap
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for place_opt..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists synth_pnr(design_lib_name)] ? $synth_pnr(design_lib_name) : "${design_name}.nlib"}]

    # FC-RM: open_lib, copy_block from compile to place_opt
    open_lib $lib_name
    copy_block -from ${design_name}/compile -to ${design_name}/place_opt
    current_block ${design_name}/place_opt

    # FC-RM: set_early_data_check_policy
    set qor_mode "balanced"
    if {[info exists synth_pnr(compile,qor_mode)]} { set qor_mode $synth_pnr(compile,qor_mode) }
    if {$qor_mode eq "early_design"} {
        set_early_data_check_policy -policy lenient -if_not_exist
    }

    link_block

    # FC-RM: Hierarchical — swap abstracts for place_opt
    set chip_type [expr {[info exists synth_pnr(chip_type)] ? $synth_pnr(chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        if {[info exists synth_pnr(block_abstract_for_place_opt)] && $synth_pnr(block_abstract_for_place_opt) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $synth_pnr(block_abstract_for_place_opt) 0] \
                -view [lindex $synth_pnr(block_abstract_for_place_opt) 1]
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
}

# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status, hold scenario check
# ==============================================================================
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for place_opt..."
    global synth_pnr

    # Priority: synth_pnr user override > mmmc_config get_node_scenarios("placement")
    if {[info exists synth_pnr(place_opt,active_scenarios)] && $synth_pnr(place_opt,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $synth_pnr(place_opt,active_scenarios)
        handle_info "Active scenarios (user override): $synth_pnr(place_opt,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "placement" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/placement): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file
    if {[info exists synth_pnr(mcmm_adjustment_file)] && [file exists $synth_pnr(mcmm_adjustment_file)]} {
        source -e $synth_pnr(mcmm_adjustment_file)
    }

    # FC-RM: Check hold scenarios for CCD
    if {[sizeof_collection [get_scenarios -filter "hold && active"]] == 0} {
        handle_warning "No active hold scenario. Recommended for CCD skewing in place_opt."
    }

    handle_info "Active scenarios configured"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage place_initial, routing layers,
#         disable power scenarios for timing metric
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for place_opt..."
    global synth_pnr

    # FC-RM: Build set_qor_strategy command
    set cmd "set_qor_strategy -stage place_initial"
    set metric "timing"
    set mode "balanced"
    if {[info exists synth_pnr(compile,qor_metric)]} { set metric $synth_pnr(compile,qor_metric) }
    if {[info exists synth_pnr(compile,qor_mode)]}   { set mode $synth_pnr(compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {[info exists synth_pnr(compile,reduced_effort)] && $synth_pnr(compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }
    if {[info exists synth_pnr(compile,congestion_effort)] && $synth_pnr(compile,congestion_effort) ne ""} {
        lappend cmd -congestion_effort $synth_pnr(compile,congestion_effort)
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: Routing layer constraints
    if {[info exists synth_pnr(route_max_layer)] && $synth_pnr(route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $synth_pnr(route_max_layer)
    }
    if {[info exists synth_pnr(route_min_layer)] && $synth_pnr(route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $synth_pnr(route_min_layer)
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
# flow_proc: configure_place_opt
# FC-RM: Instance prefixes, non-persistent settings, multi-Vt, CTS primary
#         corner, spare cells, freeze ports, mark ideal clocks, mark_clock_trees
# ==============================================================================
flow_proc configure_place_opt {
    handle_info "Configuring place_opt settings..."
    global synth_pnr tech

    # FC-RM: Instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value place_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value place_opt_cts_

    # FC-RM: Non-persistent settings
    if {[info exists synth_pnr(non_persistent_script)] && [file exists $synth_pnr(non_persistent_script)]} {
        source -e $synth_pnr(non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists synth_pnr(multi_vt_constraint_file)] && [file exists $synth_pnr(multi_vt_constraint_file)]} {
        source -e $synth_pnr(multi_vt_constraint_file)
    }

    # FC-RM: Lib cell purpose
    if {[info exists synth_pnr(lib_cell_purpose_file)] && [file exists $synth_pnr(lib_cell_purpose_file)]} {
        source -e $synth_pnr(lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source -e $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS primary corner
    if {[info exists synth_pnr(cts_primary_corner)] && $synth_pnr(cts_primary_corner) ne ""} {
        set_app_options -name cts.compile.primary_corner -value $synth_pnr(cts_primary_corner)
    }

    # FC-RM: Spare cells before place_opt
    if {[info exists synth_pnr(spare_cell_pre_script)] && [file exists $synth_pnr(spare_cell_pre_script)]} {
        source -e $synth_pnr(spare_cell_pre_script)
    }

    # FC-RM: Freeze ports for DFT hierarchy preservation
    if {[info exists synth_pnr(optimization_freeze_port_list)] && $synth_pnr(optimization_freeze_port_list) ne ""} {
        set_app_options -name opt.dft.hier_preservation -value true
        set_freeze_port -all [get_cells $synth_pnr(optimization_freeze_port_list)]
    }

    # FC-RM: User pre-place_opt script
    if {[info exists synth_pnr(place_opt_pre_script)] && [file exists $synth_pnr(place_opt_pre_script)]} {
        source -e $synth_pnr(place_opt_pre_script)
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
    set chip_type [expr {[info exists synth_pnr(chip_type)] ? $synth_pnr(chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    # FC-RM: Mark clock trees for NDR impact modeling
    handle_info "Running mark_clock_trees -routing_rules"
    mark_clock_trees -routing_rules

    handle_info "Place_opt configuration completed"
}

# ==============================================================================
# flow_proc: run_place_opt
# FC-RM: place_opt — SPG or non-SPG (two-pass) flow,
#         high utilization flow support
# ==============================================================================
flow_proc run_place_opt {
    handle_info "Running place_opt..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]

    # FC-RM: SVF
    set_svf $::OUTPUTS_DIR/${design_name}_place_opt.svf

    set enable_spg false
    if {[info exists synth_pnr(compile,enable_spg)]} { set enable_spg $synth_pnr(compile,enable_spg) }

    if {$enable_spg} {
        # ── SPG flow ──────────────────────────────────────────────────────────
        handle_info "Running place_opt (SPG flow)"
        place_opt
    } else {
        # ── Non-SPG two-pass flow ─────────────────────────────────────────────

        # FC-RM: High utilization flow (pre-pass)
        set high_util false
        if {[info exists synth_pnr(place_opt,high_utilization_flow)]} {
            set high_util $synth_pnr(place_opt,high_utilization_flow)
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
        if {[info exists synth_pnr(place_opt_incremental_post_script)] && [file exists $synth_pnr(place_opt_incremental_post_script)]} {
            source -e $synth_pnr(place_opt_incremental_post_script)
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
}

# ==============================================================================
# flow_proc: post_place_opt
# FC-RM: User post script, spare cells, connect_pg_net,
#         re-enable power scenarios
# ==============================================================================
flow_proc post_place_opt {
    handle_info "Running post-place_opt tasks..."
    global synth_pnr

    # FC-RM: User post-place_opt script
    if {[info exists synth_pnr(place_opt_post_script)] && [file exists $synth_pnr(place_opt_post_script)]} {
        source -e $synth_pnr(place_opt_post_script)
    }

    # FC-RM: Spare cell insertion after place_opt
    if {[info exists synth_pnr(spare_cell_post_script)] && [file exists $synth_pnr(spare_cell_post_script)]} {
        source -e $synth_pnr(spare_cell_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists synth_pnr(connect_pg_net_script)] && [file exists $synth_pnr(connect_pg_net_script)]} {
        source -e $synth_pnr(connect_pg_net_script)
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
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical designs
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global synth_pnr

    set chip_type [expr {[info exists synth_pnr(chip_type)] ? $synth_pnr(chip_type) : "flat"}]

    if {$chip_type eq "hierarchical"} {
        set hier_level "bottom"
        if {[info exists synth_pnr(physical_hierarchy_level)]} { set hier_level $synth_pnr(physical_hierarchy_level) }
        if {$hier_level ne "top"} {
            handle_info "Creating abstract and frame (level=$hier_level)"
            create_abstract -read_only
            create_frame -block_all true
        }
    }

    handle_info "Abstracts completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block, set_svf -off
# ==============================================================================
flow_proc save_design {
    handle_info "Saving place_opt design..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]

    save_block
    if {[info exists synth_pnr(output,block_labeling)] && $synth_pnr(output,block_labeling)} {
        save_block -as ${design_name}/place_opt
        handle_info "Block saved: ${design_name}/place_opt"
    }

    set_svf -off
    handle_info "Place_opt design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_congestion, report_power,
#         write_qor_data, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating place_opt reports..."
    global synth_pnr

    set max_paths [expr {[info exists synth_pnr(analysis,max_paths)] ? $synth_pnr(analysis,max_paths) : 100}]

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
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/SYNTH_PNR/place1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.place.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
