#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - LEC Setup Command File
# Description: Setup and configuration for Logic Equivalence Checking
# Tool: Synopsys Formality
# Usage: Source this file in Formality or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

# Source environment variables
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source -e $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

# Source flow utilities
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    puts stderr "ERROR: FLOW_DIR not found in environment"
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts stderr "ERROR: UTILITIES_VERSION not set."
    exit 1
}

set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source -e $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

namespace import ::CBFlow::Utilities::print_header

# Source generated configuration file
set config_file "$run_dir/work/LEC/setup1/run/config.tcl"
if {[file exists $config_file]} {
    source -e $config_file
}

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Declare global arrays
global lec project tech flow

# Source FORMALITY tool config
set _tool_config "[file dirname [info script]]/formality_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting LEC setup stage with Synopsys Formality..."

# Initialize flow namespace
if {![namespace exists ::flow]} {
    namespace eval ::flow {
        variable exec_mode "auto"
        variable current_stage ""
        variable start_time [clock seconds]
        variable flow_errors {}
    }
}

set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/LEC/setup1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_libraries {
    global lec project tech flow FLOW_DIR
    handle_info "Setting up libraries for equivalence checking..."

    # Read timing library files for cell matching
    if {[info exists tech(lib,timing)]} {
        puts "Reading Liberty files for reference:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set project_root [file dirname $FLOW_DIR]
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "   $lib"
                # Formality: read_db or set_top
                read_db $lib_path
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_warning "tech(lib,timing) not defined - cell matching may be limited"
    }

    puts " Libraries setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ REFERENCE DESIGN (GOLDEN)                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_reference_design {
    global lec project tech flow FLOW_DIR
    handle_info "Reading reference (golden) design..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set golden_dir "$run_dir/work/LEC/inputs/netlist_golden"
    set golden_files [glob -nocomplain "$golden_dir/*.v" "$golden_dir/*.sv" "$golden_dir/*.vg"]

    if {[llength $golden_files] > 0} {
        puts "Found [llength $golden_files] golden netlist files"
        foreach netlist $golden_files {
            puts "   Reading: [file tail $netlist]"
            read_verilog -r $netlist
        }
    } else {
        handle_error "No golden netlist files found in $golden_dir"
    }

    # Set top module for reference
    if {[info exists project(top_module)]} {
        puts "Setting reference top module: $project(top_module)"
        set_top r:$project(top_module)
    }

    puts " Reference design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ IMPLEMENTATION DESIGN (REVISED)                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_implementation_design {
    global lec project tech flow FLOW_DIR
    handle_info "Reading implementation (revised) design..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set revised_dir "$run_dir/work/LEC/inputs/netlist_revised"
    set revised_files [glob -nocomplain "$revised_dir/*.v" "$revised_dir/*.sv" "$revised_dir/*.vg"]

    if {[llength $revised_files] > 0} {
        puts "Found [llength $revised_files] revised netlist files"
        foreach netlist $revised_files {
            puts "   Reading: [file tail $netlist]"
            read_verilog -i $netlist
        }
    } else {
        handle_error "No revised netlist files found in $revised_dir"
    }

    # Set top module for implementation
    if {[info exists project(top_module)]} {
        puts "Setting implementation top module: $project(top_module)"
        set_top i:$project(top_module)
    }

    puts " Implementation design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ CONSTRAINTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global lec project tech flow
    handle_info "Reading LEC constraints..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set constraints_dir "$run_dir/work/LEC/inputs/constraints"
    set constraint_files [glob -nocomplain "$constraints_dir/*.sdc" "$constraints_dir/*.fmconst" "$constraints_dir/*.svf"]

    if {[llength $constraint_files] > 0} {
        puts "Found [llength $constraint_files] constraint files"
        foreach cf $constraint_files {
            set ext [file extension $cf]
            puts "   Reading: [file tail $cf]"
            switch $ext {
                ".svf" {
                    # Synopsys Verification Flow guidance
                    set_svf $cf
                }
                ".sdc" {
                    read_sdc $cf
                }
                default {
                    source -e $cf
                }
            }
        }
        puts " Constraints loaded"
    } else {
        puts " No constraint files found (optional)"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       CONFIGURE VERIFICATION                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc configure_verification {
    global lec project tech flow
    handle_info "Configuring verification settings..."

    # Set verification mode
    if {[info exists formality(verification,mode)]} {
        puts "Verification mode: $formality(verification,mode)"
    } else {
        puts "Verification mode: default (combinational)"
    }

    # Configure matching settings
    if {[info exists formality(matching,multibit)] && $formality(matching,multibit) eq "true"} {
        set_constant_folding true
        puts "Multi-bit matching: enabled"
    }

    # Configure effort level
    if {[info exists formality(common,effort)]} {
        puts "Verification effort: $formality(common,effort)"
    }

    # Set undriven/unloaded signal handling
    set_undriven 0
    set_unloaded 0

    puts " Verification configured"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow LEC Setup with Synopsys Formality"
handle_info "═══════════════════════════════════════════════════════════════════════════════"

flow_proc setup_flow {
    handle_info "Executing LEC setup flow..."

    flow_exec setup_libraries
    flow_exec read_reference_design
    flow_exec read_implementation_design
    flow_exec read_constraints
    flow_exec configure_verification

    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " LEC Setup Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info "LEC setup completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Direct execution mode - running LEC setup flow"
    flow_exec setup_flow
} else {
    puts " CBFlow LEC setup procedures loaded"
    puts "Available: setup_libraries, read_reference_design, read_implementation_design, read_constraints, configure_verification, setup_flow"
}
exit
