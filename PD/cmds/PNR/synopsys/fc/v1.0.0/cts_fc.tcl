#!/usr/bin/env tclsh
# CBFlow shared cts_fc.tcl — synopsys/fc CTS stage (clock_opt_cts)
# Same byte-identical file lives at:
#   PD/cmds/PNR/synopsys/fc/v1.0.0/cts_fc.tcl
#   PD/cmds/SYNTH_PNR/synopsys/fc/v1.0.0/cts_fc.tcl
# Subnode handlers set ::flow_type to "PNR" or "SYNTH_PNR"; cfg_get/cfg_true
# resolve pnr(...) vs synth_pnr(...) transparently. Edit ONE copy and then
# sync the other (PD/utils/validation has a healthcheck for drift).
#
# FC-RM source of truth: Y-2026.03 clock_opt_cts.tcl

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

# Flow type — subnode handler sets ::flow_type; env is the standalone fallback.
if {![info exists ::flow_type] || $::flow_type eq ""} {
    set ::flow_type $::env(CBFLOW_FLOW_TYPE)
}
set FLOW_TYPE $::flow_type
set STAGE_NAME "cts"
set NODE_NAME "cts1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib + copy_block from place_opt → clock_opt_cts, hier abstract swap
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for clock_opt_cts..."
    global flow

    set design_name [cfg_get common,design_name $flow(design_name)]
    set lib_name    [cfg_get common,design_lib_name "${design_name}.nlib"]

    open_lib $lib_name
    copy_block -from ${design_name}/place_opt -to ${design_name}/clock_opt_cts
    current_block ${design_name}/clock_opt_cts
    link_block

    if {$flow(run_type) eq "hier"} {
        set _abs [cfg_get common,block_abstract_for_cts ""]
        if {$_abs ne ""} {
            change_abstract -references [get_blocks -hierarchical] \
                -label [lindex $_abs 0] -view [lindex $_abs 1]
            report_abstracts
        }
        if {[cfg_true common,promote_clock_balance_points]} {
            set _f [cfg_get common,promote_abstract_clock_data_file ""]
            if {$_f ne "" && [file exists $_f]} { source $_f }
        }
        set_timing_paths_disabled_blocks -all_sub_blocks
    }

    handle_info "Design loaded: ${design_name}/clock_opt_cts"
}

