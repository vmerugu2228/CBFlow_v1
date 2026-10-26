#!/usr/bin/env tclsh
# CBFlow ECO - Cadence Innovus
#
# Minimal real-world ECO flow:
#   1. load_design       — restore the routed design
#   2. source_eco_file    — eval the user's ECO ops file
#                          (eco(input,change_file), set via user_config or
#                          override_config.<node>.tcl)
#   3. legalize           — refinePlace -eco (NO opt)
#   4. eco_reroute        — ecoRoute incremental
#   5. add_fillers        — addFiller around new cells
#   6. save_design

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
# Restore the routed design from a saved Innovus db, or rebuild from ASCII
# (verilog + DEF + SDC) if no db handoff is provided.
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for ECO..."
    global eco project

    if {[info exists eco(input,db)] && $eco(input,db) ne ""} {
        set top [expr {[info exists project(top_module)] ? $project(top_module) : ""}]
        handle_info "restoreDesign $eco(input,db) $top"
        restoreDesign $eco(input,db) $top
    } else {
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

    handle_info "Design loaded"
}

# ==============================================================================
# flow_proc: source_eco_file
# Source the user's ECO ops file. The path comes from the resolved cascade —
# user_config.tcl or override_config.<node>.tcl sets eco(input,change_file).
# Hard error if absent or unreadable.
# ==============================================================================
flow_proc source_eco_file {
    handle_info "Sourcing user ECO file..."
    global eco

    if {![info exists eco(input,change_file)] || $eco(input,change_file) eq ""} {
        handle_error "eco(input,change_file) is not set — nothing to apply. Set it in user_config.tcl or override_config.<node>.tcl"
        return
    }
    if {![file exists $eco(input,change_file)]} {
        handle_error "ECO change file not found: $eco(input,change_file)"
        return
    }

    handle_info "Sourcing: $eco(input,change_file)"
    source $eco(input,change_file)
    handle_info "ECO ops applied"
}

# ==============================================================================
# flow_proc: legalize
# Pure legalization — no optimization. refinePlace -eco moves only the
# affected cells with minimum-distance constraint.
# ==============================================================================
flow_proc legalize {
    handle_info "Legalizing placement post-ECO..."
    refinePlace -eco -preserveRouting true
    redirect $::REPORTS_DIR/checkPlace.post_eco { checkPlace }
    handle_info "Placement legalized"
}

# ==============================================================================
# flow_proc: eco_reroute
# Incremental ECO routing — Innovus ecoRoute handles dangling wires and
# new/broken nets without touching already-clean routing.
# ==============================================================================
flow_proc eco_reroute {
    handle_info "Running ECO reroute..."
    ecoRoute
    redirect $::REPORTS_DIR/verifyConnectivity.post_eco { verifyConnectivity -type all }
    handle_info "ECO reroute completed"
}

# ==============================================================================
# flow_proc: add_fillers
# Re-insert std-cell fillers around newly-placed ECO cells.
# ==============================================================================
flow_proc add_fillers {
    handle_info "Adding fillers..."
    global eco tech

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
    handle_info "Fillers added"
}

# ==============================================================================
# flow_proc: save_design
# Save the Innovus design db.
# ==============================================================================
flow_proc save_design {
    handle_info "Saving ECO design..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    set _db "$::OUTPUTS_DIR/db/${design_name}_eco.innovus.dat"
    file mkdir [file dirname $_db]
    handle_info "saveDesign $_db"
    saveDesign $_db
    handle_info "ECO design saved: $_db"
}

# ==============================================================================
# Execute all registered flow_procs in definition order
# ==============================================================================
flow_exec_all

exit
