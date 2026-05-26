#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Setup Hooks for SYNTH_PNR synthesis1 (synthesis1_default)
# Generated: Thu May 21 09:47:33 IST 2026
# Description: flow_proc hooks only (NO configuration variables)
# ═══════════════════════════════════════════════════════════════════════════════

# CBFlow setup file - configuration is loaded separately

# Use environment variables from .run.cbflow.env
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    set FLOW_DIR "/Users/vmerugu/projects/CBflow_clone/PD"
}
if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} else {
    set ROOT_DIR "[file dirname $FLOW_DIR]"
}
if {[info exists ::env(RUN_DIR)]} {
    set RUN_DIR $::env(RUN_DIR)
} else {
    set RUN_DIR "/Users/vmerugu/projects/CBflow_clone/workarea_test/P0_run_SYNTH_PNR_test1"
}

global synth_pnr synth pnr project tech flow

puts "INFO: Setup hooks for SYNTH_PNR synthesis1 (synthesis1_default)"

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOK EXECUTION ORDER AND PRECEDENCE
# ═══════════════════════════════════════════════════════════════════════════════
# This file contains flow_proc hooks that execute in hierarchical order:
# 1. Global setup (lowest priority) - applies to ALL nodes in ALL flows
# 2. Flow-specific setup - applies to all nodes in this flow type
# 3. Tool-specific setup - applies to specific EDA tool
# 4. Stage-specific setup - applies to specific flow stage
# 5. Override setup (highest priority) - user customizations
#
# Within each level, hooks execute in order: prepend -> main -> append
# Higher priority levels can override lower levels using flow_proc replace
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# global_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/common/v1.0.0/setup.tcl
# ───────────────────────────────────────────────────────────────────────────────
# CBflow Global Setup — applies to ALL flows, ALL stages
# Priority: LOWEST

# Global flow_proc hook: add design info header to every stage
flow_proc_prepend start_stage {
    handle_info "═══════════════════════════════════════════"
    handle_info "  CBflow Global Hook: Design=$::env(CBFLOW_DESIGN_NAME)"
    handle_info "  Flow=$::env(CBFLOW_FLOW_TYPE) Release=$::env(CBFLOW_RELEASE_VERSION)"
    handle_info "═══════════════════════════════════════════"
}


# ───────────────────────────────────────────────────────────────────────────────
# global_flow_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/common/v1.0.0/flow_setup.tcl
# ───────────────────────────────────────────────────────────────────────────────
#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Global Flow Setup (Applied to ALL flow types)
# Description: Common flow_proc hooks and utilities for all flows
# Priority: Low (can be overridden by flow-specific setup)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading global flow setup - CBFlow flow_proc hooks for ALL flow types"

# Flow initialization hooks
flow_proc_prepend flow_init {
    handle_info "Flow init prepend: Preparing for flow initialization"

    # Initialize flow namespace if not exists
    if {![namespace exists ::flow]} {
        namespace eval ::flow {
            variable exec_mode "manual"
            variable current_stage ""
            variable start_time [clock seconds]
            variable flow_errors {}
        }
        handle_info "Initialized flow namespace"
    }

    # Set default execution mode
    set ::flow::exec_mode "manual"
    set ::flow::start_time [clock seconds]

    # Create flow-level directories
    set flow_dirs {
        "logs/flow"
        "reports/flow"
        "work"
    }

    foreach dir $flow_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created flow directory: $dir"
        }
    }

    handle_info "Flow initialization prepend completed"
}

flow_proc_append flow_init {
    handle_info "Flow init append: Flow initialization complete"

    # Validate flow initialization
    if {[info exists ::flow::exec_mode]} {
        handle_info "Flow execution mode: $::flow::exec_mode"
    }

    # Log flow start
    if {[info exists ::flow::start_time]} {
        set start_time_str [clock format $::flow::start_time]
        handle_info "Flow started at: $start_time_str"
    }

    handle_info "Flow initialization append completed"
}

