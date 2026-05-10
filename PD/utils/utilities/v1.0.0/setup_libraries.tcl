#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Library Setup Script  
# Description: Setup technology libraries for PNR flow
# Usage: tclsh setup_libraries.tcl <run_dir>
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 1} {
    if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
        source $::env(UTILS_TCL)
    } else {
        puts "ERROR: UTILS_TCL not found in environment"
        exit 1
    }
    handle_error "Usage: tclsh setup_libraries.tcl <run_dir>"
}

set run_dir [lindex $argv 0]

# TCL-First Environment Loading - Clean and Simple Approach
proc load_tcl_environment {run_dir} {
    puts "Loading CBFlow environment from native TCL files..."

    # Look for TCL environment files in priority order
    set env_files [list "$run_dir/.run.cbflow.tcl" "$run_dir/.cbflow.tcl" "$run_dir/../.cbflow.tcl"]

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            puts "Found CBFlow TCL environment file: $env_file"
            if {[catch {source $env_file} error]} {
                puts stderr "ERROR: Failed to source TCL environment file: $error"
                exit 1
            }
            puts "✓ Environment variables loaded from native TCL file"
            return true
        }
    }

    puts stderr "ERROR: No CBFlow TCL environment file found"
    puts stderr "Please ensure you're running from a CBFlow workspace or run directory"
    exit 1
}

# Load TCL environment
load_tcl_environment $run_dir

# Source utils.tcl for logging
if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
    source $::env(UTILS_TCL)
} elseif {[file exists "$run_dir/../utils.tcl"]} {
    source $::env(UTILS_TCL)
} elseif {[info exists ::env(FLOW_DIR)] && [file exists "$::env(FLOW_DIR)/utils/utils.tcl"]} {
    source "$::env(FLOW_DIR)/utils/utils.tcl"
}

# Change to run directory and call the inputs subnode handler
cd $run_dir

# Determine flow type from environment or default to PNR for library setup
set flow_type "PNR"
if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set flow_type $::env(CBFLOW_FLOW_TYPE)
} elseif {[file exists ".config.tcl"]} {
    # Try to read flow type from config
    if {[catch {source ".config.tcl"} error]} {
        handle_warning "Could not read flow type from config, using default PNR"
    } elseif {[info exists flow(type)]} {
        set flow_type $flow(type)
    }
}

# Call the inputs subnode handler with proper variables
set handler "$::env(FLOW_DIR)/cmds/$flow_type/cadence/innovus/$::env(INNOVUS_VERSION)/inputs_subnode_handler.tcl"
if {![file exists $handler]} {
    handle_error "Cannot find inputs_subnode_handler.tcl at $handler"
}
handle_info "Validating library files using $handler"
set result [catch {exec tclsh $handler "libraries" $run_dir} err]
if {$result != 0} {
    handle_error "Library validation failed: $err"
} else {
    handle_info "Library validation completed successfully."
}