#!/usr/bin/env tclsh
# CBFlow PNR signoff1 - Synopsys Fusion Compiler | PNR signoff1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "signoff"
set NODE_NAME "signoff1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: insert_filler
# Description: Insert filler cells for DRC cleanliness and well-tie continuity
# ==============================================================================
flow_proc insert_filler {
    handle_info "Checking filler cell insertion settings..."
    global pnr tech

    if {[info exists pnr(signoff,insert_filler)] && $pnr(signoff,insert_filler) ne "" && [string is true -strict $pnr(signoff,insert_filler)]} {
        # Build filler cell list from tech config
        if {[info exists tech(cells,filler)] && $tech(cells,filler) ne ""} {
            handle_info "Inserting filler cells: $tech(cells,filler)"
            set filler_cmd "create_stdcell_fillers -lib_cells \[get_lib_cells $tech(cells,filler)\]"
            eval $filler_cmd
        } else {
            handle_warning "pnr(signoff,insert_filler) is true but tech(cells,filler) not specified"
        }

        # Connect PG nets after filler insertion
        connect_pg_net
    } else {
        handle_info "Filler cell insertion not enabled -- skipping"
    }
}

# ==============================================================================
# flow_proc: insert_decap
# Description: Insert decap cells for IR drop mitigation
# ==============================================================================
flow_proc insert_decap {
    handle_info "Checking decap cell insertion settings..."
    global pnr tech

    if {[info exists pnr(signoff,insert_decap)] && $pnr(signoff,insert_decap) ne "" && [string is true -strict $pnr(signoff,insert_decap)]} {
        if {[info exists tech(cells,decap)] && $tech(cells,decap) ne ""} {
            handle_info "Inserting decap cells: $tech(cells,decap)"
            set decap_cmd "create_stdcell_fillers -lib_cells \[get_lib_cells $tech(cells,decap)\]"
            eval $decap_cmd
        } else {
            handle_warning "pnr(signoff,insert_decap) is true but tech(cells,decap) not specified"
        }

        # Connect PG nets after decap insertion
        connect_pg_net
    } else {
        handle_info "Decap cell insertion not enabled -- skipping"
    }
}

# ==============================================================================
# flow_proc: run_drc_check
# Description: Run signoff DRC check using ICV in-design
# ==============================================================================
flow_proc run_drc_check {
    handle_info "Running signoff DRC check..."
    global pnr tech

    # Configure DRC runset
    if {[info exists pnr(signoff,drc_runset)] && [file exists $pnr(signoff,drc_runset)]} {
        set_app_options -name signoff.check_drc.runset -value $pnr(signoff,drc_runset)
    }

    # Configure layer mapping for signoff
    if {[info exists tech(gds_layer_map)] && $tech(gds_layer_map) ne ""} {
        set_app_options -name signoff.physical.layer_map_file -value $tech(gds_layer_map)
    }
    if {[info exists pnr(signoff,stream_files_for_merge)] && $pnr(signoff,stream_files_for_merge) ne ""} {
        set_app_options -name signoff.physical.merge_stream_files -value $pnr(signoff,stream_files_for_merge)
    }

    # Save block before ICV (reads from disk)
    save_block

    # Run signoff_check_drc
    if {[info exists pnr(signoff,drc_runset)] && [file exists $pnr(signoff,drc_runset)]} {
        handle_info "Running signoff_check_drc"
        set drc_cmd "signoff_check_drc"
        if {[info exists pnr(signoff,drc_select_rules)] && $pnr(signoff,drc_select_rules) ne ""} {
            lappend drc_cmd -select_rules $pnr(signoff,drc_select_rules)
        }
        eval $drc_cmd
    } else {
        handle_info "No DRC runset specified -- running check_routes instead"
        redirect -file $::REPORTS_DIR/check_routes.rpt {
            check_routes
        }
    }

    handle_info "Signoff DRC check completed"
}

# ==============================================================================
# flow_proc: fix_drc
# Description: Fix DRC violations using signoff_fix_drc
# ==============================================================================
flow_proc fix_drc {
    handle_info "Checking signoff DRC fix settings..."
    global pnr

    if {[info exists pnr(signoff,fix_drc)] && $pnr(signoff,fix_drc) ne "" && [string is true -strict $pnr(signoff,fix_drc)]} {
        handle_info "Running signoff_fix_drc"
        signoff_fix_drc
        handle_info "signoff_fix_drc completed"
    } else {
        handle_info "signoff_fix_drc not enabled -- skipping"
    }
}

# ==============================================================================
# flow_proc: create_metal_fill
# Description: Create metal fill for density rules compliance
# ==============================================================================
flow_proc create_metal_fill {
    handle_info "Checking metal fill settings..."
    global pnr tech

    if {[info exists pnr(signoff,metal_fill)] && $pnr(signoff,metal_fill) ne "" && [string is true -strict $pnr(signoff,metal_fill)]} {
        # Configure metal fill runset if provided
        if {[info exists pnr(signoff,metal_fill_runset)] && [file exists $pnr(signoff,metal_fill_runset)]} {
            set_app_options -name signoff.create_metal_fill.runset -value $pnr(signoff,metal_fill_runset)
        }

        # Configure timing-driven metal fill
        set fill_cmd "signoff_create_metal_fill"
        if {[info exists pnr(signoff,metal_fill_track_based)] && $pnr(signoff,metal_fill_track_based) ne "off"} {
            lappend fill_cmd -track_fill $pnr(signoff,metal_fill_track_based)
            if {$pnr(signoff,metal_fill_track_based) ne "generic"} {
                lappend fill_cmd -fill_all_tracks true
            }
        }
        if {[info exists pnr(signoff,metal_fill_timing_threshold)] && $pnr(signoff,metal_fill_timing_threshold) ne ""} {
            lappend fill_cmd -timing_preserve_setup_slack_threshold $pnr(signoff,metal_fill_timing_threshold)
            set_extraction_options -real_metalfill_extraction none
        }

        save_block
        handle_info "Running: $fill_cmd"
        eval $fill_cmd
        save_block

        # Set extraction options for metal fill
        set_extraction_options -real_metalfill_extraction floating -virtual_metalfill_extraction none
    } else {
        handle_info "Metal fill not enabled -- skipping"
    }
}

# ==============================================================================
# flow_proc: run_final_drc
# Description: Run final signoff DRC check after all physical finishing
# ==============================================================================
flow_proc run_final_drc {
    handle_info "Running final signoff DRC check..."
    global pnr

    # Run check_routes for final DRC summary
    redirect -file $::REPORTS_DIR/check_routes.final.rpt {
        check_routes
    }

    # Run signoff_check_drc if runset is available (post-metal-fill check)
    if {[info exists pnr(signoff,drc_runset)] && [file exists $pnr(signoff,drc_runset)]} {
        handle_info "Running final signoff_check_drc"
        signoff_check_drc -error_data POST_FINISH
    }

    # Connect PG nets final pass
    connect_pg_net

    handle_info "Final DRC check completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after signoff finishing
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling) ne "" && [string is true -strict $pnr(output,block_labeling)]} {
        save_block -as $pnr(common,design_name)/signoff
        handle_info "Block saved as $pnr(common,design_name)/signoff"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate comprehensive signoff reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating signoff reports..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    set max_paths [expr {[info exists pnr(analysis,max_paths)] ? $pnr(analysis,max_paths) : 100}]

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
    redirect -file $::REPORTS_DIR/check_routes.signoff.rpt { check_routes }

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

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Signoff reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
