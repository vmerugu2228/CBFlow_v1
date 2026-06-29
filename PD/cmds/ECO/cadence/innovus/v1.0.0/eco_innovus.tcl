#!/usr/bin/env tclsh
# CBFlow ECO - Cadence Innovus
# Mirrors the FC counterpart at PD/cmds/ECO/synopsys/fc/v1.0.0/eco_fc.tcl
# (FC-RM Y-2026.03 ECO recipe). Cadence-Innovus command equivalents used:
#   restoreDesign / optDesign -postRoute / ecoDesign / placeECOInsts /
#   ecoRoute / addFiller / globalNetConnect / saveDesign.

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
# Innovus equivalent of FC's open_lib + copy_block + link_block:
# restoreDesign of the input db, or read_verilog + read_def + read_sdc.
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for ECO ($::eco_type)..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    if {[info exists eco(input,db)] && $eco(input,db) ne ""} {
        # Preferred: restore from a saved Innovus design database
        handle_info "restoreDesign $eco(input,db) $design_name"
        restoreDesign $eco(input,db) $design_name
    } else {
        # Fallback: rebuild from RTL + DEF + SDC + libs
        if {[info exists eco(input,netlist)] && $eco(input,netlist) ne ""} {
            handle_info "read_verilog $eco(input,netlist)"
            read_verilog $eco(input,netlist)
        }
        if {[info exists project(top_module)]} {
            handle_info "set_top_module $project(top_module)"
            set_top_module $project(top_module)
        }
        if {[info exists eco(input,def_file)] && $eco(input,def_file) ne ""} {
            handle_info "defIn $eco(input,def_file)"
            defIn $eco(input,def_file)
        }
        if {[info exists eco(input,sdc)] && $eco(input,sdc) ne ""} {
            handle_info "read_sdc $eco(input,sdc)"
            read_sdc $eco(input,sdc)
        }
    }

    handle_info "Design loaded for ECO ($::eco_type)"
}

# ==============================================================================
# flow_proc: configure_eco
# Innovus equivalents: setExtractRCMode (RC engine), setOptMode (PBA/post-route),
# setAnalysisViewActiveStatus (scenario activation), checkPlace + verifyConnectivity
# ==============================================================================
flow_proc configure_eco {
    handle_info "Configuring ECO settings..."
    global eco tech

    # RC extraction engine — default StarXt (Innovus equivalent of FC's fusion_adv)
    set extraction_mode "starxt"
    if {[info exists eco(eco,extraction_mode)]} { set extraction_mode $eco(eco,extraction_mode) }
    handle_info "setExtractRCMode -engine $extraction_mode -effortLevel signoff"
    setExtractRCMode -engine $extraction_mode -effortLevel signoff

    # Post-route mode (always true for ECO; ECO modifies a routed design)
    setOptMode -postRoute true

    # PBA mode for timing ECO
    if {$::eco_type eq "timing"} {
        set pba_mode "path"
        if {[info exists eco(eco,pba_mode)]} { set pba_mode $eco(eco,pba_mode) }
        if {$pba_mode ne ""} {
            handle_info "setOptMode -pbaMode $pba_mode"
            setOptMode -pbaMode $pba_mode
        }
    }

    # Activate ECO analysis views (Innovus's MMMC scenarios are analysis_views)
    if {[info exists eco(eco,active_scenarios)] && $eco(eco,active_scenarios) ne ""} {
        foreach view $eco(eco,active_scenarios) {
            handle_info "setAnalysisViewActiveStatus -view $view -setup true -hold true"
            setAnalysisViewActiveStatus -view $view -setup true -hold true
        }
    }

    # User pre-ECO script
    if {[info exists eco(common,eco_pre_script)] && [file exists $eco(common,eco_pre_script)]} {
        source $eco(common,eco_pre_script)
    }

    # Pre-ECO sanity reports
    redirect $::REPORTS_DIR/pre_eco.checkPlace { checkPlace }
    redirect $::REPORTS_DIR/pre_eco.verifyConnectivity { verifyConnectivity -type all }

    handle_info "ECO configuration completed (type=$::eco_type)"
}

