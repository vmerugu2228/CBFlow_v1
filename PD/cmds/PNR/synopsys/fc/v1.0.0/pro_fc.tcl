#!/usr/bin/env tclsh
# CBFlow shared (PNR + SYNTH_PNR) — synopsys/fc — pro (route_opt) - Synopsys Fusion Compiler
# FC-RM: route_opt.tcl -- Post-route optimization: hyper_route_opt with PBA,
#         StarRC extraction, VMF, incremental DRC fix, redundant vias
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

if {![info exists ::flow_type] || $::flow_type eq ""} { set ::flow_type $::env(CBFLOW_FLOW_TYPE) }
set FLOW_TYPE $::flow_type
set STAGE_NAME "pro"
set NODE_NAME "pro1"

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
# FC-RM: open_lib, copy_block from route_auto, link_block, hier abstracts
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for route_opt..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$cfg(common,design_lib_name) ne "" ? $cfg(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    set _from_block [cbflow_resolve_head_block "route_auto" {route cts_opt cts place init_design}]
    handle_info "load_design: copying from ${design_name}/${_from_block} (head-block manifest)"
    copy_block -from ${design_name}/${_from_block} -to ${design_name}/route_opt
    current_block ${design_name}/route_opt
    link_block

    # FC-RM: Hierarchical — swap abstracts
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {[info exists cfg(pro,block_abstract)] && $cfg(pro,block_abstract) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $cfg(pro,block_abstract) 0] \
                -view [lindex $cfg(pro,block_abstract) 1]
            report_abstracts
        }
    }

    handle_info "Design loaded: ${design_name}/route_opt"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for route_opt (post_route scenarios)
