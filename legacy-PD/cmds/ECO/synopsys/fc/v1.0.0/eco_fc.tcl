#!/usr/bin/env tclsh
# CBFlow ECO - Synopsys Fusion Compiler
#
# Minimal real-world ECO flow:
#   1. load_design       — open the routed design
#   2. source_eco_file    — eval the user's ECO ops file
#                          (eco(input,change_file), set via user_config or
#                          override_config.<node>.tcl)
#   3. legalize           — fix placement DRC after the ECO edits
#   4. eco_reroute        — incremental ECO router
#   5. add_fillers        — re-insert fillers around new cells
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
# Open lib, copy block from the upstream stage, link.
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for ECO..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]
    set lib_name    [expr {[info exists eco(common,design_lib_name)] ? $eco(common,design_lib_name) : "${design_name}.nlib"}]
    set prev_step   [expr {[info exists eco(input,from_block)] ? $eco(input,from_block) : "signoff"}]

    open_lib $lib_name
    copy_block -from ${design_name}/${prev_step} -to ${design_name}/eco
    current_block ${design_name}/eco
    link_block

    handle_info "Design loaded: ${design_name}/eco"
}

# ==============================================================================
# flow_proc: source_eco_file
# Source the user's ECO ops file. The path comes from the resolved cascade —
# user_config.tcl or override_config.<node>.tcl can set
# eco(input,change_file). Hard error if absent or unreadable.
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
# Legalize placement after the ECO edits — minimum-physical-impact mode so
# unchanged cells stay put.
# ==============================================================================
flow_proc legalize {
    handle_info "Legalizing placement post-ECO..."
    place_eco_cells -eco_changed_cells -legalize_only \
        -legalize_mode minimum_physical_impact
    redirect -file $::REPORTS_DIR/check_legality.post_eco { check_legality }
    handle_info "Placement legalized"
}

# ==============================================================================
# flow_proc: eco_reroute
# Incremental ECO routing — utilize_dangling_wires reduces detours.
# ==============================================================================
flow_proc eco_reroute {
    handle_info "Running ECO reroute..."
    route_eco -utilize_dangling_wires -reroute -open_net_driven
    redirect -file $::REPORTS_DIR/check_routes.post_eco { check_routes -open_net false }
    handle_info "ECO reroute completed"
}

# ==============================================================================
# flow_proc: add_fillers
# Re-insert std-cell fillers around newly-placed ECO cells. Uses tech filler
# sidefile if defined, else the default create_stdcell_fillers.
# ==============================================================================
flow_proc add_fillers {
    handle_info "Adding fillers..."
    global tech

    if {[info exists tech(filler_sidefile)] && [file exists $tech(filler_sidefile)]} {
        source $tech(filler_sidefile)
    } else {
        create_stdcell_fillers -lib_cells [get_lib_cells */FILL*]
    }
    handle_info "Fillers added"
}

# ==============================================================================
# flow_proc: save_design
# Save the block.
# ==============================================================================
flow_proc save_design {
    handle_info "Saving ECO design..."
    global eco flow

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]
    save_block
    save_block -as ${design_name}/eco
    handle_info "ECO design saved: ${design_name}/eco"
}

# ==============================================================================
# Execute all registered flow_procs in definition order
# ==============================================================================
flow_exec_all

exit