# ==============================================================================
# flow_proc: detect_fillers
# Innovus: deleteFiller -prefix to remove existing fillers before ECO.
# ==============================================================================
flow_proc detect_fillers {
    handle_info "Detecting filler cells..."
    global eco tech

    set ::had_fillers false
    set ::had_metal_fill false

    set filler_prefix "FILL"
    if {[info exists eco(eco,filler_cell_prefix)]} { set filler_prefix $eco(eco,filler_cell_prefix) }

    # If any filler instances exist, remove them so ECO can place new cells
    set _n [llength [dbGet -p2 top.insts.cell.name ${filler_prefix}* -e]]
    if {$_n > 0} {
        set ::had_fillers true
        handle_info "Removing $_n filler cells (prefix=${filler_prefix}) before ECO"
        deleteFiller -prefix $filler_prefix
    }

    # Metal fill detection (Innovus stores as METAL_FILL_*)
    set _mf [llength [dbGet -p2 top.fPlan.fills -e]]
    if {$_mf > 0} {
        set ::had_metal_fill true
        handle_info "Metal fill detected ($_mf) — will reinsert after ECO"
    }

    handle_info "Filler detection completed (fillers=$::had_fillers, metal_fill=$::had_metal_fill)"
}

# ==============================================================================
# flow_proc: apply_eco
# Innovus: optDesign -postRoute -hold/-setup for timing ECO
#          ecoDesign <reports> <verilog> for functional ECO
# ==============================================================================
flow_proc apply_eco {
    handle_info "Applying $::eco_type ECO..."
    global eco flow

    if {$::eco_type eq "timing"} {
        # Timing ECO: post-route optDesign sweeps
        set _opt "optDesign -postRoute"
        if {[info exists eco(eco,recipe)] && $eco(eco,recipe) ne ""} {
            # Recipe-style: append the user's recipe keywords
            append _opt " $eco(eco,recipe)"
        } else {
            # Default sweep: setup → hold → drv → leakage
            append _opt " -setup -hold -drv"
        }
        if {[info exists eco(eco,custom_options)] && $eco(eco,custom_options) ne ""} {
            append _opt " $eco(eco,custom_options)"
        }
        handle_info "Running: $_opt"
        eval $_opt

        # User-provided timing ECO change file (alternative to optDesign sweep)
        if {[info exists eco(input,change_file)] && [file exists $eco(input,change_file)]} {
            handle_info "Sourcing timing ECO change file: $eco(input,change_file)"
            source $eco(input,change_file)
        }

    } elseif {$::eco_type eq "functional"} {
        # Functional ECO: ecoDesign generates physical changes from a new verilog
        if {[info exists eco(input,eco_verilog)] && [file exists $eco(input,eco_verilog)]} {
            handle_info "ecoDesign with new verilog: $eco(input,eco_verilog)"
            ecoDesign -reportDir $::REPORTS_DIR/ecoDesign \
                      -reportFilePrefix eco \
                      $eco(input,eco_verilog)

            # The resulting changes are committed in-memory; downstream
            # placeECOInsts + ecoRoute pick them up.

        } elseif {[info exists eco(input,change_file)] && [file exists $eco(input,change_file)]} {
            handle_info "Sourcing functional ECO change file: $eco(input,change_file)"
            source $eco(input,change_file)
        }
    }

    handle_info "$::eco_type ECO applied"
}

# ==============================================================================
# flow_proc: place_eco_cells
# Innovus: placeECOInsts (or refinePlace -eco) for placing newly-added cells.
# ==============================================================================
flow_proc place_eco_cells {
    handle_info "Placing ECO cells..."
    global eco

    set eco_mode "mpi"
    if {[info exists eco(eco,mode)]} { set eco_mode $eco(eco,mode) }

    if {$eco_mode eq "freeze_silicon"} {
        # Freeze-silicon analog: minimal-displacement legalization
        handle_info "Freeze-silicon mode: refinePlace -eco -isMinDistEco true"
        refinePlace -eco -isMinDistEco true
    } else {
        # MPI mode: placeECOInsts then refinePlace to legalize
        handle_info "placeECOInsts"
        placeECOInsts
        handle_info "refinePlace -eco -preserveRouting true"
        refinePlace -eco -preserveRouting true
    }

    if {[info exists eco(eco,legalize_placement)] && [string is true -strict $eco(eco,legalize_placement)]} {
        redirect $::REPORTS_DIR/checkPlace.post_place { checkPlace }
    }

    handle_info "ECO cell placement completed"
}

