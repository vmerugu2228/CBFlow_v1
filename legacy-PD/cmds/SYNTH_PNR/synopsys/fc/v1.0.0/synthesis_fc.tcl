#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR synthesis (compile) - Synopsys Fusion Compiler
# FC-RM: compile.tcl -- Unified synthesis via compile_fusion
# Aligned with FC-RM Y-2026.03
# Stages: pre_initial_map → initial_map → logic_opto → insert_dft →
#          initial_place → initial_drc → initial_opto → final_place → final_opto

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "synthesis"
set NODE_NAME "synthesis1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block, current_block, link_block,
#         set_early_data_check_policy, swap abstracts for hier
# ==============================================================================
flow_proc load_design {
    handle_info "Opening design for synthesis..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$synth_pnr(common,design_lib_name) ne "" ? $synth_pnr(common,design_lib_name) : "${design_name}.nlib"}]

    # FC-RM: open_lib, copy_block from init_design to compile
    open_lib $lib_name
    copy_block -from ${design_name}/init_design -to ${design_name}/compile
    current_block ${design_name}/compile

    # FC-RM: set_early_data_check_policy
    set qor_mode [expr {$synth_pnr(common,compile,qor_mode) ne "" ? $synth_pnr(common,compile,qor_mode) : "balanced"}]
    if {$qor_mode eq "early_design"} {
        set_early_data_check_policy -policy lenient -if_not_exist
    }

    link_block

    # FC-RM: Hierarchical — swap abstracts and set editability
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {[info exists synth_pnr(common,block_abstract_for_compile)] && $synth_pnr(common,block_abstract_for_compile) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $synth_pnr(common,block_abstract_for_compile) 0] \
                -view [lindex $synth_pnr(common,block_abstract_for_compile) 1]
            report_abstracts
        }
        set_editability -blocks [get_blocks -hierarchical] -value false
        report_editability -blocks [get_blocks -hierarchical]
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Design opened: ${design_name}/compile"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for compile, check hold scenarios
# ==============================================================================
}
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for synthesis..."
    global synth_pnr

    # Priority: synth_pnr user override > mmmc_config get_node_scenarios("synthesis")
    if {[info exists synth_pnr(synthesis,compile,active_scenarios)] && $synth_pnr(synthesis,compile,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $synth_pnr(synthesis,compile,active_scenarios)
        handle_info "Active scenarios (user override): $synth_pnr(synthesis,compile,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "synthesis" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/synthesis): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file for modes/corners/scenarios
    if {[info exists synth_pnr(common,mcmm_adjustment_file)] && $synth_pnr(common,mcmm_adjustment_file) ne "" && [file exists $synth_pnr(common,mcmm_adjustment_file)]} {
        source $synth_pnr(common,mcmm_adjustment_file)
    }

    # FC-RM: Check for hold scenarios (needed for CCD)
    if {[sizeof_collection [get_scenarios -filter "hold && active"]] == 0} {
        handle_warning "No active hold scenario found. Recommended for CCD skewing."
    }

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage compile_initial, routing layers
# ==============================================================================
}
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for synthesis..."
    global synth_pnr

    # FC-RM: QoR strategy version
    if {[info exists synth_pnr(common,compile,qor_version)] && $synth_pnr(common,compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $synth_pnr(common,compile,qor_version)
    }

    # FC-RM: Build set_qor_strategy command
    set cmd "set_qor_strategy -stage compile_initial"
    set metric [expr {$synth_pnr(common,compile,qor_metric) ne "" ? $synth_pnr(common,compile,qor_metric) : "timing"}]
    set mode [expr {$synth_pnr(common,compile,qor_mode) ne "" ? $synth_pnr(common,compile,qor_mode) : "balanced"}]
    lappend cmd -metric $metric -mode $mode

    if {[info exists synth_pnr(common,compile,reduced_effort)] && $synth_pnr(common,compile,reduced_effort) ne "" && $synth_pnr(common,compile,reduced_effort)} {
        lappend cmd -reduced_effort
    } elseif {[info exists synth_pnr(synthesis,compile,high_effort_timing)] && $synth_pnr(synthesis,compile,high_effort_timing) ne "" && $synth_pnr(synthesis,compile,high_effort_timing)} {
        lappend cmd -high_effort_timing
    }
    if {[info exists synth_pnr(common,compile,congestion_effort)] && $synth_pnr(common,compile,congestion_effort) ne ""} {
        lappend cmd -congestion_effort $synth_pnr(common,compile,congestion_effort)
    }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # FC-RM: set_ignored_layers (routing layer constraints)
    if {[info exists synth_pnr(common,route_max_layer)] && $synth_pnr(common,route_max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $synth_pnr(common,route_max_layer)
    }
    if {[info exists synth_pnr(common,route_min_layer)] && $synth_pnr(common,route_min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $synth_pnr(common,route_min_layer)
    }

    # FC-RM: Disable dynamic power for leakage_power metric
    if {$metric eq "leakage_power"} {
        set ::rm_dynamic_scenarios [get_object_name [get_scenarios -filter "active==true&&dynamic_power==true"]]
        if {[llength $::rm_dynamic_scenarios] > 0} {
            handle_info "Disabling dynamic analysis for leakage_power optimization"
            set_scenario_status -dynamic_power false [get_scenarios $::rm_dynamic_scenarios]
        }
    }

    handle_info "QoR strategy set: metric=$metric, mode=$mode"
# ==============================================================================
# flow_proc: configure_compile
# FC-RM: Instance prefixes, lib_cell_purpose, multi-Vt, CTS primary corner,
#         remove propagated clocks, non-persistent settings
# ==============================================================================
}
flow_proc configure_compile {
    handle_info "Configuring compile settings..."
    global synth_pnr tech
    apply_vt_dont_use

    # FC-RM: Instance name prefixes
    set_app_options -name opt.common.user_instance_name_prefix -value compile_
    set_app_options -name cts.common.user_instance_name_prefix -value compile_cts_

    # FC-RM: HDLC naming (UPF compatible)
    set_app_options -name hdlin.naming.upf_compatible -value true

    # FC-RM: Lib cell purpose restrictions
    if {[info exists synth_pnr(common,lib_cell_purpose_file)] && $synth_pnr(common,lib_cell_purpose_file) ne "" && [file exists $synth_pnr(common,lib_cell_purpose_file)]} {
        source $synth_pnr(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && $tech(lib_cell_purpose_file) ne "" && [file exists $tech(lib_cell_purpose_file)]} {
        source $tech(lib_cell_purpose_file)
    }

    # FC-RM: Multi-Vt constraint file
    if {[info exists synth_pnr(common,multi_vt_constraint_file)] && $synth_pnr(common,multi_vt_constraint_file) ne "" && [file exists $synth_pnr(common,multi_vt_constraint_file)]} {
        source $synth_pnr(common,multi_vt_constraint_file)
    }

    # FC-RM: Non-persistent settings
    if {[info exists synth_pnr(common,non_persistent_script)] && $synth_pnr(common,non_persistent_script) ne "" && [file exists $synth_pnr(common,non_persistent_script)]} {
        source $synth_pnr(common,non_persistent_script)
    }

    # FC-RM: CTS primary corner
    if {[info exists synth_pnr(common,cts_primary_corner)] && $synth_pnr(common,cts_primary_corner) ne ""} {
        set_app_options -name cts.compile.primary_corner -value $synth_pnr(common,cts_primary_corner)
        handle_info "CTS primary corner: $synth_pnr(common,cts_primary_corner)"
    }

    # FC-RM: Remove propagated clocks
    set cur_mode [current_mode]
    foreach_in_collection mode [all_modes] {
        current_mode $mode
        catch {
            if {[regexp true [get_attribute [all_clocks] propagated_clock]]} {
                remove_propagated_clock [get_pins -hierarchical]
                remove_propagated_clock [get_ports]
                remove_propagated_clock [get_clocks -filter "!is_virtual"]
            }
        }
    }
    current_mode $cur_mode

    handle_info "Compile configuration completed"
# ==============================================================================
# flow_proc: pre_compile_setup
# FC-RM: SVF, DFT pre-compile setup, autoungroup check,
#         create_mv_cells, compile_fusion -check_only, mark_clock_trees
# ==============================================================================
}
flow_proc pre_compile_setup {
    handle_info "Running pre-compile setup..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf for formality
    set_svf $::OUTPUTS_DIR/${design_name}_compile.svf

    # FC-RM: User pre-compile script
    if {[info exists synth_pnr(synthesis,compile_pre_script)] && $synth_pnr(synthesis,compile_pre_script) ne "" && [file exists $synth_pnr(synthesis,compile_pre_script)]} {
        handle_info "Sourcing compile pre-script"
        source $synth_pnr(synthesis,compile_pre_script)
    }

    # FC-RM: Read test model for sub-blocks (hierarchical)
    if {[info exists synth_pnr(pro,ctl_for_abstract_blocks)] && $synth_pnr(pro,ctl_for_abstract_blocks) ne "" && [llength $synth_pnr(pro,ctl_for_abstract_blocks)] > 0} {
        foreach ctl $synth_pnr(pro,ctl_for_abstract_blocks) {
            read_test_model $ctl
        }
    }

    # FC-RM: Check autoungroup setting
    if {![get_app_option_value -name compile.flow.autoungroup]} {
        set_app_options -name opt.common.consider_port_direction -value true
    }

    # FC-RM: Create MV cells
    handle_info "Running create_mv_cells"
    create_mv_cells -verbose

    # FC-RM: DFT pre-compile setup
    if {[info exists synth_pnr(synthesis,dft_pre_compile_setup_file)] && $synth_pnr(synthesis,dft_pre_compile_setup_file) ne "" && [file exists $synth_pnr(synthesis,dft_pre_compile_setup_file)]} {
        source $synth_pnr(synthesis,dft_pre_compile_setup_file)
    }

    # FC-RM: Mark clock trees for NDR impact modeling
    handle_info "Marking clock trees for NDR impact modeling"
    mark_clock_trees -routing_rules

    # FC-RM: Spare cell insertion before initial_place
    if {[info exists synth_pnr(common,spare_cell_pre_script)] && $synth_pnr(common,spare_cell_pre_script) ne "" && [file exists $synth_pnr(common,spare_cell_pre_script)]} {
        source $synth_pnr(common,spare_cell_pre_script)
    }

    # FC-RM: Pre-flight check
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }
    redirect -file $::REPORTS_DIR/compile_fusion.check_only { compile_fusion -check_only }

    handle_info "Pre-compile setup completed"
# ==============================================================================
# flow_proc: run_compile
# FC-RM: compile_fusion — unified or stage-by-stage execution
# ==============================================================================
}
flow_proc run_compile {
    handle_info "Running compile_fusion..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    if {[info exists synth_pnr(synthesis,compile,unified_flow)] && $synth_pnr(synthesis,compile,unified_flow) ne "" && $synth_pnr(synthesis,compile,unified_flow)} {
        # ── Unified compile (all stages end-to-end) ───────────────────────────
        handle_info "Running compile_fusion (unified flow — all stages)"
        compile_fusion
        save_block -as ${design_name}/compile

    } else {
        # ── Stage-by-stage compile ────────────────────────────────────────────

        # FC-RM: initial_map
        handle_info "compile_fusion -to initial_map"
        compile_fusion -to initial_map
        connect_pg_net
        save_block -as ${design_name}/compile_initial_map

        # FC-RM: logic_opto
        handle_info "compile_fusion -from logic_opto -to logic_opto"
        # Mark clock network as ideal before logic_opto
        set cur_mode [current_mode]
        foreach_in_collection mode [all_modes] {
            current_mode $mode
            catch {
                set clock_tree [filter_collection \
                    [remove_from_collection [all_fanout -flat -clock_tree] [all_registers -clock_pins]] \
                    "is_clock_used_as_clock==true"]
                if {[sizeof_collection $clock_tree] > 0} { set_ideal_network $clock_tree }
            }
        }
        current_mode $cur_mode

        compile_fusion -from logic_opto -to logic_opto
        save_block -as ${design_name}/compile_logic_opto
        redirect -file $::REPORTS_DIR/report_qor_summary.logic_opto.rpt { report_qor -summary }

        # FC-RM: insert_dft (if enabled)
        if {[info exists synth_pnr(synthesis,dft_insert_enable)] && $synth_pnr(synthesis,dft_insert_enable) ne "" && $synth_pnr(synthesis,dft_insert_enable)} {
            handle_info "DFT insertion enabled"
            if {[info exists synth_pnr(synthesis,dft_setup_file)] && $synth_pnr(synthesis,dft_setup_file) ne "" && [file exists $synth_pnr(synthesis,dft_setup_file)]} {
                source $synth_pnr(synthesis,dft_setup_file)
            }
            create_test_protocol
            redirect -file $::REPORTS_DIR/pre_insert_dft.dft_drc { dft_drc -test_mode all_dft }
            redirect -file $::REPORTS_DIR/preview_dft { preview_dft }
            insert_dft
            redirect -file $::REPORTS_DIR/report_dft.scan_path { report_dft -scan_path }
            save_block -as ${design_name}/compile_insert_dft
        }

        # FC-RM: initial_place → initial_drc → initial_opto
        handle_info "compile_fusion -from initial_place -to initial_place"
        compile_fusion -from initial_place -to initial_place
        save_block -as ${design_name}/compile_initial_place

        handle_info "compile_fusion -from initial_drc -to initial_drc"
        compile_fusion -from initial_drc -to initial_drc
        save_block -as ${design_name}/compile_initial_drc

        handle_info "compile_fusion -from initial_opto -to initial_opto"
        compile_fusion -from initial_opto -to initial_opto
        save_block -as ${design_name}/compile_initial_opto
        redirect -file $::REPORTS_DIR/report_qor_summary.initial_opto.rpt { report_qor -summary }

        # FC-RM: final_place + final_opto (set_qor_strategy for final)
        handle_info "Setting QoR strategy for compile_final_place"
        set final_cmd "set_qor_strategy -stage compile_final_place"
        set metric [expr {$synth_pnr(common,compile,qor_metric) ne "" ? $synth_pnr(common,compile,qor_metric) : "timing"}]
        set mode [expr {$synth_pnr(common,compile,qor_mode) ne "" ? $synth_pnr(common,compile,qor_mode) : "balanced"}]
        lappend final_cmd -metric $metric -mode $mode
        if {[info exists synth_pnr(common,compile,congestion_effort)] && $synth_pnr(common,compile,congestion_effort) ne ""} {
            lappend final_cmd -congestion_effort $synth_pnr(common,compile,congestion_effort)
        }
        eval $final_cmd

        # FC-RM: Enable IRDP
        if {[info exists synth_pnr(synthesis,compile,enable_irdp)] && $synth_pnr(synthesis,compile,enable_irdp) ne "" && $synth_pnr(synthesis,compile,enable_irdp)} {
            set_app_options -name compile.flow.enable_irap -value true
        }

        handle_info "compile_fusion -from final_place -to final_place"
        compile_fusion -from final_place -to final_place
        save_block -as ${design_name}/compile_final_place

        handle_info "compile_fusion -from final_opto -to final_opto"
        compile_fusion -from final_opto -to final_opto
        save_block -as ${design_name}/compile_final_opto
        redirect -file $::REPORTS_DIR/report_qor_summary.final_opto.rpt { report_qor -summary }
    }

    handle_info "compile_fusion completed successfully"
# ==============================================================================
# flow_proc: post_compile
# FC-RM: User post script, spare cells, re-enable dynamic power,
#         connect_pg_net
# ==============================================================================
}
flow_proc post_compile {
    handle_info "Running post-compile tasks..."
    global synth_pnr

    # FC-RM: User post-compile script
    if {[info exists synth_pnr(synthesis,compile_post_script)] && $synth_pnr(synthesis,compile_post_script) ne "" && [file exists $synth_pnr(synthesis,compile_post_script)]} {
        handle_info "Sourcing compile post-script"
        source $synth_pnr(synthesis,compile_post_script)
    }

    # FC-RM: Spare cell insertion after final_opto
    if {[info exists synth_pnr(common,spare_cell_post_script)] && $synth_pnr(common,spare_cell_post_script) ne "" && [file exists $synth_pnr(common,spare_cell_post_script)]} {
        source $synth_pnr(common,spare_cell_post_script)
    }

    # FC-RM: Re-enable dynamic power scenarios
    if {[info exists ::rm_dynamic_scenarios] && [llength $::rm_dynamic_scenarios] > 0} {
        handle_info "Re-enabling dynamic power analysis"
        set_scenario_status -dynamic_power true [get_scenarios $::rm_dynamic_scenarios]
    }

    # FC-RM: connect_pg_net
    if {[info exists synth_pnr(common,connect_pg_net_script)] && $synth_pnr(common,connect_pg_net_script) ne "" && [file exists $synth_pnr(common,connect_pg_net_script)]} {
        source $synth_pnr(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    handle_info "Post-compile tasks completed"
# ==============================================================================
# flow_proc: finalize_netlist
# FC-RM: change_names, write_ascii_files, saif_map
# ==============================================================================
}
flow_proc finalize_netlist {
    handle_info "Finalizing netlist..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: Define and apply name rules for verilog output
    if {[info exists synth_pnr(common,define_name_rules_options)] && $synth_pnr(common,define_name_rules_options) ne ""} {
        eval define_name_rules verilog $synth_pnr(common,define_name_rules_options)
    }
    redirect -file $::REPORTS_DIR/report_name_rules.log { report_name_rules }
    change_names -rules verilog -hierarchy -skip_physical_only_cells
    redirect -file $::REPORTS_DIR/report_names.log { report_names -rules verilog }

    # FC-RM: write_ascii_files (netlist + UPF + SDC for downstream)
    set upf_mode [expr {$synth_pnr(common,upf_mode) ne "" ? $synth_pnr(common,upf_mode) : "none"}]
    if {$upf_mode eq "golden" && [info exists synth_pnr(input,upf_file)]} {
        write_ascii_files -force -compress gzip \
            -output $::OUTPUTS_DIR/compile.ascii_files \
            -golden_upf $synth_pnr(input,upf_file)
    } else {
        write_ascii_files -force -compress gzip \
            -output $::OUTPUTS_DIR/compile.ascii_files
    }

    # FC-RM: saif_map write
    saif_map -type ptpx -write_map $::OUTPUTS_DIR/compile.saif.ptpx.map
    saif_map -write_map $::OUTPUTS_DIR/compile.saif.fc.map

    handle_info "Netlist finalized"
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
        set hier_level [expr {$synth_pnr(common,physical_hierarchy_level) ne "" ? $synth_pnr(common,physical_hierarchy_level) : "bottom"}]

        if {$hier_level ne "top"} {
            handle_info "Creating abstract and frame for hierarchical design (level=$hier_level)"
            create_abstract -read_only
            create_frame -block_all true
        }
    } else {
        handle_info "Flat design — abstract creation skipped"
    }

    # FC-RM: Write DFT test model
    if {[info exists synth_pnr(synthesis,dft_insert_enable)] && $synth_pnr(synthesis,dft_insert_enable) ne "" && $synth_pnr(synthesis,dft_insert_enable)} {
        write_test_model -output $::OUTPUTS_DIR/${synth_pnr(common,design_name)}.ctl
    }

    handle_info "Abstracts completed"
# ==============================================================================
# flow_proc: save_design
# FC-RM: save_upf, save_block, set_svf -off
# ==============================================================================
}
flow_proc save_design {
    handle_info "Saving compile design..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: Save UPF
    set upf_mode [expr {$synth_pnr(common,upf_mode) ne "" ? $synth_pnr(common,upf_mode) : "none"}]
    if {$upf_mode eq "golden"} {
        save_upf $::OUTPUTS_DIR/compile.supplemental.upf
    } elseif {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
        save_upf $::OUTPUTS_DIR/compile.save_upf
    }

    # FC-RM: FUSA
    if {[info exists synth_pnr(common,enable_fusa)] && $synth_pnr(common,enable_fusa) ne "" && $synth_pnr(common,enable_fusa)} {
        save_ssf $::OUTPUTS_DIR/compile.ssf
    }

    # FC-RM: save_block
    save_block
    if {[info exists synth_pnr(common,output,block_labeling)] && $synth_pnr(common,output,block_labeling) ne "" && $synth_pnr(common,output,block_labeling)} {
        save_block -as ${design_name}/compile
        handle_info "Block saved: ${design_name}/compile"
    }

    # FC-RM: Close SVF
    set_svf -off

    handle_info "Compile design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_power, report_congestion,
#         write_qor_data, run_end
# ==============================================================================
}
flow_proc generate_reports {
    handle_info "Generating synthesis reports..."
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

    # FC-RM: Design reports
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion -rerun_global_router }
    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }

    # FC-RM: Power report
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: Threshold voltage group (Vt distribution)
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: App options snapshot
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label compile -output $run_dir/qor_data
    }

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Synthesis reports generated in: $::REPORTS_DIR"
# ==============================================================================
# ==============================================================================
}
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
