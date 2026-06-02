#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR cts (clock_opt_cts) - Synopsys Fusion Compiler
# FC-RM: clock_opt_cts.tcl -- Clock tree synthesis: build_clock + route_clock
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "cts"
set NODE_NAME "cts1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from place_opt, link_block, hier abstract swap
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for clock_opt_cts..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$synth_pnr(common,design_lib_name) ne "" ? $synth_pnr(common,design_lib_name) : "${design_name}.nlib"}]

    # FC-RM: open_lib, copy_block from place_opt to clock_opt_cts
    open_lib $lib_name
    copy_block -from ${design_name}/place_opt -to ${design_name}/clock_opt_cts
    current_block ${design_name}/clock_opt_cts
    link_block

    # FC-RM: Hierarchical — swap abstracts, promote clock balance points
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {$synth_pnr(common,block_abstract_for_cts) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $synth_pnr(common,block_abstract_for_cts) 0] \
                -view [lindex $synth_pnr(common,block_abstract_for_cts) 1]
            report_abstracts
        }
        # FC-RM: Promote clock tree exceptions from blocks to top
        if {$synth_pnr(common,promote_clock_balance_points) ne "" && $synth_pnr(common,promote_clock_balance_points)} {
            if {$synth_pnr(common,promote_abstract_clock_data_file) ne "" && [file exists $synth_pnr(common,promote_abstract_clock_data_file)]} {
                source -e $synth_pnr(common,promote_abstract_clock_data_file)
            }
        }
        # FC-RM: Disable sub-block timing paths
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Design loaded: ${design_name}/clock_opt_cts"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for CTS (include hold for CCD)
# ==============================================================================
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for clock_opt_cts..."
    global synth_pnr

    # Priority: synth_pnr override > mmmc_config get_node_scenarios("cts")
    if {$synth_pnr(cts,clock_opt_cts,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $synth_pnr(cts,clock_opt_cts,active_scenarios)
        handle_info "Active scenarios (user override): $synth_pnr(cts,clock_opt_cts,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "cts" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/cts): $node_scenarios"
        }
    }

    # FC-RM: MCMM adjustment file
    if {$synth_pnr(common,mcmm_adjustment_file) ne "" && [file exists $synth_pnr(common,mcmm_adjustment_file)]} {
        source -e $synth_pnr(common,mcmm_adjustment_file)
    }

    # FC-RM: Check hold scenarios — critical for CCD skewing
    if {[sizeof_collection [get_scenarios -filter "hold && active"]] == 0} {
        handle_warning "No active hold scenario! CCD skewing requires hold scenarios for CTS."
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage cts, disable power scenarios
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for CTS..."
    global synth_pnr

    # FC-RM: QoR strategy version
    if {$synth_pnr(common,compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $synth_pnr(common,compile,qor_version)
    }

    set cmd "set_qor_strategy -stage cts"
    set metric "timing"
    set mode "balanced"
    if {$synth_pnr(common,compile,qor_metric) ne ""} { set metric $synth_pnr(common,compile,qor_metric) }
    if {$synth_pnr(common,compile,qor_mode) ne ""}   { set mode $synth_pnr(common,compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {$synth_pnr(common,compile,reduced_effort) ne "" && $synth_pnr(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: Disable power scenarios for timing optimization
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
# ==============================================================================
# flow_proc: configure_cts
# FC-RM: Instance prefixes, lib_cell_purpose, non-persistent, multi-Vt,
#         antenna rules, sidefile, MSCTS mesh routing
# ==============================================================================
flow_proc configure_cts {
    handle_info "Configuring CTS settings..."
    global synth_pnr tech
    apply_vt_dont_use

    # FC-RM: Instance name prefixes
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_

    # FC-RM: Lib cell purpose
    if {$synth_pnr(common,lib_cell_purpose_file) ne "" && [file exists $synth_pnr(common,lib_cell_purpose_file)]} {
        source -e $synth_pnr(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source -e $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS sidefile
    if {$synth_pnr(cts,cts_sidefile) ne "" && [file exists $synth_pnr(cts,cts_sidefile)]} {
        source -e $synth_pnr(cts,cts_sidefile)
    }

    # FC-RM: Non-persistent settings
    if {$synth_pnr(common,non_persistent_script) ne "" && [file exists $synth_pnr(common,non_persistent_script)]} {
        source -e $synth_pnr(common,non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {$synth_pnr(common,multi_vt_constraint_file) ne "" && [file exists $synth_pnr(common,multi_vt_constraint_file)]} {
        source -e $synth_pnr(common,multi_vt_constraint_file)
    }

    # FC-RM: Antenna rule file
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Sourcing antenna rules: $tech(antenna_rule_file)"
        source -e $tech(antenna_rule_file)
    }

    # FC-RM: User CTS pre-script
    if {$synth_pnr(cts,cts_pre_script) ne "" && [file exists $synth_pnr(cts,cts_pre_script)]} {
        source -e $synth_pnr(cts,cts_pre_script)
    }

    # FC-RM: Pre-CTS reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }
    redirect -file $::REPORTS_DIR/pre_cts.report_clock_settings { report_clock_settings }
    redirect -file $::REPORTS_DIR/pre_cts.check_clock_tree { check_clock_trees }

    # FC-RM: MSCTS mesh routing (if configured)
    if {$synth_pnr(cts,mscts_mesh_routing_script) ne "" && [file exists $synth_pnr(cts,mscts_mesh_routing_script)]} {
        mark_clock_trees -clear -dont_touch
        source -e $synth_pnr(cts,mscts_mesh_routing_script)
    }

    handle_info "CTS configuration completed"
# ==============================================================================
# flow_proc: build_clock_trees
# FC-RM: clock_opt -from build_clock -to build_clock (with relaxed transition)
# ==============================================================================
flow_proc build_clock_trees {
    handle_info "Building clock trees..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_clock_opt_cts.svf

    # FC-RM: Check and apply relaxed clock transition constraint
    handle_info "Checking relaxed clock transition constraint"
    check_clock_transition -threshold 0.15 -apply_max_transition

    # FC-RM: Build clock trees
    handle_info "Running clock_opt -from build_clock -to build_clock"
    clock_opt -from build_clock -to build_clock
    save_block -as ${design_name}/clock_opt_cts_build_clock

    # FC-RM: Set propagated clocks after build_clock
    handle_info "Setting propagated clocks"
    set_propagated_clock [all_clocks]

    # FC-RM: Compute clock latency
    compute_clock_latency

    # FC-RM: Restore original clock transition
    restore_clock_transition

    handle_info "Clock trees built"
# ==============================================================================
# flow_proc: route_clock_nets
# FC-RM: clock_opt -from route_clock -to route_clock
# ==============================================================================
flow_proc route_clock_nets {
    handle_info "Routing clock nets..."

    # FC-RM: Route clock nets
    handle_info "Running clock_opt -from route_clock -to route_clock"
    clock_opt -from route_clock -to route_clock

    handle_info "Clock nets routed"
# ==============================================================================
# flow_proc: post_cts_optimization
# FC-RM: Redundant via insertion, AOCV enable, create_shields
# ==============================================================================
flow_proc post_cts_optimization {
    handle_info "Running post-CTS optimization..."
    global synth_pnr tech

    # FC-RM: Redundant via insertion
    if {$synth_pnr(cts,redundant_via) ne "" && $synth_pnr(cts,redundant_via)} {
        if {[info exists tech(redundant_via_mapping_file)] && [file exists $tech(redundant_via_mapping_file)]} {
            handle_info "Sourcing redundant via mapping"
            source -e $tech(redundant_via_mapping_file)
            redirect -file $::REPORTS_DIR/report_via_mapping.rpt { report_via_mapping }
        }
        handle_info "Adding redundant vias"
        add_redundant_vias
    }

    # FC-RM: Enable AOCV after CTS (recommended)
    if {$synth_pnr(cts,clock_opt_cts,enable_aocv) ne "" && $synth_pnr(cts,clock_opt_cts,enable_aocv)} {
        set_app_options -name time.aocvm_enable_analysis -value true
        handle_info "AOCV analysis enabled after CTS"
    }

    # FC-RM: Create shields
    if {$synth_pnr(cts,cts,enable_shields) ne "" && $synth_pnr(cts,cts,enable_shields)} {
        set shields_cmd "create_shields"
        if {$synth_pnr(cts,cts,shields_options) ne ""} {
            append shields_cmd " $synth_pnr(cts,cts,shields_options)"
        }
        if {$synth_pnr(cts,cts,shields_ground_net) ne ""} {
            lappend shields_cmd -with_ground $synth_pnr(cts,cts,shields_ground_net)
        }
        handle_info "Running: $shields_cmd"
        eval $shields_cmd
    }

    # FC-RM: User post-CTS script
    if {$synth_pnr(cts,cts_post_script) ne "" && [file exists $synth_pnr(cts,cts_post_script)]} {
        source -e $synth_pnr(cts,cts_post_script)
    }

    handle_info "Post-CTS optimization completed"
# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net, re-enable power scenarios, check_routes
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting PG nets and finalizing..."
    global synth_pnr

    # FC-RM: connect_pg_net
    if {$synth_pnr(common,connect_pg_net_script) ne "" && [file exists $synth_pnr(common,connect_pg_net_script)]} {
        source -e $synth_pnr(common,connect_pg_net_script)
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

    # FC-RM: check_routes
    redirect -file $::REPORTS_DIR/check_routes { check_routes -open_net false }

    handle_info "PG nets connected, routes checked"
# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global synth_pnr

    set _run_type $flow(run_type)

    if {$_run_type eq "hier"} {
        set hier_level "bottom"
        if {$synth_pnr(common,physical_hierarchy_level) ne ""} { set hier_level $synth_pnr(common,physical_hierarchy_level) }
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
flow_proc save_design {
    handle_info "Saving clock_opt_cts design..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    save_block
    if {$synth_pnr(common,output,block_labeling) ne "" && $synth_pnr(common,output,block_labeling)} {
        save_block -as ${design_name}/clock_opt_cts
        handle_info "Block saved: ${design_name}/clock_opt_cts"
    }

    set_svf -off
    handle_info "CTS design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_clock_qor, report_clock_timing,
#         write_qor_data, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS reports..."
    global synth_pnr

    set max_paths [expr {$synth_pnr(common,analysis,max_paths) ne "" ? $synth_pnr(common,analysis,max_paths) : 100}]

    # FC-RM: Timing reports
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min -nosplit
    }

    # FC-RM: QoR reports
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary -nosplit }

    # FC-RM: Clock-specific reports
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }
    redirect -file $::REPORTS_DIR/report_clock_timing.setup.rpt {
        report_clock_timing -type summary -scenarios [all_scenarios]
    }
    redirect -file $::REPORTS_DIR/report_clock_timing.skew.rpt {
        report_clock_timing -type skew -scenarios [all_scenarios]
    }

    # FC-RM: Design and congestion
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Threshold voltage group
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: Congestion after CTS
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }

    # FC-RM: App options end state
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label clock_opt_cts -output $run_dir/qor_data
    }

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "CTS reports generated in: $::REPORTS_DIR"
# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
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
set _stage_override "$run_dir/setup/override_setup.cts.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
