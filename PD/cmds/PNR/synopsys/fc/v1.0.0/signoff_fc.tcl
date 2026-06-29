#!/usr/bin/env tclsh
# CBFlow shared (PNR + SYNTH_PNR) — synopsys/fc — signoff (signoff + icv_in_design) - Synopsys Fusion Compiler
# FC-RM: signoff.tcl + icv_in_design.tcl -- Filler insertion, signal EM,
#         ICV signoff DRC, metal fill, base fill
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

if {![info exists ::flow_type] || $::flow_type eq ""} { set ::flow_type $::env(CBFLOW_FLOW_TYPE) }
set FLOW_TYPE $::flow_type
set STAGE_NAME "signoff"
set NODE_NAME "signoff1"

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
# FC-RM: open_lib, copy_block from route_opt, link_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for signoff..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$cfg(common,design_lib_name) ne "" ? $cfg(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    set _from_block [cbflow_get_head_block "route_opt"]
    handle_info "load_design: copying from ${design_name}/${_from_block} (head-block manifest)"
    copy_block -from ${design_name}/${_from_block} -to ${design_name}/signoff
    current_block ${design_name}/signoff
    link_block

    # FC-RM: Hierarchical abstract swap
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        if {[info exists cfg(common,block_abstract_for_signoff)] && $cfg(common,block_abstract_for_signoff) ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $cfg(common,block_abstract_for_signoff) 0] \
                -view [lindex $cfg(common,block_abstract_for_signoff) 1]
            report_abstracts
        }
    }

    handle_info "Design loaded: ${design_name}/signoff"
# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for signoff (all scenarios)
# ==============================================================================
}
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for signoff..."
    global cfg

    # Priority: user override > mmmc_config get_node_scenarios("signoff")
    if {[info exists cfg(signoff,active_scenarios)] && $cfg(signoff,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $cfg(signoff,active_scenarios)
        handle_info "Active scenarios (user override): $cfg(signoff,active_scenarios)"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set node_scenarios [get_node_scenarios "signoff" "all"]
        if {[llength $node_scenarios] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $node_scenarios
            handle_info "Active scenarios (mmmc_config/signoff): $node_scenarios"
        }
    }

    # FC-RM: Adjustment file
    if {[info exists cfg(common,mcmm_adjustment_file)] && $cfg(common,mcmm_adjustment_file) ne "" && [file exists $cfg(common,mcmm_adjustment_file)]} {
        source $cfg(common,mcmm_adjustment_file)
    }

    # FC-RM: Non-persistent settings
    if {[info exists cfg(common,non_persistent_script)] && $cfg(common,non_persistent_script) ne "" && [file exists $cfg(common,non_persistent_script)]} {
        source $cfg(common,non_persistent_script)
    }

    # FC-RM: Disable soft-rule timing opt during ECO routing
    set_app_options -name route.detail.eco_route_use_soft_spacing_for_timing_optimization -value false

    handle_info "Active scenarios configured"
# ==============================================================================
# flow_proc: insert_filler_cells
# FC-RM: signoff filler cell insertion (metal and non-metal)
# ==============================================================================
}
flow_proc insert_filler_cells {
    handle_info "Inserting filler cells..."
    global flow cfg tech

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    # FC-RM: set_svf for formality tracking
    set_svf $::OUTPUTS_DIR/${design_name}_signoff.svf

    # FC-RM: set_qor_strategy -stage signoff
    set cmd "set_qor_strategy -stage signoff"
    set metric [expr {$cfg(common,compile,qor_metric) ne "" ? $cfg(common,compile,qor_metric) : "timing"}]
    lappend cmd -metric $metric
    handle_info "Running: $cmd"
    eval $cmd

    # FC-RM: Pre-signoff script
    if {[info exists cfg(pro,signoff_pre_script)] && [file exists $cfg(pro,signoff_pre_script)]} {
        source $cfg(pro,signoff_pre_script)
    }

    # FC-RM: Pre-reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }

    # FC-RM: Disable sub-block timing
    set _run_type $flow(run_type)
    if {$_run_type eq "hier"} {
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    # FC-RM: Filler cell insertion
    if {[info exists cfg(signoff,insert_filler)] && $cfg(signoff,insert_filler) ne "" && [string is true -strict $cfg(signoff,insert_filler)]} {
        # Source filler sidefile (foundry-specific filler commands)
        if {[info exists tech(filler_sidefile)] && $tech(filler_sidefile) ne "" && [file exists $tech(filler_sidefile)]} {
            handle_info "Sourcing filler sidefile: $tech(filler_sidefile)"
            source $tech(filler_sidefile)
        } else {
            # Default: create_stdcell_fillers
            handle_info "Running create_stdcell_fillers"
            create_stdcell_fillers -lib_cells [get_lib_cells */FILL*]
        }
    }

    # FC-RM: Decap cell insertion
    if {[info exists cfg(signoff,insert_decap)] && $cfg(signoff,insert_decap) ne "" && [string is true -strict $cfg(signoff,insert_decap)]} {
        if {[info exists tech(decap_cells)] && $tech(decap_cells) ne ""} {
            handle_info "Inserting decap cells"
            create_stdcell_fillers -lib_cells [get_lib_cells $tech(decap_cells)]
        }
    }

    handle_info "Filler cell insertion completed"
# ==============================================================================
# flow_proc: fix_signal_em
# FC-RM: Signal EM analysis and fixing (read constraints, report, fix)
# ==============================================================================
}
flow_proc fix_signal_em {
    handle_info "Running signal EM analysis..."
    global flow cfg tech

    # FC-RM: Signal EM constraint file
    if {[info exists tech(signal_em_constraint_file)] && $tech(signal_em_constraint_file) ne "" && [file exists $tech(signal_em_constraint_file)]} {
        set cmd "read_signal_em_constraints $tech(signal_em_constraint_file)"
        if {[info exists tech(signal_em_constraint_format)] && $tech(signal_em_constraint_format) ne ""} {
            lappend cmd -format $tech(signal_em_constraint_format)
        }
        handle_info "Running: $cmd"
        eval $cmd

        # FC-RM: EM SAIF file
        if {[info exists cfg(signoff,em_saif)] && [file exists $cfg(signoff,em_saif)]} {
            read_saif $cfg(signoff,em_saif)
        }

        # FC-RM: Signal EM analysis and fix
        if {[info exists cfg(signoff,em_scenario)] && $cfg(signoff,em_scenario) ne ""} {
            set_app_options -name time.si_enable_analysis -value true
            set cur_sce [current_scenario]
            current_scenario $cfg(signoff,em_scenario)
            redirect -file $::REPORTS_DIR/report_signal_em { report_signal_em -violated }

            if {[info exists cfg(signoff,em_fixing)] && $cfg(signoff,em_fixing) ne "" && [string is true -strict $cfg(signoff,em_fixing)]} {
                handle_info "Fixing signal EM violations"
                fix_signal_em
                redirect -file $::REPORTS_DIR/report_signal_em.post { report_signal_em -violated }
            }
            current_scenario $cur_sce
        }
    }

    handle_info "Signal EM analysis completed"
# ==============================================================================
# flow_proc: run_signoff_drc
# FC-RM: ICV in-design signoff DRC check (signoff_check_drc)
# ==============================================================================
}
flow_proc run_signoff_drc {
    handle_info "Running signoff DRC (ICV in-design)..."
    global flow cfg tech

    # FC-RM: DRC runset
    if {[info exists cfg(signoff,drc_runset)] && [file exists $cfg(signoff,drc_runset)]} {
        set_app_options -name signoff.check_drc.runset -value $cfg(signoff,drc_runset)

        # FC-RM: Layer map file
        if {[info exists tech(gds_layer_map_file)] && $tech(gds_layer_map_file) ne ""} {
            set_app_options -name signoff.physical.layer_map_file -value $tech(gds_layer_map_file)
        }

        # FC-RM: Stream files for merge
        if {[info exists tech(stream_files_for_merge)] && $tech(stream_files_for_merge) ne ""} {
            set_app_options -name signoff.physical.merge_stream_files -value $tech(stream_files_for_merge)
        }

        # FC-RM: DRC select/unselect rules
        if {[info exists cfg(signoff,drc_select_rules)] && $cfg(signoff,drc_select_rules) ne ""} {
            set_app_options -name signoff.check_drc.select_rules -value $cfg(signoff,drc_select_rules)
        }

        save_block
        redirect -file $::REPORTS_DIR/report_app_options.signoff_physical {
            report_app_options signoff.physical.*
        }

        # FC-RM: signoff_check_drc
        handle_info "Running signoff_check_drc"
        signoff_check_drc

        redirect -file $::REPORTS_DIR/signoff_check_drc.rpt {
            report_drc_errors -error_data zroute.err
        }

        # FC-RM: signoff_fix_drc — automatically fix DRC violations
        if {[info exists cfg(signoff,fix_drc)] && $cfg(signoff,fix_drc) ne "" && [string is true -strict $cfg(signoff,fix_drc)]} {
            handle_info "Running signoff_fix_drc"
            signoff_fix_drc
            redirect -file $::REPORTS_DIR/signoff_check_drc.post_fix.rpt {
                signoff_check_drc
            }
        }
    } else {
        handle_info "No DRC runset specified, skipping signoff DRC check"
    }

    # FC-RM: route_detail -incremental — post-filler routing cleanup
    handle_info "Running incremental route_detail for post-filler cleanup"
    route_detail -incremental true

    # FC-RM: insert_diode_on_nets — antenna diode insertion
    if {[info exists cfg(signoff,insert_diodes)] && $cfg(signoff,insert_diodes) ne "" && [string is true -strict $cfg(signoff,insert_diodes)]} {
        handle_info "Inserting antenna diodes"
        insert_diode_on_nets -diode_cell $tech(cells,antenna_diode) -verbose
        route_detail -incremental true
        handle_info "Antenna diodes inserted and rerouted"
    } elseif {[info exists tech(cells,antenna_diode)] && $tech(cells,antenna_diode) ne ""} {
        handle_info "Inserting antenna diodes (auto)"
        insert_diode_on_nets -diode_cell $tech(cells,antenna_diode)
        route_detail -incremental true
    }

    handle_info "Signoff DRC completed"
}

# ==============================================================================
# flow_proc: redhawk_rail_analysis
# Optional RedHawk-SC IR signoff after signoff DRC. Gated on
# <flow>(signoff,redhawk_enable) OR <flow>(common,redhawk_enable) == "true".
# Stages cfg(signoff,redhawk,*) → ::REDHAWK_* globals, then sources the
# standalone redhawk_fc.tcl recipe with stage="signoff". One-shot static +
# dynamic IR check; no fix-point feedback (signoff is post-opto). Default OFF.
# ==============================================================================
flow_proc redhawk_rail_analysis {
    if {![redhawk_enabled signoff]} {
        handle_info "RedHawk-SC disabled (signoff,redhawk_enable != true) — skipping"
        return
    }
    handle_info "RedHawk-SC enabled — staging globals for signoff"
    redhawk_stage_globals signoff
    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/redhawk_fc.tcl"
    if {![file exists $_recipe]} {
        set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/redhawk_fc.tcl"
    }
    handle_info "Sourcing RedHawk recipe: $_recipe"
    source $_recipe
}

# ==============================================================================
# flow_proc: create_metal_fill
# FC-RM: ICV in-design metal fill (signoff_create_metal_fill)
# ==============================================================================
flow_proc create_metal_fill {
    handle_info "Creating metal fill..."
    global flow cfg tech

    if {[info exists cfg(signoff,metal_fill)] && $cfg(signoff,metal_fill) ne "" && [string is true -strict $cfg(signoff,metal_fill)]} {
        # FC-RM: Metal fill runset
        if {[info exists tech(metal_fill_runset)] && $tech(metal_fill_runset) ne "" && [file exists $tech(metal_fill_runset)]} {
            set_app_options -name signoff.create_metal_fill.runset -value $tech(metal_fill_runset)
        }

        # FC-RM: Track-based or runset-based
        set track_based "off"
        if {[info exists cfg(signoff,metal_fill_track_based)] && $cfg(signoff,metal_fill_track_based) ne ""} {
            set track_based $cfg(signoff,metal_fill_track_based)
        }

        if {$track_based eq "off"} {
            # Runset-based metal fill
            set fill_cmd "signoff_create_metal_fill"
        } else {
            # Track-based metal fill
            set fill_cmd "signoff_create_metal_fill -track_fill $track_based -fill_all_tracks true"
            if {[info exists cfg(signoff,metal_fill_parameter_file)] && [file exists $cfg(signoff,metal_fill_parameter_file)]} {
                lappend fill_cmd -track_fill_parameter_file $cfg(signoff,metal_fill_parameter_file)
            }
        }

        # FC-RM: Timing-driven metal fill
        if {[info exists cfg(signoff,metal_fill_timing_threshold)] && $cfg(signoff,metal_fill_timing_threshold) ne ""} {
            lappend fill_cmd -timing_preserve_setup_slack_threshold $cfg(signoff,metal_fill_timing_threshold)
            set_extraction_options -real_metalfill_extraction none
        }

        save_block
        handle_info "Running: $fill_cmd"
        eval $fill_cmd
        save_block

        # FC-RM: Set extraction for real metal fill after fill creation
        set_extraction_options -real_metalfill_extraction floating -virtual_metalfill_extraction none

        # FC-RM: Post-fill DRC check
        if {[info exists cfg(signoff,drc_runset)] && [file exists $cfg(signoff,drc_runset)]} {
            set_app_options -name signoff.check_drc.run_dir -value z_MFILL_after
            signoff_check_drc -error_data POST_MFILL
        }
    } else {
        handle_info "Metal fill disabled, skipping"
    }

    handle_info "Metal fill completed"
# ==============================================================================
# flow_proc: post_signoff
# FC-RM: User post-script, connect_pg_net, check_routes
# ==============================================================================
}
flow_proc post_signoff {
    handle_info "Running post-signoff tasks..."
    global flow cfg

    # FC-RM: User post-script
    if {[info exists cfg(pro,signoff_post_script)] && [file exists $cfg(pro,signoff_post_script)]} {
        source $cfg(pro,signoff_post_script)
    }

    # FC-RM: connect_pg_net
    if {[info exists cfg(common,connect_pg_net_script)] && $cfg(common,connect_pg_net_script) ne "" && [file exists $cfg(common,connect_pg_net_script)]} {
        source $cfg(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # FC-RM: check_routes
    redirect -file $::REPORTS_DIR/check_routes { check_routes }

    handle_info "Post-signoff tasks completed"
# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract, create_frame, derive_hier_antenna_property
# ==============================================================================
}
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]
    set _run_type $flow(run_type)

    if {$_run_type eq "hier"} {
        set hier_level [expr {$cfg(common,physical_hierarchy_level) ne "" ? $cfg(common,physical_hierarchy_level) : "bottom"}]
        if {$hier_level ne "top"} {
            handle_info "Creating abstract and frame (level=$hier_level)"
            create_abstract -read_only
            create_frame -block_all true
            # FC-RM: Derive hierarchical antenna property
            derive_hier_antenna_property -design ${design_name}/signoff
            save_block ${design_name}/signoff.frame
        }
    }

    handle_info "Abstracts completed"
# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block, set_svf -off
# ==============================================================================
}
flow_proc save_design {
    handle_info "Saving signoff design..."
    global cfg flow

    set design_name [expr {$cfg(common,design_name) ne "" ? $cfg(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists cfg(common,output,block_labeling)] && $cfg(common,output,block_labeling) ne "" && $cfg(common,output,block_labeling)} {
        save_block -as ${design_name}/signoff
        handle_info "Block saved: ${design_name}/signoff"
    }
    cbflow_set_head_block "signoff" $STAGE_NAME $NODE_NAME

    set_svf -off
    handle_info "Signoff design saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_power, check_routes,
#         write_qor_data, run_end
# ==============================================================================
}
flow_proc generate_reports {
    handle_info "Generating signoff reports..."
    global cfg

    set max_paths [expr {$cfg(common,analysis,max_paths) ne "" ? $cfg(common,analysis,max_paths) : 100}]

    # FC-RM: Timing settings for post-route/signoff
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

    # FC-RM: SI
    redirect -file $::REPORTS_DIR/report_si.rpt {
        report_timing -crosstalk_delta -max_paths $max_paths -nosplit
    }

    # FC-RM: Final check_routes
    redirect -file $::REPORTS_DIR/check_routes.final { check_routes }

    # FC-RM: check_timing (constraint completeness at signoff)
    redirect -file $::REPORTS_DIR/check_timing.rpt { check_timing }

    # FC-RM: check_legality
    redirect -file $::REPORTS_DIR/check_legality.rpt { check_legality }

    # FC-RM: Threshold voltage group (Vt distribution)
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }

    # FC-RM: App options
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label signoff -output $run_dir/qor_data
    }

    # FC-RM: run_end
    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Signoff reports generated in: $::REPORTS_DIR"
# ==============================================================================
# ==============================================================================
}
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
