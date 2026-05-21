#!/usr/bin/env tclsh
# CBFlow LEC setup - Synopsys Formality

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "setup"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {[info exists lec(verification,mode)]} {
        puts "Verification mode: $lec(verification,mode)"
    } else {
        puts "Verification mode: default (combinational)"
    }

    # Configure matching settings
    if {[info exists lec(matching,multibit)] && $lec(matching,multibit) eq "true"} {
        set_constant_folding true
        puts "Multi-bit matching: enabled"
    }

    # Configure effort level
    if {[info exists lec(common,effort)]} {
        puts "Verification effort: $lec(common,effort)"
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
