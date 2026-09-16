#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Global Setup Hooks (Applied to ALL flow_proc procedures)
# Description: Global flow_proc hooks that execute before/after any flow procedure
# Priority: Lowest (overridden by all other setup files)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading global setup.tcl - CBFlow flow_proc hooks for ALL flows"

# Global hooks that apply to ALL flow_proc procedures
flow_proc_prepend global {
    handle_info "Global prepend hook: Starting any flow_proc execution"

    # Global environment validation
    if {![info exists ::env(FLOW_DIR)]} {
        handle_error "FLOW_DIR environment variable not set"
    }
    if {![info exists ::env(CBFLOW_RUN_DIR)]} {
        handle_error "CBFLOW_RUN_DIR environment variable not set"
    }

    # Global directory structure creation
    set global_dirs {
        "logs"
        "reports"
        "work"
        ".stamps"
    }

    foreach dir $global_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created global directory: $dir"
        }
    }

    # Initialize global timing for procedure execution
    set ::global_proc_start_time [clock seconds]
    handle_info "Global prepend hook completed"
}

flow_proc_append global {
    handle_info "Global append hook: Completed any flow_proc execution"

    # Global cleanup and validation
    if {[info exists ::global_proc_start_time]} {
        set execution_time [expr {[clock seconds] - $::global_proc_start_time}]
        handle_info "Procedure execution time: ${execution_time} seconds"
        unset ::global_proc_start_time
    }

    handle_info "Global append hook completed"
}

# Stage-specific global hooks for common operations
flow_proc_prepend inputs {
    handle_info "Global inputs prepend: Preparing for inputs processing"

    # Create inputs-specific directory structure
    set inputs_dirs {
        "logs/inputs"
        "reports/inputs"
    }

    foreach dir $inputs_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created inputs directory: $dir"
        }
    }
}

flow_proc_append inputs {
    handle_info "Global inputs append: Inputs processing complete"

    # Global inputs validation
    if {[file exists "work"]} {
        set work_dirs [glob -nocomplain "work/*/inputs"]
        if {[llength $work_dirs] > 0} {
            handle_info "Inputs directories found: [llength $work_dirs]"
        }
    }
}

flow_proc_prepend synthesis {
    handle_info "Global synthesis prepend: Preparing for synthesis processing"

    # Create synthesis-specific directory structure
    set synthesis_dirs {
        "logs/synthesis"
        "reports/synthesis"
    }

    foreach dir $synthesis_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created synthesis directory: $dir"
        }
    }
}

flow_proc_append synthesis {
    handle_info "Global synthesis append: Synthesis processing complete"

    # Global synthesis validation
    if {[file exists "work"]} {
        set synth_dirs [glob -nocomplain "work/*/synthesis"]
        if {[llength $synth_dirs] > 0} {
            handle_info "Synthesis directories found: [llength $synth_dirs]"
        }
    }
}

# User-customizable hook procedures (can be overridden in override files)
proc flow_proc_prepend_global {} {
    # Default implementation - users can override this
    handle_info "User global prepend hook (default implementation)"
}

proc flow_proc_append_global {} {
    # Default implementation - users can override this
    handle_info "User global append hook (default implementation)"
}

# Error handling hooks
flow_proc_prepend error_handler {
    handle_info "Global error prepend: Preparing error handling"
}

flow_proc_append error_handler {
    handle_info "Global error append: Error handling complete"
}

handle_info "Global setup complete - CBFlow flow_proc hooks loaded and ready"