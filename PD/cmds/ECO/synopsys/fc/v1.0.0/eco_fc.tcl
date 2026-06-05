#!/usr/bin/env tclsh
# CBFlow ECO - Synopsys Fusion Compiler (FC-RM Y-2026.03)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
set STAGE_NAME "eco"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from previous step, link_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for ECO ($::eco_type)..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists eco(common,design_lib_name)] ? $eco(common,design_lib_name) : "${design_name}.nlib"}]

    # FC-RM: Determine previous step based on ECO type
    set prev_step "signoff"
    if {[info exists eco(input,from_block)]} { set prev_step $eco(input,from_block) }

    open_lib $lib_name
    set target_step "${::eco_type}_eco"
    copy_block -from ${design_name}/${prev_step} -to ${design_name}/${target_step}
    current_block ${design_name}/${target_step}
    link_block

    # FC-RM: set_svf
    set_svf $::OUTPUTS_DIR/${design_name}_${target_step}.svf

    handle_info "Design loaded: ${design_name}/${target_step}"
}

# ==============================================================================
# flow_proc: configure_eco
# FC-RM: Extraction mode, PBA mode, scenario activation, pre-checks
# ==============================================================================
flow_proc configure_eco {
    handle_info "Configuring ECO settings..."
    global eco tech

    # FC-RM: Set extraction mode (fusion_adv for timing ECO)
    set extraction_mode "fusion_adv"
    if {[info exists eco(eco,extraction_mode)]} { set extraction_mode $eco(eco,extraction_mode) }
    set_app_options -name extract.starrc_mode -value $extraction_mode
    handle_info "Extraction mode: $extraction_mode"

    # FC-RM: StarRC config
    if {[info exists eco(eco,starrc_config)] && $eco(eco,starrc_config) ne ""} {
        if {[file exists $eco(eco,starrc_config)]} {
            set config [file normalize $eco(eco,starrc_config)]
            set_starrc_in_design -config $config
            handle_info "StarRC config: $config"
        }
    }

    # FC-RM: Set PBA mode for timing ECO
    if {$::eco_type eq "timing"} {
        set pba_mode "path"
        if {[info exists eco(eco,pba_mode)]} { set pba_mode $eco(eco,pba_mode) }
        if {$pba_mode ne ""} {
            set_app_options -name time.pba_optimization_mode -value $pba_mode
            if {$pba_mode eq "exhaustive"} {
                set_app_options -name time.pba_exhaustive_endpoint_path_limit -value 16
            }
            handle_info "PBA mode: $pba_mode"
        }
    }

    # FC-RM: Activate ECO scenarios
    if {[info exists eco(eco,active_scenarios)] && $eco(eco,active_scenarios) ne ""} {
        set_scenario_status -active false [get_scenarios -filter active]
        set_scenario_status -active true $eco(eco,active_scenarios)
        handle_info "Active scenarios: $eco(eco,active_scenarios)"
    }

    # FC-RM: Non-persistent settings
    if {[info exists eco(common,non_persistent_script)] && [file exists $eco(common,non_persistent_script)]} {
        source -e $eco(common,non_persistent_script)
    }

    # FC-RM: User pre-ECO script
    if {[info exists eco(common,eco_pre_script)] && [file exists $eco(common,eco_pre_script)]} {
        source -e $eco(common,eco_pre_script)
    }

    # FC-RM: Pre-ECO reports and checks
    redirect -file $::REPORTS_DIR/report_app_options.start { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/pre_eco.check_legality { check_legality }
    redirect -file $::REPORTS_DIR/pre_eco.check_routes { check_routes }

    handle_info "ECO configuration completed (type=$::eco_type)"
}

# ==============================================================================
# flow_proc: detect_fillers
# FC-RM: Detect and remove filler cells before ECO (they'll be reinserted after)
# ==============================================================================
flow_proc detect_fillers {
    handle_info "Detecting filler cells..."
    global eco tech

    set ::had_fillers false
    set ::had_metal_fill false

    # FC-RM: Detect filler cell prefix
    set filler_prefix "FILL"
    if {[info exists eco(eco,filler_cell_prefix)]} { set filler_prefix $eco(eco,filler_cell_prefix) }

    # FC-RM: Check if fillers exist and remove them
    catch {
        set filler_cells [get_flat_cells -filter "ref_name=~${filler_prefix}*"]
        if {[sizeof_collection $filler_cells] > 0} {
            set ::had_fillers true
            handle_info "Removing [sizeof_collection $filler_cells] filler cells before ECO"
            remove_cells $filler_cells
        }
    }

    # FC-RM: Check if metal fill exists
    catch {
        set metal_fill [get_shapes -filter "shape_use==metal_fill" -quiet]
        if {[sizeof_collection $metal_fill] > 0} {
            set ::had_metal_fill true
            handle_info "Metal fill detected — will reinsert after ECO"
        }
    }

    handle_info "Filler detection completed (fillers=$::had_fillers, metal_fill=$::had_metal_fill)"
}

# ==============================================================================
# flow_proc: apply_eco
# FC-RM: timing_eco.tcl (eco_opt) OR functional_eco.tcl (eco_netlist)
#         based on eco(eco,type)
# ==============================================================================
flow_proc apply_eco {
    handle_info "Applying $::eco_type ECO..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    if {$::eco_type eq "timing"} {
        # ── TIMING ECO ────────────────────────────────────────────────────────
        # FC-RM: eco_opt with PrimeClosure-Fusion or PT engine

        set engine "smsa"
        if {[info exists eco(eco,engine)]} { set engine $eco(eco,engine) }

        if {$engine eq "smsa" || $engine eq "PrimeClosure-Fusion"} {
            # FC-RM: eco_opt with SMSA (PrimeClosure-Fusion)
            handle_info "Running eco_opt with PrimeClosure-Fusion engine"
            set_eco_opt_options -eco_engine smsa

            set eco_cmd "eco_opt"
            if {[info exists eco(eco,recipe)] && $eco(eco,recipe) ne ""} {
                lappend eco_cmd -recipe $eco(eco,recipe)
            }
            if {[info exists eco(eco,custom_options)] && $eco(eco,custom_options) ne ""} {
                append eco_cmd " $eco(eco,custom_options)"
            }
            handle_info "Running: $eco_cmd"
            eval $eco_cmd

        } elseif {$engine eq "pt" || $engine eq "pteco"} {
            # FC-RM: eco_opt with PT engine
            handle_info "Running eco_opt with PT engine"
            set_eco_opt_options -eco_engine pteco

            if {[info exists eco(eco,pt_exec_path)] && $eco(eco,pt_exec_path) ne ""} {
                set_pt_options -pt_exec $eco(eco,pt_exec_path)
            }

            # FC-RM: Pre-ECO PT QoR check
            redirect -file $::REPORTS_DIR/check_pt_qor.pre_eco { check_pt_qor }

            set eco_cmd "eco_opt"
            if {[info exists eco(eco,custom_options)] && $eco(eco,custom_options) ne ""} {
                append eco_cmd " $eco(eco,custom_options)"
            }
            handle_info "Running: $eco_cmd"
            eval $eco_cmd

            # FC-RM: Post-ECO PT QoR check
            redirect -file $::REPORTS_DIR/check_pt_qor.post_eco { check_pt_qor }
        }

        # FC-RM: User-provided timing ECO change file (alternative to eco_opt)
        if {[info exists eco(input,change_file)] && $eco(input,change_file) ne "" && [file exists $eco(input,change_file)]} {
            handle_info "Sourcing timing ECO change file: $eco(input,change_file)"
            source -e $eco(input,change_file)
        }

    } elseif {$::eco_type eq "functional"} {
        # ── FUNCTIONAL ECO ────────────────────────────────────────────────────
        # FC-RM: eco_netlist -by_verilog_file

        if {[info exists eco(input,eco_verilog)] && $eco(input,eco_verilog) ne ""} {
            if {[file exists $eco(input,eco_verilog)]} {
                handle_info "Running functional ECO with: $eco(input,eco_verilog)"

                # FC-RM: eco_netlist generates eco_changes.tcl
                set changes_file "$::OUTPUTS_DIR/eco_changes.tcl"
                eco_netlist -by_verilog_file $eco(input,eco_verilog) -write_changes $changes_file

                # FC-RM: Determine ECO mode
                set eco_mode "mpi"
                if {[info exists eco(eco,mode)]} { set eco_mode $eco(eco,mode) }

                if {$eco_mode eq "freeze_silicon"} {
                    # FC-RM: Freeze-silicon mode
                    handle_info "Freeze-silicon mode: enable + source changes + place_freeze_silicon"
                    set_app_options -name design.freeze_silicon.enabled -value true
                    if {[file exists $changes_file]} { source -e $changes_file }
                    place_freeze_silicon
                } else {
                    # FC-RM: MPI mode (minimum physical impact)
                    handle_info "MPI mode: source changes + place_eco_cells + legalize"
                    if {[file exists $changes_file]} { source -e $changes_file }
                }
            } else {
                handle_error "Functional ECO verilog not found: $eco(input,eco_verilog)"
            }
        } elseif {[info exists eco(input,change_file)] && $eco(input,change_file) ne "" && [file exists $eco(input,change_file)]} {
            # FC-RM: User-provided functional change file
            handle_info "Sourcing functional ECO change file: $eco(input,change_file)"
            source -e $eco(input,change_file)
        }
    }

    handle_info "$::eco_type ECO applied"
}

