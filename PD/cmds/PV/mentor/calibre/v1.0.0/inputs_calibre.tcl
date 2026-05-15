#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - PV Inputs Command File
# Description: Input validation and preparation for Physical Verification
# Tool: Mentor Calibre
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global phyv project tech flow
# Source CALIBRE tool config
set _tool_config "[file dirname [info script]]/calibre_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV inputs stage..."

set WORK_DIR "$run_dir/work/PV/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global pv flow project flow_input_handshake

    set design_name [expr {[info exists calibre(common,design_name)] ? $calibre(common,design_name) : $flow(design_name)}]

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

    # ── def: pv(input,def_release_tag) -> pv(input,def) ────────────────────
    if {[info exists pv(input,def_release_tag)] && $pv(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "def"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "def" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,def) $_file
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