# ==============================================================================
}
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for route_opt..."
    global cfg

    # Priority: user override > mmmc_config get_node_scenarios("post_route")
    if {[info exists cfg(pro,opt_active_scenarios)] && $cfg(pro,opt_active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $cfg(pro,opt_active_scenarios)
        handle_info "Active scenarios (user override): $cfg(pro,opt_active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "post_route" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/post_route): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file
    if {[info exists cfg(common,mcmm_adjustment_file)] && $cfg(common,mcmm_adjustment_file) ne "" && [file exists $cfg(common,mcmm_adjustment_file)]} {
        source $cfg(common,mcmm_adjustment_file)
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage post_route, instance prefixes,
#         disable dynamic power for optimization
# ==============================================================================
}
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for route_opt..."
    global cfg

    if {[info exists cfg(common,compile,qor_version)] && $cfg(common,compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $cfg(common,compile,qor_version)
    }

    set cmd "set_qor_strategy -stage post_route"
    set metric [expr {$cfg(common,compile,qor_metric) ne "" ? $cfg(common,compile,qor_metric) : "timing"}]
    set mode [expr {$cfg(common,compile,qor_mode) ne "" ? $cfg(common,compile,qor_mode) : "balanced"}]
    lappend cmd -metric $metric -mode $mode

    if {[info exists cfg(common,compile,reduced_effort)] && $cfg(common,compile,reduced_effort) ne "" && $cfg(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: Instance prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value route_opt_
    set_app_options -name cts.common.user_instance_name_prefix -value route_opt_cts_

    # FC-RM: Disable dynamic power for optimization
    if {$metric eq "leakage_power" || $metric eq "timing"} {
        set ::rm_dynamic_scenarios [get_object_name [get_scenarios -filter "active==true&&dynamic_power==true"]]
        if {[llength $::rm_dynamic_scenarios] > 0} {
            handle_info "Disabling dynamic power analysis for optimization"
            set_scenario_status -dynamic_power false [get_scenarios $::rm_dynamic_scenarios]
        }
    }

    handle_info "QoR strategy set: metric=$metric, mode=$mode"
# ==============================================================================
# flow_proc: configure_route_opt
# FC-RM: Extraction mode (StarRC/native), StarRC config, VMF setup,
#         lib_cell_purpose, sidefile, non-persistent, multi-Vt, pre-reports
# ==============================================================================
}
flow_proc configure_route_opt {
    handle_info "Configuring route_opt settings..."
    global flow cfg tech
    apply_vt_dont_use

    # FC-RM: Lib cell purpose
    if {[info exists cfg(common,lib_cell_purpose_file)] && $cfg(common,lib_cell_purpose_file) ne "" && [file exists $cfg(common,lib_cell_purpose_file)]} {
        source $cfg(common,lib_cell_purpose_file)
    }

    # FC-RM: Non-persistent settings
    if {[info exists cfg(common,non_persistent_script)] && $cfg(common,non_persistent_script) ne "" && [file exists $cfg(common,non_persistent_script)]} {
        source $cfg(common,non_persistent_script)
    }

    # FC-RM: Multi-Vt constraint
    if {[info exists cfg(common,multi_vt_constraint_file)] && $cfg(common,multi_vt_constraint_file) ne "" && [file exists $cfg(common,multi_vt_constraint_file)]} {
        source $cfg(common,multi_vt_constraint_file)
    }

    # FC-RM: Route_opt sidefile
    if {[info exists cfg(pro,route_opt_sidefile)] && [file exists $cfg(pro,route_opt_sidefile)]} {
        source $cfg(pro,route_opt_sidefile)
    }

    # FC-RM: Set extraction mode (fusion_adv, in_design, or none)
    set extraction_mode [expr {[info exists cfg(pro,route_opt,extraction_mode)] && $cfg(pro,route_opt,extraction_mode) ne "" ? $cfg(pro,route_opt,extraction_mode) : "fusion_adv"}]
    set_app_options -name extract.starrc_mode -value $extraction_mode
    handle_info "Extraction mode: $extraction_mode"

    # FC-RM: StarRC in-design config
    if {[info exists cfg(common,route_opt,starrc_config)] && $cfg(common,route_opt,starrc_config) ne ""} {
        if {[file exists $cfg(common,route_opt,starrc_config)]} {
            set config_file [file normalize $cfg(common,route_opt,starrc_config)]
            set cmd "set_starrc_in_design -config $config_file"
            if {[info exists cfg(common,route_opt,starrc_options)] && $cfg(common,route_opt,starrc_options) ne ""} {
                append cmd " $cfg(common,route_opt,starrc_options)"
            }
            handle_info "StarRC: $cmd"
            eval $cmd
        }
    }

    # FC-RM: Virtual Metal Fill
    if {[info exists cfg(common,route_opt,vmf_parameter_file)] && $cfg(common,route_opt,vmf_parameter_file) ne ""} {
        if {[file exists $cfg(common,route_opt,vmf_parameter_file)]} {
            set vmf_file [file normalize $cfg(common,route_opt,vmf_parameter_file)]
            if {[info exists cfg(common,route_opt,enable_advanced_vmf)] && $cfg(common,route_opt,enable_advanced_vmf) ne "" && $cfg(common,route_opt,enable_advanced_vmf)} {
                set_app_options -name extract.fusion_starrc_vmf -value advanced
            }
            set_extraction_options -virtual_metalfill_parameter_file $vmf_file
            handle_info "VMF parameter file: $vmf_file"
        }
    }

    # FC-RM: User pre-route_opt script
    if {[info exists cfg(pro,route_opt_pre_script)] && [file exists $cfg(pro,route_opt_pre_script)]} {
        source $cfg(pro,route_opt_pre_script)
    }

    # FC-RM: Pre-reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }

    # FC-RM: Disable sub-block timing for hierarchical
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Route_opt configuration completed"
# ==============================================================================
# flow_proc: run_route_opt
# FC-RM: PBA mode, compute_clock_latency, hyper_route_opt (with redundant
#         vias in post_eco proc), IRD-CCD
# ==============================================================================
}
flow_proc run_route_opt {
    handle_info "Running route_opt (hyper_route_opt)..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_route_opt.svf

    # FC-RM: Track DRC before optimization
    catch {
        if {[get_drc_error_data -quiet zroute.err] == ""} { open_drc_error_data zroute.err }
        set ::rm_drc_before [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]
    }

    # FC-RM: compute_clock_latency before route_opt
    compute_clock_latency

    # FC-RM: PBA optimization mode
    set pba_mode ""
    if {[info exists cfg(pro,route_opt,pba_mode)] && $cfg(pro,route_opt,pba_mode) ne ""} { set pba_mode $cfg(pro,route_opt,pba_mode) }
    if {$pba_mode ne ""} {
        handle_info "Setting PBA optimization mode: $pba_mode"
        set_app_options -name time.pba_optimization_mode -value $pba_mode
        if {$pba_mode eq "exhaustive"} {
            set_app_options -name time.pba_exhaustive_endpoint_path_limit -value 16
        }
    }

    # FC-RM: IRD-CCD (IR-drop aware concurrent clock-data optimization)
    if {[info exists cfg(pro,route_opt,enable_irdccd)] && $cfg(pro,route_opt,enable_irdccd) ne "" && [string is true -strict $cfg(pro,route_opt,enable_irdccd)]} {
        if {[info exists cfg(common,irdccd_config_file)] && $cfg(common,irdccd_config_file) ne "" && [file exists $cfg(common,irdccd_config_file)]} {
            handle_info "Sourcing IRD-CCD config: $cfg(common,irdccd_config_file)"
            source $cfg(common,irdccd_config_file)

        }
    }

    # FC-RM: hyper_route_opt (includes route_opt phases 1-3)
    # The snps_hyper_route_opt_post_eco proc runs between phase2 and phase3
    if {[info exists cfg(pro,route_opt,enable_hyper)] && $cfg(pro,route_opt,enable_hyper) ne "" && [string is true -strict $cfg(pro,route_opt,enable_hyper)]} {
        # Define post_eco proc for redundant vias during hyper_route_opt
        if {[info exists cfg(pro,route_opt,redundant_via)] && $cfg(pro,route_opt,redundant_via) ne "" && [string is true -strict $cfg(pro,route_opt,redundant_via)]} {
            proc snps_hyper_route_opt_post_eco {} {
                handle_info "hyper_route_opt post_eco: adding redundant vias"
                add_redundant_vias -timing_preserve_setup_slack_threshold 0
            }
        }
        handle_info "Running hyper_route_opt"
        hyper_route_opt
    } else {
        # Standard route_opt
        handle_info "Running route_opt"
        route_opt
    }

    handle_info "route_opt completed"
}

# ==============================================================================
# flow_proc: redhawk_rail_analysis
# Optional RedHawk-SC IR-driven rail analysis after route_opt. Gated on
# <flow>(pro,redhawk_enable) OR <flow>(common,redhawk_enable) == "true".
# Stages cfg(pro,redhawk,*) → ::REDHAWK_* globals, then sources the
# standalone redhawk_fc.tcl recipe with stage="pro". Default OFF.
# ==============================================================================
flow_proc redhawk_rail_analysis {
    if {![redhawk_enabled pro]} {
        handle_info "RedHawk-SC disabled (pro,redhawk_enable != true) — skipping"
        return
    }
    handle_info "RedHawk-SC enabled — staging globals for pro"
    redhawk_stage_globals pro
    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/redhawk_fc.tcl"
    if {![file exists $_recipe]} {
        set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/redhawk_fc.tcl"
    }
    handle_info "Sourcing RedHawk recipe: $_recipe"
    source $_recipe
}

# ==============================================================================
# flow_proc: post_route_opt
# FC-RM: Post-route_opt redundant vias, incremental route_detail for DRC fix,
#         FuSa safety taps, user post-script, connect_pg_net, check_routes,
#         re-enable power
# ==============================================================================
flow_proc post_route_opt {
    handle_info "Running post-route_opt tasks..."
    global flow cfg

    # FC-RM: Post route_opt redundant via insertion (for DRC-sensitive nodes)
    if {[info exists cfg(pro,route_opt,post_redundant_via)] && $cfg(pro,route_opt,post_redundant_via) ne "" && [string is true -strict $cfg(pro,route_opt,post_redundant_via)]} {
        handle_info "Adding post-route_opt redundant vias"
        add_redundant_vias
    }

    # FC-RM: Incremental route_detail for fixing routing DRCs
    catch {
        if {[get_drc_error_data -quiet zroute.err] == ""} { open_drc_error_data zroute.err }
        set rm_drc_after [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]
        if {[info exists ::rm_drc_before] && $rm_drc_after > $::rm_drc_before} {
            handle_info "DRC increased ($::rm_drc_before -> $rm_drc_after), running incremental route_detail"
            route_detail -incremental true -initial_drc_from_input true
        }
    }

    # FC-RM: FuSa safety tap cells
    if {[info exists cfg(common,enable_fusa)] && $cfg(common,enable_fusa) ne "" && $cfg(common,enable_fusa)} {
        catch {
            if {[sizeof_collection [get_safety_register_groups -quiet]]} {
                create_safety_tap_cells
            }
        }
    }

    # FC-RM: User post-route_opt script
    if {[info exists cfg(pro,route_opt_post_script)] && [file exists $cfg(pro,route_opt_post_script)]} {
        source $cfg(pro,route_opt_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists cfg(common,connect_pg_net_script)] && $cfg(common,connect_pg_net_script) ne "" && [file exists $cfg(common,connect_pg_net_script)]} {
        source $cfg(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # FC-RM: check_routes
    redirect -file $::REPORTS_DIR/check_routes { check_routes }

    # FC-RM: Re-enable dynamic power
    if {[info exists ::rm_dynamic_scenarios] && [llength $::rm_dynamic_scenarios] > 0} {
        handle_info "Re-enabling dynamic power analysis"
        set_scenario_status -dynamic_power true [get_scenarios $::rm_dynamic_scenarios]
    }

    handle_info "Post-route_opt tasks completed"
# ==============================================================================
# flow_proc: run_endpoint_opt
# FC-RM: endpoint_opt.tcl -- PBA-CCD targeted optimization on worst endpoints
# Enabled by <flow>(pro,route_opt,enable_endpoint_opt) — flow-agnostic cfg key
# ==============================================================================
}
flow_proc run_endpoint_opt {
    handle_info "Checking endpoint optimization..."
    global cfg flow

    # Only run if enabled in config
    if {![info exists cfg(pro,route_opt,enable_endpoint_opt)] || (![info exists cfg(pro,route_opt,enable_endpoint_opt)] || ![string is true -strict $cfg(pro,route_opt,enable_endpoint_opt)])} {
        handle_info "Endpoint optimization disabled (route_opt,enable_endpoint_opt=false)"
        return
    }

    handle_info "Running PBA-CCD targeted endpoint optimization..."
    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    # FC-RM: Track DRC before endpoint_opt
    catch {
        if {[get_drc_error_data -quiet zroute.err] == ""} { open_drc_error_data zroute.err }
        set ::rm_eopt_drc_before [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]
    }

    # FC-RM: Build targeted_ep_ropt_pba_ccd arguments
    set auto_metric "false"
    if {[info exists cfg(pro,endpoint_opt,auto_metric)] && $cfg(pro,endpoint_opt,auto_metric) ne ""} { set auto_metric $cfg(pro,endpoint_opt,auto_metric) }

    if {$auto_metric ne "false"} {
        # FC-RM: Auto mode (tool selects endpoints)
        set eopt_args "-auto $auto_metric"
    } else {
        # FC-RM: Manual mode (user controls endpoint selection)
        set max_paths 100
        set slack_threshold 0.0
        set target_scenarios ""
        if {[info exists cfg(pro,endpoint_opt,max_paths)] && $cfg(pro,endpoint_opt,max_paths) ne ""} { set max_paths $cfg(pro,endpoint_opt,max_paths) }
        if {[info exists cfg(pro,endpoint_opt,slack_threshold)] && $cfg(pro,endpoint_opt,slack_threshold) ne ""} { set slack_threshold $cfg(pro,endpoint_opt,slack_threshold) }
        if {[info exists cfg(pro,endpoint_opt,target_scenarios)] && $cfg(pro,endpoint_opt,target_scenarios) ne ""} { set target_scenarios $cfg(pro,endpoint_opt,target_scenarios) }

        set eopt_args "-max_paths $max_paths -slack_lesser_than $slack_threshold"
        if {$target_scenarios ne ""} {
            append eopt_args " -scenarios \[list $target_scenarios\]"
        }
        # FC-RM: Optional path group filter
        if {[info exists cfg(pro,endpoint_opt,path_group_filter)] && $cfg(pro,endpoint_opt,path_group_filter) ne ""} {
            append eopt_args " -path_group_filter \[list $cfg(pro,endpoint_opt,path_group_filter)\]"
        }
    }

    # FC-RM: Iterative endpoint optimization
    set loop_count 1
    if {[info exists cfg(pro,endpoint_opt,loop_count)] && $cfg(pro,endpoint_opt,loop_count) ne ""} { set loop_count $cfg(pro,endpoint_opt,loop_count) }

    for {set iter 1} {$iter <= $loop_count} {incr iter} {
        handle_info "Endpoint opt pass $iter/$loop_count: targeted_ep_ropt_pba_ccd $eopt_args"
        eval targeted_ep_ropt_pba_ccd $eopt_args

        if {$loop_count > 1} {
            save_block -as ${design_name}/endpoint_opt_pass${iter}
            report_qor -summary
        }
    }

    # FC-RM: Incremental route_detail after endpoint_opt
    catch {
        if {[get_drc_error_data -quiet zroute.err] == ""} { open_drc_error_data zroute.err }
        set rm_eopt_drc_after [sizeof_collection [get_drc_errors -quiet -error_data zroute.err]]
        if {[info exists ::rm_eopt_drc_before] && $rm_eopt_drc_after > $::rm_eopt_drc_before} {
            handle_info "DRC increased after endpoint_opt, running incremental route_detail"
            route_detail -incremental true -initial_drc_from_input true
        }
    }

    # FC-RM: connect_pg_net and check_routes after endpoint_opt
    connect_pg_net
    redirect -file $::REPORTS_DIR/check_routes.post_endpoint_opt { check_routes }

    handle_info "Endpoint optimization completed ($loop_count passes)"
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
        set hier_level [expr {$cfg(common,physical_hierarchy_level) ne "" ? $cfg(common,physical_hierarchy_level) : "bottom"}]
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
    handle_info "Saving route_opt design..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists cfg(common,output,block_labeling)] && $cfg(common,output,block_labeling) ne "" && $cfg(common,output,block_labeling)} {
        save_block -as ${design_name}/route_opt
        handle_info "Block saved: ${design_name}/route_opt"
    }
    cbflow_record_block_state $::STAGE_NAME "route_opt" $::NODE_NAME

    set_svf -off
    handle_info "Route_opt design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing (with AWP/CCS), report_power,
#         write_qor_data, run_end
# ==============================================================================
}
flow_proc generate_reports {
    handle_info "Generating route_opt reports..."
    global cfg

    set max_paths [expr {$cfg(common,analysis,max_paths) ne "" ? $cfg(common,analysis,max_paths) : 100}]

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

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Route_opt reports generated in: $::REPORTS_DIR"
# ==============================================================================
# ==============================================================================
}
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
