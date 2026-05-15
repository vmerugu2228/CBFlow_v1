#!/usr/bin/env tclsh
# CBFlow PNR signoff1 - Synopsys Fusion Compiler | PNR signoff1
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PNR/signoff1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR signoff1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/signoff1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source -e $mmmc_config_file }

# ==============================================================================
# flow_proc: insert_filler
# Description: Insert filler cells for DRC cleanliness and well-tie continuity
# ==============================================================================
flow_proc insert_filler {
    handle_info "Checking filler cell insertion settings..."
    global pnr tech

    if {[info exists fc(signoff,insert_filler)] && $fc(signoff,insert_filler)} {
        # Build filler cell list from tech config
        if {[info exists tech(cells,filler)] && $tech(cells,filler) ne ""} {
            handle_info "Inserting filler cells: $tech(cells,filler)"
            set filler_cmd "create_stdcell_fillers -lib_cells \[get_lib_cells $tech(cells,filler)\]"
            eval $filler_cmd
        } else {
            handle_warning "fc(signoff,insert_filler) is true but tech(cells,filler) not specified"
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

    if {[info exists fc(signoff,insert_decap)] && $fc(signoff,insert_decap)} {
        if {[info exists tech(cells,decap)] && $tech(cells,decap) ne ""} {
            handle_info "Inserting decap cells: $tech(cells,decap)"
            set decap_cmd "create_stdcell_fillers -lib_cells \[get_lib_cells $tech(cells,decap)\]"
            eval $decap_cmd
        } else {
            handle_warning "fc(signoff,insert_decap) is true but tech(cells,decap) not specified"
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
    if {[info exists fc(signoff,drc_runset)] && [file exists $fc(signoff,drc_runset)]} {
        set_app_options -name signoff.check_drc.runset -value $fc(signoff,drc_runset)
    }

    # Configure layer mapping for signoff
    if {[info exists tech(gds_layer_map)] && $tech(gds_layer_map) ne ""} {
        set_app_options -name signoff.physical.layer_map_file -value $tech(gds_layer_map)
    }
    if {[info exists fc(signoff,stream_files_for_merge)] && $fc(signoff,stream_files_for_merge) ne ""} {
        set_app_options -name signoff.physical.merge_stream_files -value $fc(signoff,stream_files_for_merge)
    }

    # Save block before ICV (reads from disk)
    save_block

    # Run signoff_check_drc
    if {[info exists fc(signoff,drc_runset)] && [file exists $fc(signoff,drc_runset)]} {
        handle_info "Running signoff_check_drc"
        set drc_cmd "signoff_check_drc"
        if {[info exists fc(signoff,drc_select_rules)] && $fc(signoff,drc_select_rules) ne ""} {
            lappend drc_cmd -select_rules $fc(signoff,drc_select_rules)
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

    if {[info exists fc(signoff,fix_drc)] && $fc(signoff,fix_drc)} {
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

    if {[info exists fc(signoff,metal_fill)] && $fc(signoff,metal_fill)} {
        # Configure metal fill runset if provided
        if {[info exists fc(signoff,metal_fill_runset)] && [file exists $fc(signoff,metal_fill_runset)]} {
            set_app_options -name signoff.create_metal_fill.runset -value $fc(signoff,metal_fill_runset)
        }

        # Configure timing-driven metal fill
        set fill_cmd "signoff_create_metal_fill"
        if {[info exists fc(signoff,metal_fill_track_based)] && $fc(signoff,metal_fill_track_based) ne "off"} {
            lappend fill_cmd -track_fill $fc(signoff,metal_fill_track_based)
            if {$fc(signoff,metal_fill_track_based) ne "generic"} {
                lappend fill_cmd -fill_all_tracks true
            }
        }
        if {[info exists fc(signoff,metal_fill_timing_threshold)] && $fc(signoff,metal_fill_timing_threshold) ne ""} {
            lappend fill_cmd -timing_preserve_setup_slack_threshold $fc(signoff,metal_fill_timing_threshold)
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
    if {[info exists fc(signoff,drc_runset)] && [file exists $fc(signoff,drc_runset)]} {
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

    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as $fc(common,design_name)/signoff
        handle_info "Block saved as $fc(common,design_name)/signoff"
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
    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

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
            -label chip_finish -output $run_dir/qor_data
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Signoff reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/PNR/signoff1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.signoff.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
