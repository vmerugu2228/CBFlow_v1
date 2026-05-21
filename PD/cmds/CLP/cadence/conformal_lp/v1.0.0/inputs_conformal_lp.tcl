#!/usr/bin/env tclsh
# CLP Inputs - Cadence Conformal LP

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting CLP inputs stage..."

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/CLP/inputs1"
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
# │                       RESOLVE INPUTS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global clp flow project flow_input_handshake

    set design_name [expr {[info exists clp(common,design_name)] ? $clp(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: clp(input,netlist_release_tag) -> clp(input,netlist) ────────
    if {[info exists clp(input,netlist_release_tag)] && $clp(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "CLP" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve clp "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set clp(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── upf: clp(input,upf_release_tag) -> clp(input,upf_file) ─────────────
    if {[info exists clp(input,upf_release_tag)] && $clp(input,upf_release_tag) ne ""} {
        set hs [get_input_handshake "CLP" "upf"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve clp "upf" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set clp(input,upf_file) $_file
            handle_info "  UPF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP INPUT DIRECTORIES                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_input_directories {
    handle_info "Setting up CLP input directories..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    foreach dir {
        "work/CLP/inputs/netlist"
        "work/CLP/inputs/upf"
        "work/CLP/inputs/power_spec"
        "logs/inputs"
        "reports/clp"
        "results/clp"
        "results/db"
    } {
        file mkdir "$run_dir/$dir"
    }

    puts " Input directories created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE INPUT FILES                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_input_files {
    global clp project tech flow FLOW_DIR
    handle_info "Validating CLP input files..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Check for netlist
    set netlist_dir "$run_dir/work/CLP/inputs/netlist"
    set netlist_files [glob -nocomplain "$netlist_dir/*"]
    if {[llength $netlist_files] > 0} {
        puts "  Netlist files found: [llength $netlist_files]"
        foreach f $netlist_files {
            puts "    [file tail $f]"
        }
    } else {
        handle_warning "No netlist files found in $netlist_dir"
    }

    # Check for UPF power intent
    set upf_dir "$run_dir/work/CLP/inputs/upf"
    set upf_files [glob -nocomplain "$upf_dir/*.upf" "$upf_dir/*.cpf"]
    if {[llength $upf_files] > 0} {
        puts "  UPF/CPF files found: [llength $upf_files]"
        foreach f $upf_files {
            puts "    [file tail $f]"
        }
    } else {
        handle_warning "No UPF/CPF files found in $upf_dir"
    }

    # Check for power specification
    set power_dir "$run_dir/work/CLP/inputs/power_spec"
    set power_files [glob -nocomplain "$power_dir/*"]
    if {[llength $power_files] > 0} {
        puts "  Power spec files found: [llength $power_files]"
    } else {
        puts "  No power spec files (optional)"
    }

    puts " Input file validation completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE INPUT SUMMARY                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_input_summary {
    global clp project
    handle_info "Generating input summary..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set summary_file "$::REPORTS_DIR/inputs_summary.txt"
    file mkdir [file dirname $summary_file]

    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow CLP - Input Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""

    set netlist_count [llength [glob -nocomplain "$run_dir/work/CLP/inputs/netlist/*"]]
    set upf_count [llength [glob -nocomplain "$run_dir/work/CLP/inputs/upf/*"]]
    set power_count [llength [glob -nocomplain "$run_dir/work/CLP/inputs/power_spec/*"]]

    puts $fp "Input Files:"
    puts $fp "  Netlist files:    $netlist_count"
    puts $fp "  UPF/CPF files:    $upf_count"
    puts $fp "  Power spec files: $power_count"
    puts $fp ""
    puts $fp "Tool: Cadence Conformal LP"
    if {[info exists clp(tool,version)]} {
        puts $fp "Version: $clp(tool,version)"
    }
    close $fp

    puts " Input summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc inputs_flow {
    handle_info "Executing CLP inputs flow..."

    flow_exec setup_input_directories
    flow_exec validate_input_files
    flow_exec generate_input_summary

    handle_info "CLP inputs stage completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Direct execution mode - running CLP inputs flow"
    flow_exec inputs_flow
} else {
    puts " CBFlow CLP inputs procedures loaded"
}

# Exit tool after stage completion
exit