# ==============================================================================
# flow_proc: set_active_scenarios
# FC-RM: set_scenario_status for CTS (include hold scenarios for CCD)
# ==============================================================================
flow_proc set_active_scenarios {
    handle_info "Setting active scenarios for clock_opt_cts..."

    set _override [cfg_get cts,clock_opt_cts,active_scenarios ""]
    if {$_override ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $_override
        handle_info "Active scenarios (user override): $_override"
    } elseif {[info commands get_node_scenarios] ne ""} {
        set _ns [get_node_scenarios "cts" "all"]
        if {[llength $_ns] > 0} {
            set_scenario_status -active false [get_scenarios -filter active]
            set_scenario_status -active true $_ns
            handle_info "Active scenarios (mmmc_config/cts): $_ns"
        }
    }

    set _adj [cfg_get common,mcmm_adjustment_file ""]
    if {$_adj ne "" && [file exists $_adj]} { source $_adj }

    if {[sizeof_collection [get_scenarios -filter "hold && active"]] == 0} {
        handle_warning "No active hold scenario! CCD skewing requires hold scenarios for CTS."
    }

    handle_info "Active scenarios configured"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy -stage cts, disable power scenarios for timing
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy for CTS..."

    set _ver [cfg_get common,compile,qor_version ""]
    if {$_ver ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $_ver
    }

    set metric [cfg_get common,compile,qor_metric "timing"]
    set mode   [cfg_get common,compile,qor_mode   "balanced"]
    set cmd "set_qor_strategy -stage cts -metric $metric -mode $mode"
    if {[cfg_true common,compile,reduced_effort]} { lappend cmd -reduced_effort }

    handle_info "Running: $cmd"
    redirect -file $::REPORTS_DIR/set_qor_strategy { eval $cmd -report_only }
    eval $cmd

    # Disable power scenarios for timing-focused QoR
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
# flow_proc: configure_cts
# FC-RM: instance prefixes, lib_cell_purpose, non-persistent, multi-Vt,
#        antenna rules, sidefile, MSCTS mesh routing hook
# ==============================================================================
flow_proc configure_cts {
    handle_info "Configuring CTS settings..."
    global tech
    apply_vt_dont_use

    # FC-RM: instance name prefixes
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_

    # FC-RM: lib cell purpose
    set _lcp [cfg_get common,lib_cell_purpose_file ""]
    if {$_lcp ne "" && [file exists $_lcp]} {
        source $_lcp
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source $tech(lib_cell_purpose_file)
    }

    # FC-RM: CTS sidefile
    set _sf [cfg_get cts,cts_sidefile ""]
    if {$_sf ne "" && [file exists $_sf]} { source $_sf }

    # FC-RM: non-persistent settings
    set _nps [cfg_get common,non_persistent_script ""]
    if {$_nps ne "" && [file exists $_nps]} { source $_nps }

    # FC-RM: multi-Vt constraint
    set _mvt [cfg_get common,multi_vt_constraint_file ""]
    if {$_mvt ne "" && [file exists $_mvt]} { source $_mvt }

    # FC-RM: antenna rules
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Sourcing antenna rules: $tech(antenna_rule_file)"
        source $tech(antenna_rule_file)
    }

    # FC-RM: user CTS pre-script
    set _pre [cfg_get cts,cts_pre_script ""]
    if {$_pre ne "" && [file exists $_pre]} { source $_pre }

    # FC-RM: pre-CTS reports
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_lib_cell_purpose {
        report_lib_cell -objects [get_lib_cells] -column {full_name:20 valid_purposes}
    }
    redirect -file $::REPORTS_DIR/pre_cts.report_clock_settings { report_clock_settings }
    redirect -file $::REPORTS_DIR/pre_cts.check_clock_tree { check_clock_trees }

    # FC-RM: MSCTS mesh routing user override (separate from full construct_mscts)
    set _mr [cfg_get cts,mscts_mesh_routing_script ""]
    if {$_mr ne "" && [file exists $_mr]} {
        mark_clock_trees -clear -dont_touch
        source $_mr
    }

    # PNR-flavored knobs preserved (NDR rule + primary corner) — read via cfg_get
    # so the same logic runs for SYNTH_PNR too if the keys are set there.
    set _ndr [cfg_get cts,ndr_rule ""]
    if {$_ndr ne ""} {
        handle_info "Applying clock NDR rule: $_ndr"
        mark_clock_trees -routing_rules
    }
    set _pc [cfg_get cts,primary_corner ""]
    if {$_pc ne ""} {
        handle_info "Setting cts.compile.primary_corner to $_pc"
        set_app_options -name cts.compile.primary_corner -value $_pc
    }

    handle_info "CTS configuration completed"
}