# Stage transition hooks
flow_proc_prepend stage_transition {
    handle_info "Stage transition prepend: Preparing for stage change"

    # Update current stage tracking
    if {[info exists ::flow::current_stage]} {
        set ::flow::previous_stage $::flow::current_stage
    }

    # Create stage transition log
    set transition_log "logs/flow/stage_transitions.log"
    if {![file exists [file dirname $transition_log]]} {
        file mkdir [file dirname $transition_log]
    }

    set log_file [open $transition_log "a"]
    puts $log_file "[clock format [clock seconds]]: Stage transition initiated"
    close $log_file

    handle_info "Stage transition prepend completed"
}

flow_proc_append stage_transition {
    handle_info "Stage transition append: Stage change complete"

    # Log transition completion
    set transition_log "logs/flow/stage_transitions.log"
    set log_file [open $transition_log "a"]
    puts $log_file "[clock format [clock seconds]]: Stage transition completed"
    close $log_file

    # Validate stage transition
    if {[info exists ::flow::current_stage] && [info exists ::flow::previous_stage]} {
        handle_info "Transitioned from $::flow::previous_stage to $::flow::current_stage"
    }

    handle_info "Stage transition append completed"
}

# Error handling hooks
flow_proc_prepend error_handling {
    handle_info "Error handling prepend: Preparing error management"

    # Initialize error tracking
    if {![info exists ::flow::flow_errors]} {
        set ::flow::flow_errors {}
    }

    # Create error log directory
    if {![file exists "logs/errors"]} {
        file mkdir "logs/errors"
        handle_info "Created error log directory"
    }

    handle_info "Error handling prepend completed"
}

flow_proc_append error_handling {
    handle_info "Error handling append: Error management complete"

    # Report error summary
    if {[info exists ::flow::flow_errors] && [llength $::flow::flow_errors] > 0} {
        handle_info "Flow errors encountered: [llength $::flow::flow_errors]"

        # Write error summary
        set error_log "logs/errors/error_summary.log"
        set log_file [open $error_log "w"]
        puts $log_file "Flow Error Summary - [clock format [clock seconds]]"
        puts $log_file "================================================"
        foreach error $::flow::flow_errors {
            puts $log_file "ERROR: $error"
        }
        close $log_file
        handle_info "Error summary written to: $error_log"
    }

    handle_info "Error handling append completed"
}

# Cleanup hooks
flow_proc_prepend cleanup {
    handle_info "Cleanup prepend: Preparing cleanup operations"

    # Create cleanup log
    set cleanup_log "logs/flow/cleanup.log"
    if {![file exists [file dirname $cleanup_log]]} {
        file mkdir [file dirname $cleanup_log]
    }

    set log_file [open $cleanup_log "a"]
    puts $log_file "[clock format [clock seconds]]: Cleanup initiated"
    close $log_file

    handle_info "Cleanup prepend completed"
}

flow_proc_append cleanup {
    handle_info "Cleanup append: Cleanup operations complete"

    # Final flow statistics
    if {[info exists ::flow::start_time]} {
        set total_time [expr {[clock seconds] - $::flow::start_time}]
        handle_info "Total flow execution time: ${total_time} seconds"
    }

    # Log cleanup completion
    set cleanup_log "logs/flow/cleanup.log"
    set log_file [open $cleanup_log "a"]
    puts $log_file "[clock format [clock seconds]]: Cleanup completed"
    close $log_file

    handle_info "Cleanup append completed"
}

# User-customizable flow hook procedures
proc flow_proc_prepend_flow_init {} {
    # Default implementation - users can override this
    handle_info "User flow init prepend hook (default implementation)"
}

proc flow_proc_append_flow_init {} {
    # Default implementation - users can override this
    handle_info "User flow init append hook (default implementation)"
}

proc flow_proc_prepend_stage_transition {} {
    # Default implementation - users can override this
    handle_info "User stage transition prepend hook (default implementation)"
}

