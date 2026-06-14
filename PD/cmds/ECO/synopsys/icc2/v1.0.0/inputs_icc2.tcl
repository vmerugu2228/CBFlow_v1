#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - ECO Inputs Command File
# Description: Input validation and design loading for ECO
# Tool: Synopsys IC Compiler II
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/ECO/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global eco project tech flow
handle_info "Starting ECO inputs with Synopsys IC Compiler II..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/ECO/inputs1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

# --------------------------------------------------------------------------
# Procedure: setup_dirs
#   Create directory structure for ECO flow
# --------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global eco flow project
    if {![namespace exists ::CBFlow::InputResolve]} { return }
    handle_info "Input resolution completed"
}

flow_proc setup_dirs {
    handle_info "Setting up ECO input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/ECO/inputs/netlist" "work/ECO/inputs/def" "work/ECO/inputs/sdc"
        "work/ECO/inputs/library" "work/ECO/inputs/eco_changes"
        "work/ECO/eco/run" "work/ECO/export_db/run"
        "logs/eco" "reports/eco" "results/eco" "results/db"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "ECO directories created"
}

# --------------------------------------------------------------------------
# Procedure: read_design
#   Open design library and block in ICC2
# --------------------------------------------------------------------------
flow_proc read_design {
    global eco project tech
    handle_info "Loading design into IC Compiler II..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Open NDM library
    if {[info exists eco(input,nlib)]} {
        set nlib $eco(input,nlib)
        handle_info "Opening library: $nlib"
        open_lib $nlib
    } elseif {[info exists eco(input,db)]} {
        set db $eco(input,db)
        handle_info "Opening design: $db"
        open_lib $db
    } else {
        set nlib_candidates [glob -nocomplain "$run_dir/work/ECO/inputs/library/*.nlib"]
        if {[llength $nlib_candidates] > 0} {
            set nlib [lindex $nlib_candidates 0]
            handle_info "Opening library: $nlib"
            open_lib $nlib
        } else {
            handle_error "No design library specified in eco(input,nlib)"
            return
        }
    }

    # Open block
    if {[info exists eco(input,block)]} {
        open_block $eco(input,block)
        handle_info "Opened block: $eco(input,block)"
    } elseif {[info exists project(top_module)]} {
        open_block $project(top_module)
        handle_info "Opened block: $project(top_module)"
    }

    # Read SDC constraints
    if {[info exists eco(input,sdc)]} {
        handle_info "Reading SDC: $eco(input,sdc)"
        read_sdc $eco(input,sdc)
    } else {
        set sdc_candidates [glob -nocomplain "$run_dir/work/ECO/inputs/sdc/*.sdc"]
        foreach sdc $sdc_candidates {
            handle_info "Reading SDC: $sdc"
            read_sdc $sdc
        }
    }

    # Set routing technology
    if {[info exists tech(tech_file)]} {
        set_technology -node $tech(tech_file)
    }

    handle_info "Design loading completed"
}

# --------------------------------------------------------------------------
# Procedure: read_eco_changes
#   Load ECO change specifications
# --------------------------------------------------------------------------
flow_proc read_eco_changes {
    global eco
    handle_info "Reading ECO change specifications..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::eco_change_files {}

    if {[info exists eco(input,eco_verilog)]} {
        lappend ::eco_change_files $eco(input,eco_verilog)
        handle_info "ECO Verilog: $eco(input,eco_verilog)"
    }
    if {[info exists eco(input,eco_script)]} {
        lappend ::eco_change_files $eco(input,eco_script)
        handle_info "ECO script: $eco(input,eco_script)"
    }
    if {[info exists eco(input,change_list)]} {
        lappend ::eco_change_files $eco(input,change_list)
        handle_info "Change list: $eco(input,change_list)"
    }

    if {[llength $::eco_change_files] == 0} {
        set eco_candidates [glob -nocomplain "$run_dir/work/ECO/inputs/eco_changes/*.v" \
                                             "$run_dir/work/ECO/inputs/eco_changes/*.tcl" \
                                             "$run_dir/work/ECO/inputs/eco_changes/*.eco"]
        foreach f $eco_candidates { lappend ::eco_change_files $f }
    }

    if {[llength $::eco_change_files] == 0} {
        handle_warning "No ECO change files found"
    } else {
        handle_info "ECO change files: [llength $::eco_change_files]"
    }
}

# --------------------------------------------------------------------------
# Procedure: validate_inputs
#   Validate ECO inputs
# --------------------------------------------------------------------------
flow_proc validate_inputs {
    global eco project tech
    handle_info "Validating ECO inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors {}

    if {![info exists project(top_module)] && ![info exists eco(common,top_cell)]} {
        lappend errors "Top cell not defined"
    }
    if {[llength $::eco_change_files] == 0} {
        lappend errors "No ECO change files specified"
    }

    set vf "$::REPORTS_DIR/inputs_validation.rpt"
    set fp [open $vf w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow ECO - Input Validation Report"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Synopsys IC Compiler II"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp ""
    puts $fp "ECO Change Files: [llength $::eco_change_files]"
    foreach f $::eco_change_files { puts $fp "  $f" }
    puts $fp ""

    if {[llength $errors] > 0} {
        puts $fp "VALIDATION STATUS: FAIL"
        foreach e $errors { puts $fp "  - $e" }
        close $fp
        foreach e $errors { handle_error "ECO validation: $e" }
    } else {
        puts $fp "VALIDATION STATUS: PASS"
        close $fp
        handle_info "ECO input validation PASSED"
    }
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all setup_dirs read_design read_eco_changes validate_inputs

# Exit tool after stage completion
exit
