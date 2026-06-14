#!/usr/bin/env tclsh
# STA Inputs - Cadence Tempus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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

    set design_name [expr {[info exists sta(common,design_name)] ? $sta(common,design_name) : $flow(design_name)}]

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
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
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
