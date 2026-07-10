#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FCFP Inputs Command File (Innovus)
# Description: Setup directories, read libraries, read hierarchical design,
#              read constraints, and validate inputs for fullchip floorplanning
# Tool: Cadence Innovus
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/FCFP/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

handle_info "Starting FCFP inputs stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        SETUP DIRECTORIES                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global fcfp flow project
    if {![namespace exists ::CBFlow::InputResolve]} { return }
    handle_info "Input resolution completed"
}

flow_proc setup_dirs {
    handle_info "Setting up FCFP input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    foreach dir {
        "work/FCFP/inputs/netlist"
        "work/FCFP/inputs/sdc"
        "work/FCFP/inputs/def"
        "work/FCFP/inputs/upf"
        "work/FCFP/inputs/lef"
        "work/FCFP/inputs/library"
        "work/FCFP/inputs/floorplan"
        "logs/inputs"
        "reports/fcfp"
        "reports/fcfp/floorplan"
        "reports/fcfp/powerplan"
        "reports/fcfp/post_floorplan"
        "results/fcfp"
    } {
        file mkdir "$run_dir/$dir"
    }
    puts " FCFP input directories created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_libraries {
    global fcfp project tech flow FLOW_DIR
    handle_info "Reading libraries for FCFP..."

    # Read timing libraries
    if {[info exists tech(lib,timing)]} {
        puts "Reading Liberty files:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        set project_root [file dirname $FLOW_DIR]
        foreach lib $lib_files {
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "   $lib"
                read_libs $lib_path
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_error "tech(lib,timing) not defined in configuration"
    }

    # Read technology LEF
    if {[info exists tech(lef,technology)]} {
        set project_root [file dirname $FLOW_DIR]
        set lef_path [file join $project_root [subst $tech(lef,technology)]]
        if {[file exists $lef_path]} {
            puts "   Reading technology LEF: [file tail $tech(lef,technology)]"
            read_physical -lef $lef_path
        } else {
            handle_warning "Technology LEF not found: $lef_path"
        }
    }

    # Read standard cell LEF
    if {[info exists tech(lef,standard_cells)]} {
        set project_root [file dirname $FLOW_DIR]
        set lef_path [file join $project_root [subst $tech(lef,standard_cells)]]
        if {[file exists $lef_path]} {
            puts "   Reading standard cell LEF: [file tail $tech(lef,standard_cells)]"
            read_physical -lef $lef_path
        }
    }

    # Read macro LEF files if available
    set run_dir $::env(CBFLOW_RUN_DIR)
    set macro_lefs [glob -nocomplain "$run_dir/work/FCFP/inputs/lef/*.lef"]
    if {[llength $macro_lefs] > 0} {
        puts "Reading macro LEF files:"
        foreach lef $macro_lefs {
            puts "   [file tail $lef]"
            read_physical -lef $lef
        }
    }

    puts " Libraries loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     READ HIERARCHICAL DESIGN                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_hierarchical_design {
    global fcfp project tech flow
    handle_info "Reading hierarchical design..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Read gate-level netlist
    set netlist_dir "$run_dir/work/FCFP/inputs/netlist"
    set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv" "$netlist_dir/*.vg"]

    if {[llength $netlist_files] > 0} {
        puts "Found [llength $netlist_files] netlist files"
        foreach netlist $netlist_files {
            puts "   Reading: [file tail $netlist]"
            read_verilog $netlist
        }
    } else {
        handle_error "No netlist files found in $netlist_dir"
    }

    # Set top module
    if {[info exists project(top_module)]} {
        puts "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    } else {
        handle_error "project(top_module) not defined"
    }

    # Read DEF for pre-existing placement/floorplan data
    set def_files [glob -nocomplain "$run_dir/work/FCFP/inputs/def/*.def" "$run_dir/work/FCFP/inputs/def/*.def.gz"]
    if {[llength $def_files] > 0} {
        foreach def $def_files {
            puts "   Reading DEF: [file tail $def]"
            read_def $def
        }
    }

    # Read UPF power intent
    set upf_files [glob -nocomplain "$run_dir/work/FCFP/inputs/upf/*.upf"]
    if {[llength $upf_files] > 0} {
        foreach upf $upf_files {
            puts "   Reading UPF: [file tail $upf]"
            read_power_intent -1801 $upf
        }
        commit_power_intent
    }

    puts " Hierarchical design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ CONSTRAINTS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global fcfp project tech flow
    handle_info "Reading timing constraints..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set sdc_files [glob -nocomplain "$run_dir/work/FCFP/inputs/sdc/*.sdc"]
    if {[llength $sdc_files] > 0} {
        foreach sdc $sdc_files {
            puts "   Reading SDC: [file tail $sdc]"
            read_sdc $sdc
        }
        puts " SDC constraints loaded"
    } else {
        handle_warning "No SDC files found for FCFP"
    }


    # Read floorplan constraints if available
    set fp_files [glob -nocomplain "$run_dir/work/FCFP/inputs/floorplan/*.tcl"]
    if {[llength $fp_files] > 0} {
        foreach fp_file $fp_files {
            puts "   Reading floorplan constraints: [file tail $fp_file]"
            source $fp_file
        }
    }

    puts " Constraints loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        VALIDATE INPUTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate {
    global fcfp project tech flow
    handle_info "Validating FCFP inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    set netlist_count [llength [glob -nocomplain "$run_dir/work/FCFP/inputs/netlist/*"]]
    set sdc_count [llength [glob -nocomplain "$run_dir/work/FCFP/inputs/sdc/*"]]
    set lef_count [llength [glob -nocomplain "$run_dir/work/FCFP/inputs/lef/*"]]

    if {$netlist_count == 0} { handle_warning "No netlist files"; incr errors }
    puts "  Netlist files: $netlist_count"
    puts "  SDC files: $sdc_count"
    puts "  LEF files: $lef_count"

    if {![info exists project(top_module)]} {
        handle_warning "project(top_module) not defined"
        incr errors
    }

    # Generate input summary
    set summary_file "$run_dir/reports/fcfp/inputs_summary.txt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow FCFP Input Summary - Innovus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Innovus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Input Files:"
    puts $fp "  Netlist: $netlist_count"
    puts $fp "  SDC:     $sdc_count"
    puts $fp "  LEF:     $lef_count"
    puts $fp "  DEF:     [llength [glob -nocomplain "$run_dir/work/FCFP/inputs/def/*"]]"
    puts $fp "  UPF:     [llength [glob -nocomplain "$run_dir/work/FCFP/inputs/upf/*"]]"
    puts $fp ""
    if {$errors > 0} {
        puts $fp "WARNINGS: $errors input issues detected"
    } else {
        puts $fp "STATUS: All required inputs present"
    }
    close $fp

    puts " Validation completed ($errors warnings)"
    puts " Summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow FCFP inputs with Innovus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc inputs_flow {
    handle_info "Executing FCFP inputs flow..."
    flow_exec setup_dirs
    flow_exec read_libraries
    flow_exec read_hierarchical_design
    flow_exec read_constraints
    flow_exec validate
    handle_info "FCFP inputs completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " FCFP inputs procedures loaded" }

# Exit tool after stage completion
exit
