#!/usr/bin/env tclsh
# CBFlow LEC inputs - Synopsys Formality

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       RESOLVE INPUTS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global lec flow project flow_input_handshake

    set design_name [expr {[info exists lec(common,design_name)] ? $lec(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist_golden: lec(input,netlist_golden_release_tag) -> lec(input,netlist_golden)
    if {[info exists lec(input,netlist_golden_release_tag)] && $lec(input,netlist_golden_release_tag) ne ""} {
        set hs [get_input_handshake "LEC" "netlist_golden"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve lec "netlist_golden" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set lec(input,netlist_golden) $_file
            handle_info "  Golden netlist resolved: $_file"
        }
    }

    # ── netlist_revised: lec(input,netlist_revised_release_tag) -> lec(input,netlist_revised)
    if {[info exists lec(input,netlist_revised_release_tag)] && $lec(input,netlist_revised_release_tag) ne ""} {
        set hs [get_input_handshake "LEC" "netlist_revised"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve lec "netlist_revised" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set lec(input,netlist_revised) $_file
            handle_info "  Revised netlist resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE INPUT FILES                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_input_files {
    global lec project tech flow FLOW_DIR
    handle_info "Validating LEC input files..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Check for golden netlist
    set golden_dir "$run_dir/work/LEC/inputs/netlist_golden"
    set golden_files [glob -nocomplain "$golden_dir/*"]
    if {[llength $golden_files] > 0} {
        puts "  Golden netlist files found: [llength $golden_files]"
        foreach f $golden_files {
            puts "    [file tail $f]"
        }
    } else {
        handle_warning "No golden netlist files found in $golden_dir"
    }

    # Check for revised netlist
    set revised_dir "$run_dir/work/LEC/inputs/netlist_revised"
    set revised_files [glob -nocomplain "$revised_dir/*"]
    if {[llength $revised_files] > 0} {
        puts "  Revised netlist files found: [llength $revised_files]"
        foreach f $revised_files {
            puts "    [file tail $f]"
        }
    } else {
        handle_warning "No revised netlist files found in $revised_dir"
    }

    # Check for constraints
    set constraints_dir "$run_dir/work/LEC/inputs/constraints"
    set constraint_files [glob -nocomplain "$constraints_dir/*"]
    if {[llength $constraint_files] > 0} {
        puts "  Constraint files found: [llength $constraint_files]"
    } else {
        puts "  No constraint files (optional)"
    }

    puts " Input file validation completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP INPUT DIRECTORIES                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_input_directories {
    handle_info "Setting up LEC input directories..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create standard directory structure
    foreach dir {
        "work/LEC/inputs/netlist_golden"
        "work/LEC/inputs/netlist_revised"
        "work/LEC/inputs/constraints"
        "logs/inputs"
        "reports/lec"
        "results/lec"
    } {
        file mkdir "$run_dir/$dir"
    }

    puts " Input directories created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE INPUT SUMMARY                               │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_input_summary {
    global lec project
    handle_info "Generating input summary..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set summary_file "$::REPORTS_DIR/inputs_summary.txt"
    file mkdir [file dirname $summary_file]

    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow LEC - Input Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""

    # Count files
    set golden_count [llength [glob -nocomplain "$run_dir/work/LEC/inputs/netlist_golden/*"]]
    set revised_count [llength [glob -nocomplain "$run_dir/work/LEC/inputs/netlist_revised/*"]]
    set constraint_count [llength [glob -nocomplain "$run_dir/work/LEC/inputs/constraints/*"]]

    puts $fp "Input Files:"
    puts $fp "  Golden netlist files:  $golden_count"
    puts $fp "  Revised netlist files: $revised_count"
    puts $fp "  Constraint files:     $constraint_count"
    puts $fp ""
    puts $fp "Tool: Synopsys Formality"
    if {[info exists lec(tool,version)]} {
        puts $fp "Version: $lec(tool,version)"
    }
    close $fp

    puts " Input summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc inputs_flow {
    handle_info "Executing LEC inputs flow..."

    flow_exec setup_input_directories
    flow_exec validate_input_files
    flow_exec generate_input_summary

    handle_info "LEC inputs stage completed successfully"
}

# Check if being run directly or sourced
if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Direct execution mode - running LEC inputs flow"
    flow_exec inputs_flow
} else {
    puts " CBFlow LEC inputs procedures loaded"
}
exit
