#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - STA Inputs Command File
# Description: Input validation and preparation for Static Timing Analysis
# Tool: Cadence Tempus
# Usage: Source this file in Tempus or run standalone
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"

if {[file exists $env_file]} {
    source $env_file
} else {
    puts stderr "ERROR: Environment file (.run.cbflow.tcl) not found at $env_file"
    exit 1
}

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
    source $utils_path
} else {
    puts stderr "ERROR: Cannot find flow utilities at $utils_path"
    exit 1
}

namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/STA/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow

# Source TEMPUS tool config
set _tool_config "[file dirname [info script]]/tempus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting STA inputs stage with Cadence Tempus..."

set WORK_DIR "$run_dir/work/STA/inputs"
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
# │                       MMMC CONFIGURATION                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

# Source MMMC multi-corner configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} {
    source $mmmc_config_file
    handle_info "MMMC configuration loaded: $mmmc_config_file"
    global analysis_views
    if {[info exists analysis_views]} {
        handle_info "  Available MMMC scenarios: [llength [array names analysis_views]]"
        foreach scenario [lsort [array names analysis_views]] {
            array set view_info $analysis_views($scenario)
            handle_info "    $scenario: corner=$view_info(corner) mode=$view_info(mode)"
            array unset view_info
        }
    }
} else {
    handle_warning "MMMC config not found: $mmmc_config_file -- single-corner mode"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       RESOLVE INPUTS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global sta flow project flow_input_handshake

    set design_name [expr {[info exists tempus(common,design_name)] ? $tempus(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: sta(input,netlist_release_tag) -> sta(input,netlist) ────────
    if {[info exists sta(input,netlist_release_tag)] && $sta(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── sdc: sta(input,sdc_release_tag) -> sta(input,sdc) ──────────────────
    if {[info exists sta(input,sdc_release_tag)] && $sta(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    # ── spef: sta(input,spef_release_tag) -> sta(input,spef) ────────────────
    if {[info exists sta(input,spef_release_tag)] && $sta(input,spef_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "spef"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "spef" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,spef) $_file
            handle_info "  SPEF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP INPUT DIRECTORIES                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_input_directories {
    handle_info "Setting up STA input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    foreach dir {
        "work/STA/inputs/netlist"
        "work/STA/inputs/sdc"
        "work/STA/inputs/spef"
        "work/STA/inputs/library"
        "logs/inputs"
        "reports/timing"
        "reports/extraction"
        "results/timing"
        "results/extraction"
    } {
        file mkdir "$run_dir/$dir"
    }
    puts " Input directories created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE INPUT FILES                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_input_files {
    global sta project tech flow FLOW_DIR
    handle_info "Validating STA input files..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Check netlist
    set netlist_files [glob -nocomplain "$run_dir/work/STA/inputs/netlist/*"]
    if {[llength $netlist_files] > 0} {
        puts "  Netlist files: [llength $netlist_files]"
        foreach f $netlist_files { puts "    [file tail $f]" }
    } else {
        handle_warning "No netlist files found"
    }

    # Check SDC constraints
    set sdc_files [glob -nocomplain "$run_dir/work/STA/inputs/sdc/*"]
    if {[llength $sdc_files] > 0} {
        puts "  SDC files: [llength $sdc_files]"
    } else {
        handle_warning "No SDC constraint files found"
    }

    # Check SPEF parasitics
    set spef_files [glob -nocomplain "$run_dir/work/STA/inputs/spef/*"]
    if {[llength $spef_files] > 0} {
        puts "  SPEF files: [llength $spef_files]"
    } else {
        puts "  No SPEF files (will be generated in extraction)"
    }

    # Check libraries
    set lib_files [glob -nocomplain "$run_dir/work/STA/inputs/library/*"]
    if {[llength $lib_files] > 0} {
        puts "  Library files: [llength $lib_files]"
    } else {
        puts "  No library files (optional - uses tech config)"
    }

    puts " Input file validation completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE INPUT SUMMARY                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_input_summary {
    global sta project
    handle_info "Generating input summary..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set summary_file "$::REPORTS_DIR/inputs_summary.txt"
    file mkdir [file dirname $summary_file]

    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow STA - Input Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Input Files:"
    puts $fp "  Netlist files:  [llength [glob -nocomplain "$run_dir/work/STA/inputs/netlist/*"]]"
    puts $fp "  SDC files:      [llength [glob -nocomplain "$run_dir/work/STA/inputs/sdc/*"]]"
    puts $fp "  SPEF files:     [llength [glob -nocomplain "$run_dir/work/STA/inputs/spef/*"]]"
    puts $fp "  Library files:  [llength [glob -nocomplain "$run_dir/work/STA/inputs/library/*"]]"
    puts $fp ""
    puts $fp "Tool: Cadence Tempus"
    if {[info exists sta(tool,version)]} { puts $fp "Version: $sta(tool,version)" }
    close $fp

    puts " Input summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc inputs_flow {
    handle_info "Executing STA inputs flow..."
    flow_exec setup_input_directories
    flow_exec validate_input_files
    flow_exec generate_input_summary
    handle_info "STA inputs stage completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    flow_exec inputs_flow
} else {
    puts " CBFlow STA inputs procedures loaded"
}

# Exit tool after stage completion
exit
