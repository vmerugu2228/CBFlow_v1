#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Common Utilities
# Description: Logging, environment loading, and common utilities
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::NodeManagement {
    variable version "v2.0.0"
    variable debug_mode false
    variable script_dir [file dirname [file normalize [info script]]]
}

# ┌─ Environment Loading ────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::load_tcl_environment {} {
    # Look for TCL environment files in priority order
    set env_files {".run.cbflow.tcl" ".cbflow.tcl" "../.cbflow.tcl"}

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            if {[catch {source $env_file} error]} {
                puts stderr "ERROR: Failed to source TCL environment file: $error"
                exit 1
            }
            return true
        }
    }

    puts stderr "ERROR: No CBFlow TCL environment file found"
    puts stderr "Please run from a CBFlow workspace or run directory"
    exit 1
}

# ┌─ Environment Validation ─────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::validate_environment {} {
    set required_env_vars {
        CONFIG_ROOT
        SCRIPTS_ROOT
        PROJECT_ROOT
        PROJECT_NAME
        PROJECT_VERSION
        TECHNOLOGY_VENDOR
        TECHNOLOGY_NODE
        TECHNOLOGY_VERSION
        UTILITIES_VERSION
    }

    CBFLOW_DEBUG "Validating required environment variables..."

    set missing_vars {}
    foreach var $required_env_vars {
        if {![info exists ::env($var)]} {
            lappend missing_vars $var
        } else {
            CBFLOW_DEBUG "✓ $var = $::env($var)"
        }
    }

    if {[llength $missing_vars] > 0} {
        CBFLOW_ERROR "Missing required environment variables:"
        foreach var $missing_vars {
            CBFLOW_ERROR "  - $var"
        }
        CBFLOW_ERROR ""
        CBFLOW_ERROR "Please ensure proper environment variables are loaded."
        return false
    }

    CBFLOW_DEBUG "All required environment variables are available"
    return true
}

# ┌─ Utility Functions ──────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::get_run_dir {} {
    if {![info exists ::env(CBFLOW_RUN_DIR)]} {
        CBFLOW_ERROR "CBFLOW_RUN_DIR environment variable not set"
        return ""
    }
    return $::env(CBFLOW_RUN_DIR)
}

proc ::CBFlow::NodeManagement::ensure_setup_dir {} {
    set run_dir [get_run_dir]
    if {$run_dir eq ""} {
        return ""
    }
    set setup_dir "$run_dir/setup"
    if {![file exists $setup_dir]} {
        file mkdir $setup_dir
    }
    return $setup_dir
}
