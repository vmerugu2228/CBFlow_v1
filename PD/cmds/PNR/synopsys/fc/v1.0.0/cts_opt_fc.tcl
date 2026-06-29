#!/usr/bin/env tclsh
# CBFlow shared (PNR + SYNTH_PNR) — synopsys/fc — cts_opt (clock_opt_opto) - Synopsys Fusion Compiler
# FC-RM: clock_opt_opto.tcl -- Post-CTS optimization: final_opto with GRE, IRDP
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

if {![info exists ::flow_type] || $::flow_type eq ""} { set ::flow_type $::env(CBFLOW_FLOW_TYPE) }
set FLOW_TYPE $::flow_type
set STAGE_NAME "cts_opt"
set NODE_NAME "cts_opt1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Active flow config array — pnr() or synth_pnr() depending on the run.
# Use $cfg(...) / [info exists cfg(...)] throughout the file body.
upvar #0 [string tolower $::flow_type] cfg

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from clock_opt_cts, link_block, hier abstracts
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for clock_opt_opto..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$cfg(common,design_lib_name) ne "" ? $cfg(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    copy_block -from ${design_name}/clock_opt_cts -to ${design_name}/clock_opt_opto
    current_block ${design_name}/clock_opt_opto
    link_block

    # FC-RM: Hierarchical — swap abstracts
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {[info exists cfg(common,block_abstract_for_cts_opt)] && $cfg(common,block_abstract_for_cts_opt) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $cfg(common,block_abstract_for_cts_opt) 0] \
                -view [lindex $cfg(common,block_abstract_for_cts_opt) 1]
            report_abstracts
        }
        if {[info exists cfg(common,promote_clock_balance_points)] && $cfg(common,promote_clock_balance_points) ne "" && $cfg(common,promote_clock_balance_points)} {
            if {[info exists cfg(common,promote_abstract_clock_data_file)] && $cfg(common,promote_abstract_clock_data_file) ne "" && [file exists $cfg(common,promote_abstract_clock_data_file)]} {
                source $cfg(common,promote_abstract_clock_data_file)
            }
        }
    }

    handle_info "Design loaded: ${design_name}/clock_opt_opto"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status, propagate clocks for newly activated scenarios
