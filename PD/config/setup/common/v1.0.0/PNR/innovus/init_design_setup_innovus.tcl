# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Flow-level Setup for PNR init_design nodes
# Description: Setup hooks for all init_design nodes across all runs
# Priority: Low-Medium (overrides global, overridden by run-directory files)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading flow-level init_design setup (applies to all init_design nodes)"

# Flow-level hooks for all init_design procedures
proc init_design_flow_setup {} {
    handle_info "Flow-level setup: Preparing init_design environment"
    # Add common init_design setup here
}

proc init_design_flow_teardown {} {
    handle_info "Flow-level teardown: Cleaning up init_design environment"
    # Add common init_design cleanup here
}

# Example: Hook specific flow_procs for init_design
if {[info exists ::flow::procs(setup_libraries)]} {
    set ::flow::procs(setup_libraries) "init_design_flow_setup; $::flow::procs(setup_libraries); init_design_flow_teardown"
    handle_info "Applied flow-level hooks to setup_libraries"
}

handle_info "Flow-level init_design setup complete"