# ==============================================================================
# flow_proc: construct_mscts
# Optional Multi-Source CTS step. Gated on `<flow>(cts,mpcts) == "true"`.
# Stages cascade values into FC-RM-canonical MSCTS_* globals, then sources
# the standalone mscts_fc.tcl recipe (1:1 port of FC-RM Y-2026.03
# examples/mscts.regular.tcl). Single canonical copy lives under
# cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl — shared across PNR + SYNTH_PNR.
# ==============================================================================
flow_proc construct_mscts {
    if {![cfg_true cts,mpcts]} {
        handle_info "MSCTS / multipoint CTS disabled (cts,mpcts != true) — skipping"
        return
    }

    handle_info "MSCTS / multipoint CTS enabled — staging inputs from cts,mpcts,*"

    set ::MSCTS_CLOCK                       [cfg_get cts,mpcts,clock                       ""]
    set ::MSCTS_SOURCE                      [cfg_get cts,mpcts,source                      ""]
    set ::MSCTS_TOPOLOGY                    [cfg_get cts,mpcts,topology                    "htree"]
    set ::MSCTS_PITCH                       [cfg_get cts,mpcts,pitch                       "100"]
    set ::MSCTS_TAP_DRIVER_LIB_CELLS        [cfg_get cts,mpcts,tap_driver_lib_cells        ""]
    set ::MSCTS_NET                         [cfg_get cts,mpcts,net                         ""]
    set ::MSCTS_TAP_DRIVER_MAX_DISPLACEMENT [cfg_get cts,mpcts,tap_driver_max_displacement ""]
    set ::MSCTS_TAP_BOUNDARY                [cfg_get cts,mpcts,tap_boundary                ""]
    set ::MSCTS_MACRO_KEEPOUT               [cfg_get cts,mpcts,macro_keepout               "false"]
    set ::MSCTS_HTREE_LIB_CELLS             [cfg_get cts,mpcts,htree_lib_cells             ""]
    set ::MSCTS_HTREE_NDR_RULE_NAME         [cfg_get cts,mpcts,htree_ndr_rule_name         ""]
    set ::MSCTS_HTREE_MIN_ROUTING_LAYER     [cfg_get cts,mpcts,htree_min_routing_layer     ""]
    set ::MSCTS_HTREE_MAX_ROUTING_LAYER     [cfg_get cts,mpcts,htree_max_routing_layer     ""]
    set ::MSCTS_MESH_NET                    [cfg_get cts,mpcts,mesh_net                    ""]
    set ::MSCTS_MESH_NET_PORT               [cfg_get cts,mpcts,mesh_net_port               ""]
    set ::MSCTS_MESH_NET_PORT_TRANSITION    [cfg_get cts,mpcts,mesh_net_port_transition    ""]
    set ::MSCTS_MESH_NET_PORT_DELAY         [cfg_get cts,mpcts,mesh_net_port_delay         ""]
    set ::MSCTS_INPUT_TRANSITION            [cfg_get cts,mpcts,input_transition            ""]
    set ::MSCTS_NET_DELAY                   [cfg_get cts,mpcts,net_delay                   ""]
    set ::TCL_USER_MESH_ANNOTATION_SCRIPT   [cfg_get cts,mpcts,user_mesh_annotation_script ""]

    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/mscts_fc.tcl"
    if {![file exists $_recipe]} {
        set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl"
    }
    handle_info "Sourcing MSCTS recipe: $_recipe"
    source $_recipe
    handle_info "MSCTS construction completed"
}

# ==============================================================================
# flow_proc: build_clock_trees
# FC-RM: clock_opt -from build_clock -to build_clock (with relaxed transition)
# ==============================================================================
flow_proc build_clock_trees {
    handle_info "Building clock trees..."
    global flow

    set design_name [cfg_get common,design_name $flow(design_name)]

    set_svf $::OUTPUTS_DIR/${design_name}_clock_opt_cts.svf

    handle_info "Checking relaxed clock transition constraint"
    check_clock_transition -threshold 0.15 -apply_max_transition

    handle_info "Running clock_opt -from build_clock -to build_clock"
    clock_opt -from build_clock -to build_clock

    if {[cfg_true common,output,block_labeling] || [cfg_true output,block_labeling]} {
        save_block -as ${design_name}/clock_opt_cts_build_clock
    }

    handle_info "Setting propagated clocks"
    set_propagated_clock [all_clocks]

    compute_clock_latency
    restore_clock_transition

    handle_info "Clock trees built"
}

# ==============================================================================
# flow_proc: route_clock_nets
# FC-RM: clock_opt -from route_clock -to route_clock
# ==============================================================================
flow_proc route_clock_nets {
    handle_info "Routing clock nets..."
    handle_info "Running clock_opt -from route_clock -to route_clock"
    clock_opt -from route_clock -to route_clock
    handle_info "Clock nets routed"
}

