#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Floorplan Flow Setup
# Description: FP-specific flow_proc hooks and utilities
# Priority: Medium (overrides global flow setup)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading FP flow setup (specific to Floorplan flows)"

# FP flow initialization
proc fp_flow_init_hook {} {
    handle_info "FP Flow init: Preparing floorplan flow environment"

    # Set FP-specific environment
    global fp
    if {![info exists fp]} {
        array set fp {}
    }

    # Default FP settings
    if {![info exists fp(core_utilization)]} {
        set fp(core_utilization) 0.75
    }
    if {![info exists fp(aspect_ratio)]} {
        set fp(aspect_ratio) 1.0
    }
}

# FP stage-specific hooks
proc fp_inputs_pre_hook {} {
    handle_info "FP inputs pre-hook: Validating floorplan inputs"
}

proc fp_inputs_post_hook {} {
    handle_info "FP inputs post-hook: Floorplan inputs validated"
}

proc fp_floorplan_pre_hook {} {
    handle_info "FP floorplan pre-hook: Starting floorplan creation"
}

proc fp_floorplan_post_hook {} {
    handle_info "FP floorplan post-hook: Floorplan creation complete"
}

proc fp_powerplan_pre_hook {} {
    handle_info "FP powerplan pre-hook: Starting power planning"
}

proc fp_powerplan_post_hook {} {
    handle_info "FP powerplan post-hook: Power planning complete"
}

# FP validation hooks
proc fp_validate_design_hook {} {
    handle_info "FP validate: Checking floorplan design rules"

    global fp
    if {[info exists fp(core_utilization)] && $fp(core_utilization) > 0.9} {
        handle_warning "High core utilization detected: $fp(core_utilization)"
    }
}

handle_info "FP flow setup complete - floorplan-specific hooks loaded"