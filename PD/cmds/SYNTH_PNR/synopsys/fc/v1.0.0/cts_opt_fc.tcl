#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR cts_opt (clock_opt_opto) - Synopsys Fusion Compiler
# FC-RM: clock_opt_opto.tcl -- Post-CTS optimization: final_opto with GRE, IRDP
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/SYNTH_PNR/cts_opt1/run/config.tcl"
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
handle_info "Starting SYNTH_PNR clock_opt_opto (FC-RM Y-2026.03 aligned)..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/SYNTH_PNR/cts_opt1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from clock_opt_cts, link_block, hier abstracts
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for clock_opt_opto..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists synth_pnr(design_lib_name)] ? $synth_pnr(design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    copy_block -from ${design_name}/clock_opt_cts -to ${design_name}/clock_opt_opto
    current_block ${design_name}/clock_opt_opto
    link_block

    # FC-RM: Hierarchical — swap abstracts
    set chip_type [expr {[info exists synth_pnr(chip_type)] ? $synth_pnr(chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        if {[info exists synth_pnr(block_abstract_for_cts_opt)] && $synth_pnr(block_abstract_for_cts_opt) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $synth_pnr(block_abstract_for_cts_opt) 0] \
                -view [lindex $synth_pnr(block_abstract_for_cts_opt) 1]
            report_abstracts
        }
        if {[info exists synth_pnr(promote_clock_balance_points)] && $synth_pnr(promote_clock_balance_points)} {
            if {[info exists synth_pnr(promote_abstract_clock_data_file)] && [file exists $synth_pnr(promote_abstract_clock_data_file)]} {
                source -e $synth_pnr(promote_abstract_clock_data_file)
            }
        }
    }

    handle_info "Design loaded: ${design_name}/clock_opt_opto"
}

# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status, propagate clocks for newly activated scenarios
# ==============================================================================
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for clock_opt_opto..."
    global synth_pnr

    set scenarios_changed false

    # Priority: synth_pnr override > mmmc_config get_node_scenarios("cts")
    if {[info exists synth_pnr(clock_opt_opto,active_scenarios)] && $synth_pnr(clock_opt_opto,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $synth_pnr(clock_opt_opto,active_scenarios)
        set scenarios_changed true
        handle_info "Active scenarios (user override): $synth_pnr(clock_opt_opto,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "cts_opt" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            set scenarios_changed true
            handle_info "Active scenarios (mmmc_config/cts_opt): $node_scenarios"
        }
    }

    # FC-RM: MCMM adjustment file
    if {[info exists synth_pnr(mcmm_adjustment_file)] && [file exists $synth_pnr(mcmm_adjustment_file)]} {
        source -e $synth_pnr(mcmm_adjustment_file)
        set scenarios_changed true
    }

    # FC-RM: Propagate clocks for newly activated scenarios
    if {$scenarios_changed} {
        handle_info "Propagating clocks for newly activated scenarios..."
        synthesize_clock_trees -propagate_only
        compute_clock_latency -verbose
    }

    handle_info "Active scenarios configured"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage post_cts_opto, GRE focused scenario,
#         instance prefixes, disable power scenarios
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for post-CTS opto..."
    global synth_pnr

    if {[info exists synth_pnr(compile,qor_version)] && $synth_pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $synth_pnr(compile,qor_version)
    }

    set cmd "set_qor_strategy -stage post_cts_opto"
    set metric "timing"
    set mode "balanced"
    if {[info exists synth_pnr(compile,qor_metric)]} { set metric $synth_pnr(compile,qor_metric) }
    if {[info exists synth_pnr(compile,qor_mode)]}   { set mode $synth_pnr(compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {[info exists synth_pnr(compile,reduced_effort)] && $synth_pnr(compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: GRE - Route focused scenario
    if {[info exists synth_pnr(route,focused_scenario)] && $synth_pnr(route,focused_scenario) ne ""} {
        set_app_options -name route.common.focus_scenario -value $synth_pnr(route,focused_scenario)
        handle_info "Route focused scenario: $synth_pnr(route,focused_scenario)"
    }

    # FC-RM: Instance prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_opto_
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_opto_cts_

    # FC-RM: Disable power scenarios
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
# flow_proc: configure_opto
# FC-RM: IRDP, lib_cell_purpose, sidefile, non-persistent, multi-Vt,
#         pre-opto reports, sub-block timing disable
# ==============================================================================
flow_proc configure_opto {
    handle_info "Configuring clock_opt_opto settings..."
    global synth_pnr tech

    # FC-RM: IR-driven placement (IRDP)
    if {[info exists synth_pnr(compile,enable_irdp)] && $synth_pnr(compile,enable_irdp)} {
        if {[info exists synth_pnr(irdp_config_file)] && [file exists $synth_pnr(irdp_config_file)]} {
            handle_info "Sourcing IRDP config: $synth_pnr(irdp_config_file)"
            source -e $synth_pnr(irdp_config_file)

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
        }
    }

    # FC-RM: Lib cell purpose
    if {[info exists synth_pnr(lib_cell_purpose_file)] && [file exists $synth_pnr(lib_cell_purpose_file)]} {
        source -e $synth_pnr(lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source -e $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS opto sidefile
    if {[info exists synth_pnr(cts_opt_sidefile)] && [file exists $synth_pnr(cts_opt_sidefile)]} {
        source -e $synth_pnr(cts_opt_sidefile)
    }

    # FC-RM: Non-persistent settings
    if {[info exists synth_pnr(non_persistent_script)] && [file exists $synth_pnr(non_persistent_script)]} {
        source -e $synth_pnr(non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists synth_pnr(multi_vt_constraint_file)] && [file exists $synth_pnr(multi_vt_constraint_file)]} {
        source -e $synth_pnr(multi_vt_constraint_file)
    }

    # FC-RM: User pre-opto script
    if {[info exists synth_pnr(cts_opt_pre_script)] && [file exists $synth_pnr(cts_opt_pre_script)]} {
        source -e $synth_pnr(cts_opt_pre_script)
    }

    # FC-RM: Pre-opto reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }

    # FC-RM: Disable sub-block timing for hierarchical
    set chip_type [expr {[info exists synth_pnr(chip_type)] ? $synth_pnr(chip_type) : "flat"}]
    if {$chip_type eq "hierarchical"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Clock_opt_opto configuration completed"
}

# ==============================================================================
# flow_proc: run_clock_opt_opto
# FC-RM: clock_opt -from final_opto -to final_opto
# ==============================================================================
flow_proc run_clock_opt_opto {
    handle_info "Running clock_opt final_opto..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_clock_opt_opto.svf

    # FC-RM: clock_opt -from final_opto -to final_opto
    handle_info "Running clock_opt -from final_opto -to final_opto"
    clock_opt -from final_opto -to final_opto

    handle_info "clock_opt final_opto completed"
}

# ==============================================================================
# flow_proc: post_opto
# FC-RM: User post-script, connect_pg_net, re-enable power scenarios
# ==============================================================================
flow_proc post_opto {
    handle_info "Running post-opto tasks..."
    global synth_pnr

    # FC-RM: User post-opto script
    if {[info exists synth_pnr(cts_opt_post_script)] && [file exists $synth_pnr(cts_opt_post_script)]} {
        source -e $synth_pnr(cts_opt_post_script)
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

    handle_info "Post-opto tasks completed"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical
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
    handle_info "Saving clock_opt_opto design..."
    global synth_pnr flow

    set design_name [expr {[info exists synth_pnr(design_name)] ? $synth_pnr(design_name) : $flow(design_name)}]

    save_block
    if {[info exists synth_pnr(output,block_labeling)] && $synth_pnr(output,block_labeling)} {
        save_block -as ${design_name}/clock_opt_opto
        handle_info "Block saved: ${design_name}/clock_opt_opto"
    }

    set_svf -off
    handle_info "CTS opto design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_clock_qor, write_qor_data, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating clock_opt_opto reports..."
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

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Clock_opt_opto reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# ==============================================================================
set _setup_file "$run_dir/work/SYNTH_PNR/cts_opt1/run/setup.tcl"
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

flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
