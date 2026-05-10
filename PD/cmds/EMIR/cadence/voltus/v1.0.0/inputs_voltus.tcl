#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - EMIR Inputs Command File (Voltus)
# Description: Input setup, design read, power data loading, constraint read,
#              and validation for EMIR analysis
# Tool: Cadence Voltus
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/EMIR/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global emir project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

handle_info "Starting EMIR inputs stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        RESOLVE INPUTS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global emir flow project flow_input_handshake

    set design_name [expr {[info exists emir(design_name)] ? $emir(design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── def: emir(input,def_release_tag) -> emir(input,def) ────────────────
    if {[info exists emir(input,def_release_tag)] && $emir(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "EMIR" "def"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve emir "def" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set emir(input,def) $_file
            handle_info "  DEF resolved: $_file"
        }
    }

    # ── netlist: emir(input,netlist_release_tag) -> emir(input,netlist) ─────
    if {[info exists emir(input,netlist_release_tag)] && $emir(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "EMIR" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve emir "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set emir(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── spef: emir(input,spef_release_tag) -> emir(input,spef) ─────────────
    if {[info exists emir(input,spef_release_tag)] && $emir(input,spef_release_tag) ne ""} {
        set hs [get_input_handshake "EMIR" "spef"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve emir "spef" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set emir(input,spef) $_file
            handle_info "  SPEF resolved: $_file"
        }
    }

    # ── gds: emir(input,gds_release_tag) -> emir(input,gds) ───────────────
    if {[info exists emir(input,gds_release_tag)] && $emir(input,gds_release_tag) ne ""} {
        set hs [get_input_handshake "EMIR" "gds"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve emir "gds" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set emir(input,gds) $_file
            handle_info "  GDS resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        SETUP DIRECTORIES                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_dirs {
    handle_info "Setting up EMIR input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    foreach dir {
        "work/EMIR/inputs/netlist"
        "work/EMIR/inputs/def"
        "work/EMIR/inputs/spef"
        "work/EMIR/inputs/library"
        "work/EMIR/inputs/activity"
        "work/EMIR/inputs/pg_lib"
        "logs/inputs"
        "reports/emir"
        "reports/emir/power"
        "reports/emir/ir_drop"
        "reports/emir/thermal"
        "results/emir"
    } {
        file mkdir "$run_dir/$dir"
    }
    puts " EMIR input directories created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ DESIGN                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_design {
    global emir project tech flow FLOW_DIR
    handle_info "Reading design with physical data for EMIR analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)

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
                read_lib $lib_path
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_error "tech(lib,timing) not defined in configuration"
    }

    # Read LEF files for physical data
    if {[info exists tech(lef,standard_cells)]} {
        puts "Reading LEF files:"
        set project_root [file dirname $FLOW_DIR]
        if {[info exists tech(lef,technology)]} {
            set lef_path [file join $project_root [subst $tech(lef,technology)]]
            if {[file exists $lef_path]} {
                puts "   [file tail $tech(lef,technology)]"
                read_physical -lef $lef_path
            }
        }
        set lef_path [file join $project_root [subst $tech(lef,standard_cells)]]
        if {[file exists $lef_path]} {
            puts "   [file tail $tech(lef,standard_cells)]"
            read_physical -lef $lef_path
        }
    }

    # Read DEF for physical placement and routing data
    set def_files [glob -nocomplain "$run_dir/work/EMIR/inputs/def/*.def" "$run_dir/work/EMIR/inputs/def/*.def.gz"]
    if {[llength $def_files] > 0} {
        foreach def $def_files {
            puts "   Reading DEF: [file tail $def]"
            read_design -physical_data $def
        }
    } else {
        handle_warning "No DEF files found in inputs/def"
    }

    # Read netlist
    set netlist_files [glob -nocomplain "$run_dir/work/EMIR/inputs/netlist/*.v" "$run_dir/work/EMIR/inputs/netlist/*.sv" "$run_dir/work/EMIR/inputs/netlist/*.vg"]
    if {[llength $netlist_files] > 0} {
        foreach netlist $netlist_files {
            puts "   Reading netlist: [file tail $netlist]"
            read_verilog $netlist
        }
    } else {
        handle_warning "No netlist files found in inputs/netlist"
    }

    # Set top module
    if {[info exists project(top_module)]} {
        puts "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    }

    # Read SPEF parasitics
    set spef_files [glob -nocomplain "$run_dir/work/EMIR/inputs/spef/*.spef" "$run_dir/work/EMIR/inputs/spef/*.spef.gz"]
    if {[llength $spef_files] > 0} {
        foreach spef $spef_files {
            puts "   Reading SPEF: [file tail $spef]"
            read_parasitics -format spef $spef
        }
    } else {
        handle_warning "No SPEF files found in inputs/spef"
    }

    puts " Design read completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ POWER DATA                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_power_data {
    global emir project tech flow
    handle_info "Reading power activity data..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Read switching activity files (VCD/SAIF)
    set activity_dir "$run_dir/work/EMIR/inputs/activity"
    set vcd_files [glob -nocomplain "$activity_dir/*.vcd" "$activity_dir/*.vcd.gz"]
    set saif_files [glob -nocomplain "$activity_dir/*.saif"]

    if {[llength $vcd_files] > 0} {
        foreach vcd $vcd_files {
            puts "   Reading VCD activity: [file tail $vcd]"
            read_activity_file -format vcd $vcd
        }
    } elseif {[llength $saif_files] > 0} {
        foreach saif $saif_files {
            puts "   Reading SAIF activity: [file tail $saif]"
            read_activity_file -format saif $saif
        }
    } else {
        handle_warning "No switching activity files found (VCD/SAIF)"
        # Set default switching activity from config
        if {[info exists emir(power,default_toggle_rate)]} {
            puts "   Using default toggle rate: $emir(power,default_toggle_rate)"
            set_default_switching_activity -toggle_rate $emir(power,default_toggle_rate)
        }
        if {[info exists emir(power,default_static_probability)]} {
            puts "   Using default static probability: $emir(power,default_static_probability)"
            set_default_switching_activity -static_probability $emir(power,default_static_probability)
        }
    }

    # Read power grid library models
    set pg_lib_files [glob -nocomplain "$run_dir/work/EMIR/inputs/pg_lib/*.cl"]
    if {[llength $pg_lib_files] > 0} {
        foreach pg_lib $pg_lib_files {
            puts "   Reading PG library: [file tail $pg_lib]"
            read_pg_library $pg_lib
        }
    }

    puts " Power data loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ CONSTRAINTS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global emir project tech flow
    handle_info "Reading constraints for EMIR analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Read SDC timing constraints
    set sdc_files [glob -nocomplain "$run_dir/work/EMIR/inputs/sdc/*.sdc"]
    if {[llength $sdc_files] > 0} {
        foreach sdc $sdc_files {
            puts "   Reading SDC: [file tail $sdc]"
            read_sdc $sdc
        }
        puts " SDC constraints loaded"
    } else {
        handle_warning "No SDC files found for EMIR analysis"
    }

    # Set power supply voltage from config
    if {[info exists emir(power,supply_voltage)]} {
        puts "   Setting supply voltage: $emir(power,supply_voltage)V"
        set_voltage $emir(power,supply_voltage) -object_type domain
    }

    puts " Constraints loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        VALIDATE INPUTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_inputs {
    global emir project tech flow
    handle_info "Validating EMIR input completeness..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Check mandatory files
    set netlist_count [llength [glob -nocomplain "$run_dir/work/EMIR/inputs/netlist/*"]]
    set def_count [llength [glob -nocomplain "$run_dir/work/EMIR/inputs/def/*"]]

    if {$netlist_count == 0} {
        handle_warning "No netlist files found -- EMIR analysis may fail"
        incr errors
    } else {
        puts "  Netlist files: $netlist_count"
    }

    if {$def_count == 0} {
        handle_warning "No DEF files found -- physical data required for EMIR"
        incr errors
    } else {
        puts "  DEF files: $def_count"
    }

    set spef_count [llength [glob -nocomplain "$run_dir/work/EMIR/inputs/spef/*"]]
    puts "  SPEF files: $spef_count"

    set activity_count [llength [glob -nocomplain "$run_dir/work/EMIR/inputs/activity/*"]]
    puts "  Activity files: $activity_count"

    # Validate config variables
    if {![info exists emir(ir_drop,threshold)]} {
        handle_warning "emir(ir_drop,threshold) not defined -- using tool defaults"
    }

    # Generate validation summary
    set summary_file "$::REPORTS_DIR/inputs_summary.txt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow EMIR Input Summary - Voltus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Cadence Voltus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Input Files:"
    puts $fp "  Netlist files:  $netlist_count"
    puts $fp "  DEF files:      $def_count"
    puts $fp "  SPEF files:     $spef_count"
    puts $fp "  Activity files: $activity_count"
    puts $fp ""
    if {$errors > 0} {
        puts $fp "WARNINGS: $errors input issues detected"
    } else {
        puts $fp "STATUS: All required inputs present"
    }
    close $fp

    puts " Input validation completed ($errors warnings)"
    puts " Summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow EMIR inputs with Voltus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc inputs_flow {
    handle_info "Executing EMIR inputs flow..."
    flow_exec setup_dirs
    flow_exec read_design
    flow_exec read_power_data
    flow_exec read_constraints
    flow_exec validate_inputs
    handle_info "EMIR inputs completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " EMIR inputs procedures loaded" }

# Exit tool after stage completion
exit
