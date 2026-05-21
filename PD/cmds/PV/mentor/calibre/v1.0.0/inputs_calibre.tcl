#!/usr/bin/env tclsh
# CBFlow PV inputs - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global pv flow project flow_input_handshake

    set design_name [expr {[info exists pv(common,design_name)] ? $pv(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── gds: pv(input,gds_release_tag) -> pv(input,gds) ────────────────────
    if {[info exists pv(input,gds_release_tag)] && $pv(input,gds_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "gds"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "gds" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,gds) $_file
            handle_info "  GDS resolved: $_file"
        }
    }

    # ── netlist: pv(input,netlist_release_tag) -> pv(input,netlist) ─────────
    if {[info exists pv(input,netlist_release_tag)] && $pv(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── def: pv(input,def_release_tag) -> pv(input,def_file) ────────────────
    if {[info exists pv(input,def_release_tag)] && $pv(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "def_file"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "def_file" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,def_file) $_file
            handle_info "  DEF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

flow_proc setup_input_directories {
    handle_info "Setting up PV input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {"work/PV/inputs/netlist" "work/PV/inputs/def" "work/PV/inputs/gds"
                 "logs/inputs" "reports/phyv" "results/phyv"
                 "results/drc" "results/lvs" "results/erc" "results/perc"} {
        file mkdir "$run_dir/$dir"
    }
    puts " Input directories created"
}

flow_proc validate_input_files {
    handle_info "Validating PV input files..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach {label dir} {"Netlist" "work/PV/inputs/netlist" "DEF" "work/PV/inputs/def" "GDS" "work/PV/inputs/gds"} {
        set files [glob -nocomplain "$run_dir/$dir/*"]
        if {[llength $files] > 0} { puts "  $label files: [llength $files]" } else { handle_warning "No $label files found" }
    }
    puts " Input validation completed"
}

flow_proc generate_input_summary {
    global phyv project
    handle_info "Generating input summary..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set sf "$run_dir/reports/phyv/inputs_summary.txt"
    file mkdir [file dirname $sf]
    set fp [open $sf w]
    puts $fp "CBFlow PV - Input Summary"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Netlist: [llength [glob -nocomplain "$run_dir/work/PV/inputs/netlist/*"]]"
    puts $fp "DEF: [llength [glob -nocomplain "$run_dir/work/PV/inputs/def/*"]]"
    puts $fp "GDS: [llength [glob -nocomplain "$run_dir/work/PV/inputs/gds/*"]]"
    puts $fp "Tool: Mentor Calibre"
    puts $fp "Stages: DRC, LVS, ERC, PERC"
    close $fp
    puts " Summary: $sf"
}

flow_proc inputs_flow {
    handle_info "Executing PV inputs flow..."
    flow_exec setup_input_directories
    flow_exec validate_input_files
    flow_exec generate_input_summary
    handle_info "PV inputs completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " PV inputs procedures loaded" }

# Exit tool after stage completion
exit