# ==============================================================================
}
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for clock_opt_opto..."
    global cfg

    set scenarios_changed false

    # Priority: user override > mmmc_config get_node_scenarios("cts")
    if {[info exists cfg(cts_opt,active_scenarios)] && $cfg(cts_opt,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $cfg(cts_opt,active_scenarios)
        set scenarios_changed true
        handle_info "Active scenarios (user override): $cfg(cts_opt,active_scenarios)"
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
    if {[info exists cfg(common,mcmm_adjustment_file)] && $cfg(common,mcmm_adjustment_file) ne "" && [file exists $cfg(common,mcmm_adjustment_file)]} {
        source $cfg(common,mcmm_adjustment_file)
        set scenarios_changed true
    }

    # FC-RM: Propagate clocks for newly activated scenarios
    if {$scenarios_changed} {
        handle_info "Propagating clocks for newly activated scenarios..."
        synthesize_clock_trees -propagate_only
        compute_clock_latency -verbose
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage post_cts_opto, GRE focused scenario,
#         instance prefixes, disable power scenarios
# ==============================================================================
}
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for post-CTS opto..."
    global cfg

    if {[info exists cfg(common,compile,qor_version)] && $cfg(common,compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $cfg(common,compile,qor_version)
    }

    set cmd "set_qor_strategy -stage post_cts_opto"
    set metric "timing"
    set mode "balanced"
    if {[info exists cfg(common,compile,qor_metric)] && $cfg(common,compile,qor_metric) ne ""} { set metric $cfg(common,compile,qor_metric) }
    if {[info exists cfg(common,compile,qor_mode)] && $cfg(common,compile,qor_mode) ne ""}   { set mode $cfg(common,compile,qor_mode) }
    lappend cmd -metric $metric -mode $mode

    if {[info exists cfg(common,compile,reduced_effort)] && $cfg(common,compile,reduced_effort) ne "" && $cfg(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: GRE - Route focused scenario
    if {[info exists cfg(common,route,focused_scenario)] && $cfg(common,route,focused_scenario) ne ""} {
        set_app_options -name route.common.focus_scenario -value $cfg(common,route,focused_scenario)
        handle_info "Route focused scenario: $cfg(common,route,focused_scenario)"
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
# ==============================================================================
# flow_proc: configure_opto
# FC-RM: IRDP, lib_cell_purpose, sidefile, non-persistent, multi-Vt,
#         pre-opto reports, sub-block timing disable
# ==============================================================================
}
flow_proc configure_opto {
    handle_info "Configuring clock_opt_opto settings..."
    global flow cfg tech
    apply_vt_dont_use

    # FC-RM: IR-driven placement (IRDP)
    if {[info exists cfg(synthesis,compile,enable_irdp)] && $cfg(synthesis,compile,enable_irdp) ne "" && $cfg(synthesis,compile,enable_irdp)} {
        if {[info exists cfg(common,irdp_config_file)] && $cfg(common,irdp_config_file) ne "" && [file exists $cfg(common,irdp_config_file)]} {
            handle_info "Sourcing IRDP config: $cfg(common,irdp_config_file)"
            source $cfg(common,irdp_config_file)

        }
    }

    # FC-RM: Lib cell purpose
    if {[info exists cfg(common,lib_cell_purpose_file)] && $cfg(common,lib_cell_purpose_file) ne "" && [file exists $cfg(common,lib_cell_purpose_file)]} {
        source $cfg(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS opto sidefile
    if {[info exists cfg(cts_opt,cts_opt_sidefile)] && $cfg(cts_opt,cts_opt_sidefile) ne "" && [file exists $cfg(cts_opt,cts_opt_sidefile)]} {
        source $cfg(cts_opt,cts_opt_sidefile)
    }

    # FC-RM: Non-persistent settings
    if {[info exists cfg(common,non_persistent_script)] && $cfg(common,non_persistent_script) ne "" && [file exists $cfg(common,non_persistent_script)]} {
        source $cfg(common,non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists cfg(common,multi_vt_constraint_file)] && $cfg(common,multi_vt_constraint_file) ne "" && [file exists $cfg(common,multi_vt_constraint_file)]} {
        source $cfg(common,multi_vt_constraint_file)
    }

    # FC-RM: User pre-opto script
    if {[info exists cfg(cts_opt,cts_opt_pre_script)] && $cfg(cts_opt,cts_opt_pre_script) ne "" && [file exists $cfg(cts_opt,cts_opt_pre_script)]} {
        source $cfg(cts_opt,cts_opt_pre_script)
    }

    # FC-RM: Pre-opto reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }

    # FC-RM: Disable sub-block timing for hierarchical
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Clock_opt_opto configuration completed"
# ==============================================================================
# flow_proc: run_clock_opt_opto
# FC-RM: clock_opt -from final_opto -to final_opto
# ==============================================================================
}
flow_proc run_clock_opt_opto {
    handle_info "Running clock_opt final_opto..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_clock_opt_opto.svf

    # FC-RM: clock_opt -from final_opto -to final_opto
    handle_info "Running clock_opt -from final_opto -to final_opto"
    clock_opt -from final_opto -to final_opto

    handle_info "clock_opt final_opto completed"
}

# ==============================================================================
# flow_proc: redhawk_rail_analysis
# Optional RedHawk-SC IR-driven rail analysis between opto runs. Gated on
# <flow>(cts_opt,redhawk_enable) OR <flow>(common,redhawk_enable) == "true".
# Stages cfg(cts_opt,redhawk,*) → ::REDHAWK_* globals, then sources the
# standalone redhawk_fc.tcl recipe with stage="cts_opt". Default OFF.
# ==============================================================================
flow_proc redhawk_rail_analysis {
    if {![redhawk_enabled cts_opt]} {
        handle_info "RedHawk-SC disabled (cts_opt,redhawk_enable != true) — skipping"
        return
    }
    handle_info "RedHawk-SC enabled — staging globals for cts_opt"
    redhawk_stage_globals cts_opt
    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/redhawk_fc.tcl"
    if {![file exists $_recipe]} {
        set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/redhawk_fc.tcl"
    }
    handle_info "Sourcing RedHawk recipe: $_recipe"
    source $_recipe
}

# ==============================================================================
# flow_proc: post_opto
# FC-RM: User post-script, connect_pg_net, re-enable power scenarios
# ==============================================================================
flow_proc post_opto {
    handle_info "Running post-opto tasks..."
    global flow cfg

    # FC-RM: User post-opto script
    if {[info exists cfg(cts_opt,cts_opt_post_script)] && $cfg(cts_opt,cts_opt_post_script) ne "" && [file exists $cfg(cts_opt,cts_opt_post_script)]} {
        source $cfg(cts_opt,cts_opt_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists cfg(common,connect_pg_net_script)] && $cfg(common,connect_pg_net_script) ne "" && [file exists $cfg(common,connect_pg_net_script)]} {
        source $cfg(common,connect_pg_net_script)
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
# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame for hierarchical
# ==============================================================================
}
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global flow cfg

    set _run_type $flow(run_type)

    if {$_run_type eq "hier"} {
        set hier_level "bottom"
        if {[info exists cfg(common,physical_hierarchy_level)] && $cfg(common,physical_hierarchy_level) ne ""} { set hier_level $cfg(common,physical_hierarchy_level) }
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
    handle_info "Saving clock_opt_opto design..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists cfg(common,output,block_labeling)] && $cfg(common,output,block_labeling) ne "" && $cfg(common,output,block_labeling)} {
        save_block -as ${design_name}/clock_opt_opto
        handle_info "Block saved: ${design_name}/clock_opt_opto"
    }

    set_svf -off
    handle_info "CTS opto design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_clock_qor, write_qor_data, run_end
# ==============================================================================
}
flow_proc generate_reports {
    handle_info "Generating clock_opt_opto reports..."
    global cfg

    set max_paths [expr {$cfg(common,analysis,max_paths) ne "" ? $cfg(common,analysis,max_paths) : 100}]

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
# ==============================================================================
# ==============================================================================
}
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
