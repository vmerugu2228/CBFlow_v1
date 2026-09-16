#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Common Configuration Loader (TCL-First Architecture)
# Description: Standardized TCL-only configuration and environment loading
# Version: v1.0.0
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Basic TCL-First Environment Loading ────────────────────────────────────────┐

# TCL-First Environment Loading - Clean and Simple Approach
proc load_tcl_environment {{search_dir "."}} {
    # Look for TCL environment files in priority order
    set env_files [list "$search_dir/.run.cbflow.tcl" "$search_dir/.cbflow.tcl" "$search_dir/../.cbflow.tcl"]

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            if {[catch {source $env_file} error]} {
                puts stderr "ERROR: Failed to source TCL environment file: $error"
                return false
            }
            return true
        }
    }

    puts stderr "WARNING: No CBFlow TCL environment file found"
    return false
}

# ┌─ Basic Logging Functions ────────────────────────────────────────────────────┐

proc handle_error {message} {
    puts stderr "\[CBFLOW-ERROR\] $message"
    return false
}

proc handle_warning {message} {
    puts stderr "\[CBFLOW-WARNING\] $message"
}

proc handle_info {message} {
    puts "\[CBFLOW-INFO\] $message"
}

proc handle_debug {message} {
    if {[info exists ::env(CBFLOW_DEBUG)] && $::env(CBFLOW_DEBUG) eq "1"} {
        puts "\[CBFLOW-DEBUG\] $message"
    }
}

# ┌─ Simple TCL-First Initialization ─────────────────────────────────────────────┐

# Simple CBFlow initialization using TCL-first approach
proc cbflow_init {args} {
    # Parse basic options
    array set options {
        -debug false
        -quiet false
    }

    foreach {key value} $args {
        if {[info exists options($key)]} {
            set options($key) $value
        }
    }

    # Set debug mode
    if {$options(-debug)} {
        set ::env(CBFLOW_DEBUG) "1"
    }

    # Try to load TCL environment from current directory
    set success [load_tcl_environment]

    if {$success} {
        # Load utilities if available
        if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
            if {[catch {source $::env(UTILS_TCL)} err]} {
                if {!$options(-quiet)} {
                    handle_warning "Failed to load utilities: $err"
                }
            } else {
                if {!$options(-quiet)} {
                    handle_debug "Utilities loaded successfully"
                }
            }
        }
    }

    if {!$options(-quiet)} {
        if {$success} {
            handle_info "CBFlow environment initialized successfully"
        } else {
            handle_info "CBFlow environment not found - using basic functionality"
        }
    }

    return $success
}

# Legacy compatibility function
proc cbflow_status {} {
    set env_loaded [info exists ::env(CBFLOW_RUN_DIR)]
    return [list env_config $env_loaded]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-Initialize (TCL-First Approach)
# ═══════════════════════════════════════════════════════════════════════════════

# Auto-initialize if this file is sourced (not executed directly)
if {[info script] ne $::argv0} {
    cbflow_init -quiet true
}