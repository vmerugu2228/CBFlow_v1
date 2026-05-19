#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR route (route_auto) - Synopsys Fusion Compiler
# FC-RM: route_auto.tcl -- Automatic signal routing, redundant vias, shields,
#         StarRC in-design extraction, virtual metal fill
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

global synth_pnr project tech flow
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"

}

# Source FC tool config
set _fc_config "[file dirname [info script]]/fc_config.tcl"

handle_info "Starting SYNTH_PNR route_auto (FC-RM Y-2026.03 aligned)..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/SYNTH_PNR/route1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from clock_opt_opto, link_block, hier abstracts
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for route_auto..."
    global synth_pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    copy_block -from ${design_name}/clock_opt_opto -to ${design_name}/route_auto
    current_block ${design_name}/route_auto
    link_block

    # FC-RM: Hierarchical — swap abstracts
    set chip_type [expr {[info exists fc(common,chip_type)] ? $fc(common,chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        if {[info exists fc(common,block_abstract_for_route)] && $fc(common,block_abstract_for_route) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $fc(common,block_abstract_for_route) 0] \
                -view [lindex $fc(common,block_abstract_for_route) 1]
            report_abstracts
        }
    }

    handle_info "Design loaded: ${design_name}/route_auto"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for route
# ==============================================================================
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for route_auto..."
    global synth_pnr

    # Priority: synth_pnr override > mmmc_config get_node_scenarios("route")
    if {[info exists fc(common,route_auto,active_scenarios)] && $fc(common,route_auto,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $fc(common,route_auto,active_scenarios)
        handle_info "Active scenarios (user override): $fc(common,route_auto,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "route" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/route): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file
    if {[info exists fc(common,mcmm_adjustment_file)] && [file exists $fc(common,mcmm_adjustment_file)]} {
        source -e $fc(common,mcmm_adjustment_file)
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage route, instance prefix
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for route..."
    global synth_pnr

    if {[info exists fc(common,compile,qor_version)] && $fc(common,compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $fc(common,compile,qor_version)
    }

    set cmd "set_qor_strategy -stage route"
    set metric "timing"
    set mode "balanced"
    if {[info exists fc(common,compile,qor_metric)]} { set metric $fc(common,compile,qor_metric) }
    if {[info exists fc(common,compile,qor_mode)]}   { set mode $fc(common,compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {[info exists fc(common,compile,reduced_effort)] && $fc(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: Instance prefix
    set_app_options -name opt.common.user_instance_name_prefix -value route_auto_

    handle_info "QoR strategy set: metric=$metric, mode=$mode"
# ==============================================================================
# flow_proc: configure_route
# FC-RM: lib_cell_purpose, sidefile, non-persistent, multi-Vt,
#         pre-route reports, sub-block timing disable
# ==============================================================================
flow_proc configure_route {
    handle_info "Configuring route settings..."
    global synth_pnr tech

    # FC-RM: Lib cell purpose
    if {[info exists fc(common,lib_cell_purpose_file)] && [file exists $fc(common,lib_cell_purpose_file)]} {
        source -e $fc(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source -e $tech(lib_cell_purpose_file)
    }

    # FC-RM: Route sidefile
    if {[info exists fc(route,route_sidefile)] && [file exists $fc(route,route_sidefile)]} {
        source -e $fc(route,route_sidefile)
    }

    # FC-RM: Non-persistent settings
    if {[info exists fc(common,non_persistent_script)] && [file exists $fc(common,non_persistent_script)]} {
        source -e $fc(common,non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists fc(common,multi_vt_constraint_file)] && [file exists $fc(common,multi_vt_constraint_file)]} {
        source -e $fc(common,multi_vt_constraint_file)
    }

    # FC-RM: User pre-route script
    if {[info exists fc(route,route_pre_script)] && [file exists $fc(route,route_pre_script)]} {
        source -e $fc(route,route_pre_script)
    }

    # FC-RM: Routing layer constraints
    if {[info exists fc(common,route_max_layer)] && $fc(common,route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $fc(common,route_max_layer)
        handle_info "Max routing layer: $fc(common,route_max_layer)"
    }
    if {[info exists fc(common,route_min_layer)] && $fc(common,route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $fc(common,route_min_layer)
        handle_info "Min routing layer: $fc(common,route_min_layer)"
    }

    # FC-RM: Process antenna rules before routing
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Processing antenna rules: $tech(antenna_rule_file)"
        source -e $tech(antenna_rule_file)
        process_antenna_rules
    }

    # FC-RM: Pre-route reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }

    # FC-RM: check_design -checks pre_route_stage
    handle_info "Running pre-route design checks"
    redirect -file $::REPORTS_DIR/check_design.pre_route { check_design -checks pre_route_stage }

    # FC-RM: Disable sub-block timing for hierarchical
    set chip_type [expr {[info exists fc(common,chip_type)] ? $fc(common,chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Route configuration completed"
# ==============================================================================
# flow_proc: run_route_auto
# FC-RM: route_auto
# ==============================================================================
flow_proc run_route_auto {
    handle_info "Running route_auto..."
    global synth_pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_route_auto.svf

    # FC-RM: route_auto
    handle_info "Running route_auto command"
    route_auto

    # FC-RM: Initial post-route optimization (route_opt initial_opto)
    handle_info "Running route_opt -from initial_opto -to initial_opto"
    route_opt -from initial_opto -to initial_opto

    save_block -as ${design_name}/route_auto
    handle_info "route_auto completed"
# ==============================================================================
# flow_proc: post_route_auto
# FC-RM: Redundant via insertion, shield extraction options,
#         user post-script, connect_pg_net, check_routes
# ==============================================================================
flow_proc post_route_auto {
    handle_info "Running post-route tasks..."
    global synth_pnr tech

    # FC-RM: Redundant via insertion
    if {[info exists fc(route,route_auto,enable_redundant_via)] && $fc(route,route_auto,enable_redundant_via)} {
        handle_info "Adding redundant vias"
        add_redundant_vias
    }

    # FC-RM: Shield extraction options (if shields were created during CTS)
    if {[info exists fc(cts,cts,enable_shields)] && $fc(cts,cts,enable_shields)} {
        set_extraction_options -virtual_shield_extraction false
    }

    # FC-RM: User post-route script
    if {[info exists fc(route,route_post_script)] && [file exists $fc(route,route_post_script)]} {
        source -e $fc(route,route_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists fc(common,connect_pg_net_script)] && [file exists $fc(common,connect_pg_net_script)]} {
        source -e $fc(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # FC-RM: check_routes
    redirect -file $::REPORTS_DIR/check_routes { check_routes }

    handle_info "Post-route tasks completed"
# ==============================================================================
# flow_proc: setup_starrc_extraction
# FC-RM: set_starrc_in_design for in-design parasitic extraction
# ==============================================================================
flow_proc setup_starrc_extraction {
    handle_info "Setting up StarRC in-design extraction..."
    global synth_pnr

    # FC-RM: StarRC config file for in-design extraction
    if {[info exists fc(common,route_opt,starrc_config)] && $fc(common,route_opt,starrc_config) ne ""} {
        if {[file exists $fc(common,route_opt,starrc_config)]} {
            set config_file [file normalize $fc(common,route_opt,starrc_config)]
            set cmd "set_starrc_in_design -config $config_file"
            if {[info exists fc(common,route_opt,starrc_options)] && $fc(common,route_opt,starrc_options) ne ""} {
                append cmd " $fc(common,route_opt,starrc_options)"
            }
            handle_info "Running: $cmd"
            eval $cmd
            save_block
        } else {
            handle_warning "StarRC config not found: $fc(common,route_opt,starrc_config)"
        }
    }

    handle_info "StarRC extraction setup completed"
# ==============================================================================
# flow_proc: setup_virtual_metal_fill
# FC-RM: set_extraction_options -virtual_metalfill_parameter_file
# ==============================================================================
flow_proc setup_virtual_metal_fill {
    handle_info "Setting up virtual metal fill..."
    global synth_pnr

    # FC-RM: VMF parameter file
    if {[info exists fc(common,route_opt,vmf_parameter_file)] && $fc(common,route_opt,vmf_parameter_file) ne ""} {
        if {[file exists $fc(common,route_opt,vmf_parameter_file)]} {
            set vmf_file [file normalize $fc(common,route_opt,vmf_parameter_file)]
            set cmd "set_extraction_options -virtual_metalfill_parameter_file $vmf_file"
            # FC-RM: Advanced VMF mode
            if {[info exists fc(common,route_opt,enable_advanced_vmf)] && $fc(common,route_opt,enable_advanced_vmf)} {
                set_app_options -name extract.fusion_starrc_vmf -value advanced
            }
            handle_info "Running: $cmd"
            eval $cmd
        } else {
            handle_warning "VMF parameter file not found: $fc(common,route_opt,vmf_parameter_file)"
        }
    }

    handle_info "Virtual metal fill setup completed"
# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global synth_pnr

    set chip_type [expr {[info exists fc(common,chip_type)] ? $fc(common,chip_type) : "flat"}]

    if {$chip_type eq "hierarchical"} {
        set hier_level "bottom"
        if {[info exists fc(common,physical_hierarchy_level)]} { set hier_level $fc(common,physical_hierarchy_level) }
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
    handle_info "Saving route_auto design..."
    global synth_pnr flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists fc(common,output,block_labeling)] && $fc(common,output,block_labeling)} {
        save_block -as ${design_name}/route_auto
        handle_info "Block saved: ${design_name}/route_auto"
    }

    set_svf -off
    handle_info "Route design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: Timing settings for routed designs (AWP, CCS receiver, SI),
#         report_qor, report_timing, write_qor_data, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating route reports..."
    global synth_pnr

    set max_paths [expr {[info exists fc(common,analysis,max_paths)] ? $fc(common,analysis,max_paths) : 100}]

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
    redirect -file $::REPORTS_DIR/report_routing.rpt { report_routing_rules -verbose }
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

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Route reports generated in: $::REPORTS_DIR"
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
set _stage_override "$run_dir/setup/override_setup.route.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
