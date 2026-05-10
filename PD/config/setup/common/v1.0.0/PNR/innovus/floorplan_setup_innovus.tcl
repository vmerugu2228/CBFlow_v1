# ═══════════════════════════════════════════════════════════════════════════════
# FLOW-LEVEL SETUP: PNR Floorplan (Lowest Priority)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading flow-level floorplan setup (lowest priority)"

# Global floorplan setup hooks
proc flow_level_floorplan_pre {} {
    handle_info "Flow-level: Preparing floorplan environment"
    # Add flow-level pre-setup here
}

proc flow_level_floorplan_post {} {
    handle_info "Flow-level: Cleaning up floorplan environment"
    # Add flow-level post-setup here
}

# Hook into specific flow_procs
if {[info exists ::flow::procs(read_floorplan)]} {
    set ::flow::procs(read_floorplan) "flow_level_floorplan_pre; $::flow::procs(read_floorplan); flow_level_floorplan_post"
    handle_info "Applied flow-level hooks to read_floorplan"
}

if {[info exists ::flow::procs(create_floorplan)]} {
    set ::flow::procs(create_floorplan) "flow_level_floorplan_pre; $::flow::procs(create_floorplan); flow_level_floorplan_post"
    handle_info "Applied flow-level hooks to create_floorplan"
}

handle_info "Flow-level floorplan setup complete"