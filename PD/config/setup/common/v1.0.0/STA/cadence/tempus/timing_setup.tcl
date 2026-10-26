#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Stage Setup Hooks (STA/Timing)
# Description: Timing stage-specific flow_proc hooks for Tempus
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading Tempus timing stage setup hooks"

flow_proc_prepend timing_flow {
    handle_info "Tempus timing stage prepend: Initializing STA"

    foreach dir {"logs/timing" "reports/timing" "results/timing"} {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created directory: $dir"
        }
    }
    handle_info "Timing stage: Starting static timing analysis"
}

flow_proc_append timing_flow {
    handle_info "Tempus timing stage append: Validating timing results"

    if {[file exists "results/timing/timing.rpt"]} {
        handle_info "Timing stage: Final timing report generated successfully"
    } else {
        handle_warning "Timing stage: Final timing report not generated"
    }

    if {[file exists "results/timing/violations.rpt"]} {
        handle_info "Timing stage: Violations report generated successfully"
    } else {
        handle_warning "Timing stage: Violations report not generated"
    }
}

handle_info "Tempus timing stage setup hooks loaded"
