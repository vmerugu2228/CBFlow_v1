#!/usr/bin/env tclsh
# CBFlow ECO inputs - Cadence Innovus

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
#   Load the routed design into Innovus. Two paths:
#     1. restoreDesign  — preferred (faster, complete state)
#     2. read_verilog + defIn + read_sdc — fallback for ASCII-only handoff
# --------------------------------------------------------------------------
flow_proc read_design {
    global eco project tech
    handle_info "Loading design into Innovus..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    if {[info exists eco(input,db)] && $eco(input,db) ne ""} {
        # Path 1: restoreDesign from a saved Innovus database
        set top [expr {[info exists project(top_module)] ? $project(top_module) : ""}]
        handle_info "restoreDesign $eco(input,db) $top"
        restoreDesign $eco(input,db) $top
    } else {
        # Path 2: rebuild from ASCII inputs
        if {[info exists eco(input,nlib)] && $eco(input,nlib) ne ""} {
            # If the user has only an NDM lib (FC handoff), Innovus can't read it
            handle_error "Innovus cannot consume FC NDM lib ($eco(input,nlib)); provide eco(input,db) or eco(input,netlist) + eco(input,def_file)"
            return
        }

        if {[info exists eco(input,netlist)] && $eco(input,netlist) ne ""} {
            handle_info "read_verilog $eco(input,netlist)"
            read_verilog $eco(input,netlist)
        }
        if {[info exists project(top_module)]} {
            handle_info "set_top_module $project(top_module)"
            set_top_module $project(top_module)
        }
        if {[info exists eco(input,def_file)] && $eco(input,def_file) ne ""} {
            handle_info "defIn $eco(input,def_file)"
            defIn $eco(input,def_file)
        } else {
            set def_candidates [glob -nocomplain "$run_dir/work/ECO/inputs/def/*.def"]
            foreach def $def_candidates {
                handle_info "defIn $def"
                defIn $def
            }
        }
        if {[info exists eco(input,sdc)] && $eco(input,sdc) ne ""} {
            handle_info "read_sdc $eco(input,sdc)"
            read_sdc $eco(input,sdc)
        } else {
            set sdc_candidates [glob -nocomplain "$run_dir/work/ECO/inputs/sdc/*.sdc"]
            foreach sdc $sdc_candidates {
                handle_info "read_sdc $sdc"
                read_sdc $sdc
            }
        }
    }

    handle_info "Design loading completed"
}

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
    puts $fp "Tool: Cadence Innovus"
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
flow_exec_all setup_dirs read_design read_eco_changes validate_inputs

exit