# ==============================================================================
# flow_proc: place_eco_cells
# FC-RM: place_eco_cells (coarse + legalize) or place_freeze_silicon
# ==============================================================================
flow_proc place_eco_cells {
    handle_info "Placing ECO cells..."
    global eco

    set eco_mode "mpi"
    if {[info exists eco(eco,mode)]} { set eco_mode $eco(eco,mode) }

    if {$eco_mode eq "freeze_silicon"} {
        # Already handled in apply_eco for freeze_silicon
        handle_info "Freeze-silicon placement already done in apply_eco"
    } else {
        # FC-RM: MPI two-step placement
        handle_info "Coarse placement: place_eco_cells -eco_changed_cells -no_legalize"
        place_eco_cells -eco_changed_cells -no_legalize

        handle_info "Fine legalization: place_eco_cells -eco_changed_cells -legalize_only -legalize_mode minimum_physical_impact"
        place_eco_cells -eco_changed_cells -legalize_only \
            -legalize_mode minimum_physical_impact
    }

    # FC-RM: Legalize placement if configured
    if {[info exists eco(eco,legalize_placement)] && $eco(eco,legalize_placement)} {
        redirect -file $::REPORTS_DIR/check_legality.post_place { check_legality }
    }

    handle_info "ECO cell placement completed"
}