proc flow_proc_append_stage_transition {} {
    # Default implementation - users can override this
    handle_info "User stage transition append hook (default implementation)"
}

# Utility procedures for flow management
proc set_flow_stage {stage_name} {
    if {[namespace exists ::flow]} {
        set ::flow::current_stage $stage_name
        handle_info "Flow stage set to: $stage_name"
    }
}

proc add_flow_error {error_msg} {
    if {[namespace exists ::flow]} {
        lappend ::flow::flow_errors $error_msg
        handle_error "Flow error added: $error_msg"
    }
}

proc get_flow_status {} {
    if {[namespace exists ::flow]} {
        set status_info {}
        if {[info exists ::flow::current_stage]} {
            lappend status_info "stage:$::flow::current_stage"
        }
        if {[info exists ::flow::exec_mode]} {
            lappend status_info "mode:$::flow::exec_mode"
        }
        if {[info exists ::flow::flow_errors]} {
            lappend status_info "errors:[llength $::flow::flow_errors]"
        }
        return [join $status_info " "]
    }
    return "flow_namespace_not_initialized"
}

handle_info "Global flow setup complete - CBFlow flow_proc hooks and utilities loaded"

# ───────────────────────────────────────────────────────────────────────────────
# flow_type_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/common/v1.0.0/SYNTH_PNR/synopsys/fc/global_setup.tcl
# ───────────────────────────────────────────────────────────────────────────────
# CBflow SYNTH_PNR Flow Setup — applies to ALL stages in SYNTH_PNR
# Priority: Level 2

# Set FC-specific global options for SYNTH_PNR
flow_proc_prepend setup_technology {
    handle_info "SYNTH_PNR flow setup: Enabling unified flow options"
    # set_app_options -name design.multibit.enable -value true
}


# stage_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/common/v1.0.0/SYNTH_PNR/synopsys/fc/synthesis_setup.tcl (NOT FOUND - SKIPPED)

# ───────────────────────────────────────────────────────────────────────────────
# project_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/ravendrive/v1.0.0/setup.tcl
# ───────────────────────────────────────────────────────────────────────────────
# Ravendrive Project Setup — applies to all flows in this project
# Priority: Level 4

flow_proc_prepend start_stage {
    handle_info "Ravendrive project: Target frequency = 500MHz"
}


# ───────────────────────────────────────────────────────────────────────────────
# project_flow_setup: /Users/vmerugu/projects/CBflow_clone/PD/config/setup/ravendrive/v1.0.0/SYNTH_PNR/flow_setup.tcl
# ───────────────────────────────────────────────────────────────────────────────
# Ravendrive SYNTH_PNR Flow Setup
# Priority: Level 4

flow_proc_append setup_mcmm {
    handle_info "Ravendrive MCMM: Using signoff scenario set"
}


# workspace_setup: /Users/vmerugu/projects/CBflow_clone/workarea_test/P0_run_SYNTH_PNR_test1/setup/setup.tcl (NOT FOUND - SKIPPED)

# workspace_flow_setup: /Users/vmerugu/projects/CBflow_clone/workarea_test/P0_run_SYNTH_PNR_test1/setup/flow_setup.tcl (NOT FOUND - SKIPPED)

# workspace_stage_setup: /Users/vmerugu/projects/CBflow_clone/workarea_test/P0_run_SYNTH_PNR_test1/setup/synthesis_setup.tcl (NOT FOUND - SKIPPED)

# Load tool-specific command file with all flow_proc hooks applied
set tool_name "fc"
# Construct proper tool command file path with vendor and version
set tool_cmd_path "$FLOW_DIR/cmds/SYNTH_PNR/cadence/${tool_name}/${TOOL_VERSION}/synthesis1_${tool_name}.tcl"
if {[file exists $tool_cmd_path]} {
    puts "INFO: Loading tool-specific command file: $tool_cmd_path"
    source $tool_cmd_path
} else {
    puts "ERROR: Command file not found: $tool_cmd_path"
}

