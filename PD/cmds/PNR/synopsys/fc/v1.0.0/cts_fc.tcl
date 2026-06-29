#!/usr/bin/env tclsh
# CBFlow PNR cts1 - Synopsys Fusion Compiler | PNR cts1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts"
set NODE_NAME "cts1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: configure_cts
# Description: Configure CTS options, NDR rules, and clock constraints
# ==============================================================================
flow_proc configure_cts {
    handle_info "Configuring CTS options..."
    global pnr tech

    # Set QoR strategy for CTS stage
    if {[info exists pnr(compile,qor_version)] && $pnr(compile,qor_version) ne ""} {
        set_app_options -name flow.set_qor_strategy.version -value $pnr(compile,qor_version)
    }
    set set_qor_strategy_cmd "set_qor_strategy -stage cts"
    if {[info exists pnr(compile,qor_metric)] && $pnr(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $pnr(compile,qor_metric)
    }
    if {[info exists pnr(compile,qor_mode)] && $pnr(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $pnr(compile,qor_mode)
    }
    if {[info exists pnr(compile,reduced_effort)] && $pnr(compile,reduced_effort) ne "" && [string is true -strict $pnr(compile,reduced_effort)]} {
        lappend set_qor_strategy_cmd -reduced_effort
    }
    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set instance name prefixes
    set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
    set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_

    # Set active scenarios for CTS step
    if {[info exists pnr(cts,active_scenarios)] && $pnr(cts,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $pnr(cts,active_scenarios)
    }

    # Lib cell purpose for CTS
    if {[info exists pnr(cts,ref_cells)] && $pnr(cts,ref_cells) ne ""} {
        set_lib_cell_purpose -include cts $pnr(cts,ref_cells)
        handle_info "CTS reference cells: $pnr(cts,ref_cells)"
    }
    if {[info exists pnr(cts,exclude_cells)] && $pnr(cts,exclude_cells) ne ""} {
        set_lib_cell_purpose -exclude cts $pnr(cts,exclude_cells)
    }

    # Configure NDR (non-default routing) rules for clock nets and mark trees
    if {[info exists pnr(cts,ndr_rule)] && $pnr(cts,ndr_rule) ne ""} {
        handle_info "Applying clock NDR rule: $pnr(cts,ndr_rule)"
        mark_clock_trees -routing_rules
    }

    # Antenna rules
    if {[info exists tech(antenna_rule_file)] && [file exists $tech(antenna_rule_file)]} {
        handle_info "Reading antenna rules: $tech(antenna_rule_file)"
        source $tech(antenna_rule_file)
    }

    # CTS primary corner override
    if {[info exists pnr(cts,primary_corner)] && $pnr(cts,primary_corner) ne ""} {
        handle_info "Setting cts.compile.primary_corner to $pnr(cts,primary_corner)"
        set_app_options -name cts.compile.primary_corner -value $pnr(cts,primary_corner)
    }

    handle_info "CTS configuration completed"
}

# ==============================================================================
# flow_proc: construct_mscts
# Description: Optional Multi-Source CTS (MSCTS / "multipoint CTS") step.
#              Gated on `pnr(cts,mpcts) == "true"`. When enabled, stages the
#              user's MSCTS_* settings from the cascade and sources the
#              standalone mscts_fc.tcl recipe (1:1 port of FC-RM Y-2026.03
#              examples/mscts.regular.tcl).
#
# Position in flow: AFTER configure_cts, BEFORE build_clock_trees. The
#                   subsequent `clock_opt -from build_clock` then picks up
#                   the tap assignment set via
#                   set_multisource_clock_tap_options at the end of MSCTS.
#
# Note vs FC-RM:    FC-RM places MSCTS construction at the END of place_opt
#                   so the H-tree exists before clock_opt_cts starts.
#                   Per user direction, CBflow runs it as the first sub-step
#                   of the cts1 node instead. Same net result for
#                   `clock_opt`'s view of taps. If timing closure suffers
#                   in production, the same flow_proc can be lifted into
#                   place_fc.tcl with no other change.
# ==============================================================================
flow_proc construct_mscts {
    global pnr
    # Gate. Default (key absent or anything other than "true") = no-op,
    # so existing PNR runs are unchanged.
    set _on false
    if {[info exists pnr(cts,mpcts)]} {
        if {[string is true -strict $pnr(cts,mpcts)]} { set _on true }
    }
    if {!$_on} {
        handle_info "MSCTS / multipoint CTS disabled (pnr(cts,mpcts) != true) — skipping"
        return
    }

    handle_info "MSCTS / multipoint CTS enabled — staging inputs from pnr(cts,mpcts,*)"

    # Stage cascade values into the FC-RM-canonical MSCTS_* globals the
    # standalone recipe reads. Keeping the FC-RM names means mscts_fc.tcl
    # stays a 1:1 port — no rename layer between CBflow's config keys
    # and the recipe.
    set ::MSCTS_CLOCK                     [_pnr_cts_mpcts_get clock                     ""]
    set ::MSCTS_SOURCE                    [_pnr_cts_mpcts_get source                    ""]
    set ::MSCTS_TOPOLOGY                  [_pnr_cts_mpcts_get topology                  "htree"]
    set ::MSCTS_PITCH                     [_pnr_cts_mpcts_get pitch                     "100"]
    set ::MSCTS_TAP_DRIVER_LIB_CELLS      [_pnr_cts_mpcts_get tap_driver_lib_cells      ""]
    set ::MSCTS_NET                       [_pnr_cts_mpcts_get net                       ""]
    set ::MSCTS_TAP_DRIVER_MAX_DISPLACEMENT [_pnr_cts_mpcts_get tap_driver_max_displacement ""]
    set ::MSCTS_TAP_BOUNDARY              [_pnr_cts_mpcts_get tap_boundary              ""]
    set ::MSCTS_MACRO_KEEPOUT             [_pnr_cts_mpcts_get macro_keepout             "false"]
    # htree-mode inputs
    set ::MSCTS_HTREE_LIB_CELLS           [_pnr_cts_mpcts_get htree_lib_cells           ""]
    set ::MSCTS_HTREE_NDR_RULE_NAME       [_pnr_cts_mpcts_get htree_ndr_rule_name       ""]
    set ::MSCTS_HTREE_MIN_ROUTING_LAYER   [_pnr_cts_mpcts_get htree_min_routing_layer   ""]
    set ::MSCTS_HTREE_MAX_ROUTING_LAYER   [_pnr_cts_mpcts_get htree_max_routing_layer   ""]
    # subtree_only-mode inputs
    set ::MSCTS_MESH_NET                  [_pnr_cts_mpcts_get mesh_net                  ""]
    set ::MSCTS_MESH_NET_PORT             [_pnr_cts_mpcts_get mesh_net_port             ""]
    set ::MSCTS_MESH_NET_PORT_TRANSITION  [_pnr_cts_mpcts_get mesh_net_port_transition  ""]
    set ::MSCTS_MESH_NET_PORT_DELAY       [_pnr_cts_mpcts_get mesh_net_port_delay       ""]
    set ::MSCTS_INPUT_TRANSITION          [_pnr_cts_mpcts_get input_transition          ""]
    set ::MSCTS_NET_DELAY                 [_pnr_cts_mpcts_get net_delay                 ""]
    set ::TCL_USER_MESH_ANNOTATION_SCRIPT [_pnr_cts_mpcts_get user_mesh_annotation_script ""]

    # Source the standalone recipe. It validates inputs internally and
    # raises `return -code error` if anything required is missing, which
    # propagates up through this flow_proc and aborts the cts1 stage —
    # exactly what we want.
    set _recipe "$::env(FLOW_DIR)/cmds/PNR/synopsys/fc/$::env(TOOL_VERSION)/mscts_fc.tcl"
    if {![file exists $_recipe]} {
        # Defensive fallback for TOOL_VERSION mismatch — try the version
        # that the running handler was loaded from.
        set _recipe "[file dirname [info script]]/mscts_fc.tcl"
    }
    handle_info "Sourcing MSCTS recipe: $_recipe"
    source $_recipe
    handle_info "MSCTS construction completed"
}

# Helper: read a `pnr(cts,mpcts,<key>)` from the resolved cascade, falling
# back to a default. Kept local to this file because the only other reader
# of these knobs is this flow_proc.
proc _pnr_cts_mpcts_get {key default} {
    global pnr
    set full "cts,mpcts,$key"
    if {[info exists pnr($full)] && $pnr($full) ne ""} {
        return $pnr($full)
    }
    return $default
}

# ==============================================================================
# flow_proc: build_clock_trees
# Description: Build clock trees via clock_opt build_clock phase
# ==============================================================================
flow_proc build_clock_trees {
    handle_info "Building clock trees..."
    global pnr

    # Check and apply relaxed clock transition for better CTS convergence
    handle_info "Running check_clock_transition -threshold 0.15 -apply_max_transition"
    check_clock_transition -threshold 0.15 -apply_max_transition

    # Build clock tree
    handle_info "Running clock_opt -from build_clock -to build_clock"
    clock_opt -from build_clock -to build_clock

    # Save intermediate state
    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling) ne "" && [string is true -strict $pnr(output,block_labeling)]} {
        save_block -as $pnr(common,design_name)/clock_opt_cts_build_clock
    }

    # Restore original clock transition constraint
    restore_clock_transition

    handle_info "Clock tree build completed"
}

# ==============================================================================
# flow_proc: route_clock_nets
# Description: Route clock nets via clock_opt route_clock phase
# ==============================================================================
flow_proc route_clock_nets {
    handle_info "Routing clock nets..."

    handle_info "Running clock_opt -from route_clock -to route_clock"
    clock_opt -from route_clock -to route_clock

    # Redundant via insertion on clock nets if enabled
    if {[info exists ::pnr(cts,redundant_via)] && $::pnr(cts,redundant_via)} {
        handle_info "Running add_redundant_vias for CTS"
        add_redundant_vias
    }

    # Enable AOCV analysis after CTS if configured
    if {[info exists ::pnr(cts,enable_aocv)] && $::pnr(cts,enable_aocv)} {
        set_app_options -name time.aocvm_enable_analysis -value true
        handle_info "AOCV analysis enabled"
    }

    # Create shields if enabled
    if {[info exists ::pnr(cts,enable_shields)] && $::pnr(cts,enable_shields)} {
        handle_info "Creating clock shields..."
        set create_shields_cmd "create_shields"
        if {[info exists ::pnr(cts,shields_ground_net)] && $::pnr(cts,shields_ground_net) ne ""} {
            lappend create_shields_cmd -with_ground $::pnr(cts,shields_ground_net)
        }
        eval $create_shields_cmd
    }

    handle_info "Clock net routing completed"
}

# ==============================================================================
# flow_proc: propagate_clocks
# Description: Propagate clocks to inactive scenarios and connect PG nets
# ==============================================================================
flow_proc propagate_clocks {
    handle_info "Propagating clocks and connecting PG nets..."

    # Connect PG nets
    connect_pg_net

    # Run check_routes to save updated routing DRC to the block
    redirect -file $::REPORTS_DIR/check_routes.rpt {
        check_routes -open_net false
    }

    handle_info "Clock propagation and PG connection completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after CTS
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling) ne "" && [string is true -strict $pnr(output,block_labeling)]} {
        save_block -as $pnr(common,design_name)/cts
        handle_info "Block saved as $pnr(common,design_name)/cts"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive CTS reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

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

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "CTS reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