# ==============================================================================
# flow_proc: route_eco_nets
# FC-RM: route_eco for both timing and functional ECOs
# ==============================================================================
flow_proc route_eco_nets {
    handle_info "Routing ECO nets..."
    global eco

    # FC-RM: route_eco with dangling wire utilization
    handle_info "Running route_eco"
    route_eco -utilize_dangling_wires -reroute -open_net_driven

    # FC-RM: Incremental route_detail for DRC fix
    if {[info exists eco(eco,incr_route_post)] && $eco(eco,incr_route_post)} {
        handle_info "Running incremental route_detail"
        route_detail -incremental true -initial_drc_from_input true
    }

    handle_info "ECO net routing completed"
}

# ==============================================================================
# flow_proc: reinsert_fillers
# FC-RM: Reinsert filler and decap cells after ECO (if they existed before)
# ==============================================================================
flow_proc reinsert_fillers {
    handle_info "Reinserting filler cells..."
    global eco tech

    if {$::had_fillers} {
        # FC-RM: Reinsert fillers with -post_eco flag
        if {[info exists tech(filler_sidefile)] && [file exists $tech(filler_sidefile)]} {
            source -e $tech(filler_sidefile)
        } else {
            handle_info "Running create_stdcell_fillers (post-ECO)"
            create_stdcell_fillers -lib_cells [get_lib_cells */FILL*]
        }
        handle_info "Filler cells reinserted"
    } else {
        handle_info "No fillers existed pre-ECO, skipping reinsertion"
    }

    # FC-RM: Reinsert metal fill if it existed
    if {$::had_metal_fill} {
        handle_info "Reinserting metal fill (auto_eco threshold)"
        catch {
            signoff_create_metal_fill -auto_eco \
                -timing_preserve_setup_slack_threshold 0.05
        }
        handle_info "Metal fill reinserted"
    }

    handle_info "Filler reinsertion completed"
}

# ==============================================================================
# flow_proc: post_eco
# FC-RM: connect_pg_net, check_legality, check_routes, user post-script
# ==============================================================================
flow_proc post_eco {
    handle_info "Running post-ECO tasks..."
    global eco

    # FC-RM: connect_pg_net
    connect_pg_net

    # FC-RM: Post-ECO checks
    redirect -file $::REPORTS_DIR/post_eco.check_legality { check_legality }
    redirect -file $::REPORTS_DIR/post_eco.check_routes { check_routes }

    # FC-RM: User post-ECO script
    if {[info exists eco(common,eco_post_script)] && [file exists $eco(common,eco_post_script)]} {
        source -e $eco(common,eco_post_script)
    }

    handle_info "Post-ECO tasks completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block, set_svf -off
# ==============================================================================
flow_proc save_design {
    handle_info "Saving ECO design..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists eco(output,block_labeling)] && $eco(output,block_labeling)} {
        save_block -as ${design_name}/${::eco_type}_eco
        handle_info "Block saved: ${design_name}/${::eco_type}_eco"
    }

    set_svf -off
    handle_info "ECO design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_global_timing, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating ECO reports..."
    global eco

    set max_paths [expr {[info exists eco(analysis,max_paths)] ? $eco(analysis,max_paths) : 100}]

    # FC-RM: Timing settings for post-route
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

    # FC-RM: Global timing
    redirect -file $::REPORTS_DIR/report_global_timing.rpt {
        report_global_timing -nosplit
    }

    # FC-RM: Design
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }

    # FC-RM: Power
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }

    # FC-RM: App options
    redirect -file $::REPORTS_DIR/report_app_options.end.rpt { report_app_options -non_default * }

    # FC-RM: write_qor_data
    catch {
        write_qor_data -report_list "performance host_machine report_app_options" \
            -label ${::eco_type}_eco -output $run_dir/qor_data
    }

    # FC-RM: run_end removed (not a valid FC command)
    # redirect -file $::REPORTS_DIR/run_end.rpt { run_end }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "ECO reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