# ==============================================================================
# flow_proc: route_eco_nets
# Innovus: ecoRoute (native ECO router) + optional incremental routeDesign.
# ==============================================================================
flow_proc route_eco_nets {
    handle_info "Routing ECO nets..."
    global eco

    handle_info "ecoRoute"
    ecoRoute

    if {[info exists eco(eco,incr_route_post)] && [string is true -strict $eco(eco,incr_route_post)]} {
        handle_info "routeDesign -incremental for DRC fix"
        routeDesign -incremental
    }

    handle_info "ECO net routing completed"
}

# ==============================================================================
# flow_proc: reinsert_fillers
# Innovus: addFiller + addMetalFill (after ECO) if they existed pre-ECO.
# ==============================================================================
flow_proc reinsert_fillers {
    handle_info "Reinserting filler cells..."
    global eco tech

    if {$::had_fillers} {
        set _cmd "addFiller"
        if {[info exists tech(filler_cells)] && $tech(filler_cells) ne ""} {
            append _cmd " -cell $tech(filler_cells)"
        }
        if {[info exists eco(eco,filler_cell_prefix)]} {
            append _cmd " -prefix $eco(eco,filler_cell_prefix)"
        } else {
            append _cmd " -prefix FILL"
        }
        handle_info "Running: $_cmd"
        eval $_cmd
        handle_info "Filler cells reinserted"
    } else {
        handle_info "No fillers existed pre-ECO, skipping reinsertion"
    }

    if {$::had_metal_fill} {
        handle_info "addMetalFill -layer ALL (auto-eco threshold)"
        catch { addMetalFill -layer ALL }
        handle_info "Metal fill reinserted"
    }

    handle_info "Filler reinsertion completed"
}

# ==============================================================================
# flow_proc: post_eco
# Innovus: globalNetConnect, post-ECO sanity checks, user post-script.
# ==============================================================================
flow_proc post_eco {
    handle_info "Running post-ECO tasks..."
    global eco

    handle_info "globalNetConnect"
    globalNetConnect

    redirect $::REPORTS_DIR/post_eco.checkPlace { checkPlace }
    redirect $::REPORTS_DIR/post_eco.verifyConnectivity { verifyConnectivity -type all }

    if {[info exists eco(common,eco_post_script)] && [file exists $eco(common,eco_post_script)]} {
        source $eco(common,eco_post_script)
    }

    handle_info "Post-ECO tasks completed"
}

# ==============================================================================
# flow_proc: save_design
# Innovus: saveDesign (creates <name>.innovus.dat directory).
# ==============================================================================
flow_proc save_design {
    handle_info "Saving ECO design..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    set _db "$::OUTPUTS_DIR/db/${design_name}_${::eco_type}_eco.innovus.dat"
    file mkdir [file dirname $_db]
    handle_info "saveDesign $_db"
    saveDesign $_db

    handle_info "ECO design saved: $_db"
}

# ==============================================================================
# flow_proc: generate_reports
# Innovus: reportTiming, report_qor, reportPower, reportGate
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating ECO reports..."
    global eco

    set max_paths [expr {[info exists eco(analysis,max_paths)] ? $eco(analysis,max_paths) : 100}]

    # Timing
    redirect $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -nworst 1 -max_paths $max_paths -path_type full_clock_expanded
    }
    redirect $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -nworst 1 -max_paths $max_paths -hold
    }

    # QoR
    redirect $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary }

    # Design + Power
    redirect $::REPORTS_DIR/report_design.rpt { reportGate -summary }
    redirect $::REPORTS_DIR/report_power.rpt { reportPower -summary }

    # Congestion + DRC summary
    redirect $::REPORTS_DIR/report_congestion.rpt { reportCongestion }
    redirect $::REPORTS_DIR/report_drc.rpt {
        verify_drc -reportDir $::REPORTS_DIR/drc -limit 100
    }

    handle_info "ECO reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Execute all registered flow_procs in definition order
# ==============================================================================
flow_exec_all

exit