# ==============================================================================
# flow_proc: post_cts_optimization
# FC-RM: redundant via insertion, AOCV enable, create_shields, user post-script
# ==============================================================================
flow_proc post_cts_optimization {
    handle_info "Running post-CTS optimization..."
    global tech

    if {[cfg_true cts,redundant_via]} {
        if {[info exists tech(redundant_via_mapping_file)] && [file exists $tech(redundant_via_mapping_file)]} {
            handle_info "Sourcing redundant via mapping"
            source $tech(redundant_via_mapping_file)
            redirect -file $::REPORTS_DIR/report_via_mapping.rpt { report_via_mapping }
        }
        handle_info "Adding redundant vias"
        add_redundant_vias
    }

    if {[cfg_true cts,clock_opt_cts,enable_aocv] || [cfg_true cts,enable_aocv]} {
        set_app_options -name time.aocvm_enable_analysis -value true
        handle_info "AOCV analysis enabled after CTS"
    }

    if {[cfg_true cts,cts,enable_shields] || [cfg_true cts,enable_shields]} {
        set shields_cmd "create_shields"
        set _opts [cfg_get cts,cts,shields_options [cfg_get cts,shields_options ""]]
        if {$_opts ne ""} { append shields_cmd " $_opts" }
        set _gnd [cfg_get cts,cts,shields_ground_net [cfg_get cts,shields_ground_net ""]]
        if {$_gnd ne ""} { lappend shields_cmd -with_ground $_gnd }
        handle_info "Running: $shields_cmd"
        eval $shields_cmd
    }

    set _post [cfg_get cts,cts_post_script ""]
    if {$_post ne "" && [file exists $_post]} { source $_post }

    handle_info "Post-CTS optimization completed"
}

# ==============================================================================
# flow_proc: connect_power_ground
# FC-RM: connect_pg_net, re-enable power scenarios, check_routes
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting PG nets and finalizing..."

    set _pgs [cfg_get common,connect_pg_net_script ""]
    if {$_pgs ne "" && [file exists $_pgs]} {
        source $_pgs
    } else {
        connect_pg_net
    }

    if {[info exists ::rm_leakage_scenarios] && [llength $::rm_leakage_scenarios] > 0} {
        handle_info "Re-enabling leakage power analysis"
        set_scenario_status -leakage_power true [get_scenarios $::rm_leakage_scenarios]
    }
    if {[info exists ::rm_dynamic_scenarios] && [llength $::rm_dynamic_scenarios] > 0} {
        handle_info "Re-enabling dynamic power analysis"
        set_scenario_status -dynamic_power true [get_scenarios $::rm_dynamic_scenarios]
    }

    redirect -file $::REPORTS_DIR/check_routes { check_routes -open_net false }

    handle_info "PG nets connected, routes checked"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract + create_frame for hierarchical bottom-level
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global flow

    if {$flow(run_type) eq "hier"} {
        set hier_level [cfg_get common,physical_hierarchy_level "bottom"]
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
# FC-RM: save_block, optional labeled save, set_svf -off
# ==============================================================================
flow_proc save_design {
    handle_info "Saving clock_opt_cts design..."
    global flow

    set design_name [cfg_get common,design_name $flow(design_name)]

    save_block
    if {[cfg_true common,output,block_labeling] || [cfg_true output,block_labeling]} {
        save_block -as ${design_name}/clock_opt_cts
        handle_info "Block saved: ${design_name}/clock_opt_cts"
    }

    set_svf -off
    handle_info "CTS design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: timing/QoR/clock_qor/skew, design/util/power, congestion, write_qor_data
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS reports..."

    set max_paths [cfg_get common,analysis,max_paths [cfg_get analysis,max_paths 100]]
    if {$max_paths eq ""} { set max_paths 100 }

    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths $max_paths -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min -nosplit
    }

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary -nosplit }

    redirect -file $::REPORTS_DIR/report_clock_qor.rpt { report_clock_qor }
    redirect -file $::REPORTS_DIR/report_clock_timing.setup.rpt {
        report_clock_timing -type summary -scenarios [all_scenarios]
    }
    redirect -file $::REPORTS_DIR/report_clock_timing.skew.rpt {
        report_clock_timing -type skew -scenarios [all_scenarios]
    }

    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }
    redirect -file $::REPORTS_DIR/report_threshold_voltage_group.rpt { report_threshold_voltage_group }
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label clock_opt_cts -output $run_dir/qor_data
    }

    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "CTS reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Execute all registered flow_procs in definition order
# ==============================================================================
flow_exec_all

exit
