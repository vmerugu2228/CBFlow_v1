#!/usr/bin/env tclsh
# CBFlow ECO inputs - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# --------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global eco flow project flow_input_handshake

    set design_name [expr {[info exists eco(common,design_name)] ? $eco(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: eco(input,netlist_release_tag) -> eco(input,netlist) ────────
    if {[info exists eco(input,netlist_release_tag)] && $eco(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "ECO" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve eco "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set eco(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── def: eco(input,def_release_tag) -> eco(input,def_file) ─────────────
    if {[info exists eco(input,def_release_tag)] && $eco(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "ECO" "def_file"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve eco "def_file" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set eco(input,def_file) $_file
            handle_info "  DEF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# --------------------------------------------------------------------------
# Procedure: setup_dirs
#   Create directory structure for ECO flow
# --------------------------------------------------------------------------
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
#   Open design library in Fusion Compiler
# --------------------------------------------------------------------------
flow_proc read_design {
    global eco project tech
    handle_info "Loading design into Fusion Compiler..."
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

    # Load ECO change file (Verilog, ECO script, or change list)
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

    # Search default location
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
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Synopsys Fusion Compiler"
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
