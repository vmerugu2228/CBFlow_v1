#!/usr/bin/env tclsh
# CBFlow EMIR inputs - Synopsys RedHawk

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# --------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global emir flow project flow_input_handshake

    set design_name [expr {[info exists emir(common,design_name)] ? $emir(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── def: emir(input,def_release_tag) -> emir(input,def_file) ───────────
    if {[info exists emir(input,def_release_tag)] && $emir(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "EMIR" "def_file"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve emir "def_file" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set emir(input,def_file) $_file
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

# --------------------------------------------------------------------------
# Procedure: setup_dirs
#   Create directory structure for EMIR analysis
# --------------------------------------------------------------------------
flow_proc setup_dirs {
    handle_info "Setting up EMIR input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/EMIR/inputs/def" "work/EMIR/inputs/lef" "work/EMIR/inputs/netlist"
        "work/EMIR/inputs/spef" "work/EMIR/inputs/lib" "work/EMIR/inputs/power"
        "work/EMIR/power_analysis/run" "work/EMIR/ir_drop/run" "work/EMIR/thermal_analysis/run"
        "logs/emir" "reports/emir/power" "reports/emir/ir_drop" "reports/emir/thermal"
        "results/emir"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "EMIR input directories created"
}

# --------------------------------------------------------------------------
# Procedure: read_design
#   Import design into RedHawk using DEF/LEF
# --------------------------------------------------------------------------
flow_proc read_design {
    global emir project tech
    handle_info "Reading design into RedHawk..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # DEF file
    if {[info exists emir(input,def_file)]} {
        set def_file $emir(input,def_file)
    } else {
        set def_candidates [glob -nocomplain "$run_dir/work/EMIR/inputs/def/*.def"]
        if {[llength $def_candidates] > 0} {
            set def_file [lindex $def_candidates 0]
        } else {
            handle_error "No DEF file specified in emir(input,def_file)"
            return
        }
    }

    # LEF files
    if {[info exists emir(input,lef)]} {
        set lef_files $emir(input,lef)
    } else {
        set lef_files [glob -nocomplain "$run_dir/work/EMIR/inputs/lef/*.lef"]
    }

    # Import design
    handle_info "Importing design: DEF=$def_file"
    import_design -def $def_file
    foreach lef $lef_files {
        handle_info "Reading LEF: $lef"
        import_design -lef $lef
    }

    # Read SPEF for parasitic data
    if {[info exists emir(input,spef)]} {
        handle_info "Reading SPEF: $emir(input,spef)"
        read_parasitics -spef $emir(input,spef)
    } else {
        set spef_candidates [glob -nocomplain "$run_dir/work/EMIR/inputs/spef/*.spef" "$run_dir/work/EMIR/inputs/spef/*.spef.gz"]
        foreach spef $spef_candidates {
            handle_info "Reading SPEF: $spef"
            read_parasitics -spef $spef
        }
    }

    # Read liberty timing libraries
    if {[info exists emir(input,lib)]} {
        foreach lib $emir(input,lib) {
            handle_info "Reading Liberty: $lib"
            read_lib $lib
        }
    }

    set ::emir_def_file $def_file
    handle_info "Design import completed"
}

# --------------------------------------------------------------------------
# Procedure: read_power_data
#   Load switching activity and power data for analysis
# --------------------------------------------------------------------------
flow_proc read_power_data {
    global emir project
    handle_info "Reading power data for EMIR analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Read switching activity file (VCD/SAIF)
    if {[info exists emir(input,activity)]} {
        set activity_file $emir(input,activity)
        handle_info "Reading activity file: $activity_file"
        read_activity_file -format [expr {[string match "*.vcd" $activity_file] ? "vcd" : "saif"}] $activity_file
    } else {
        set activity_candidates [glob -nocomplain "$run_dir/work/EMIR/inputs/power/*.vcd" "$run_dir/work/EMIR/inputs/power/*.saif"]
        if {[llength $activity_candidates] > 0} {
            set activity_file [lindex $activity_candidates 0]
            handle_info "Reading activity file: $activity_file"
            read_activity_file -format [expr {[string match "*.vcd" $activity_file] ? "vcd" : "saif"}] $activity_file
        } else {
            handle_warning "No switching activity file found; using default activity"
            if {[info exists emir(default_activity)]} {
                set_switching_activity -default $emir(default_activity)
            } else {
                set_switching_activity -default 0.1
            }
        }
    }

    # Read power constraints
    if {[info exists emir(power,voltage)]} {
        handle_info "Setting supply voltage: $emir(power,voltage)V"
        set_voltage $emir(power,voltage)
    }

    handle_info "Power data loading completed"
}

# --------------------------------------------------------------------------
# Procedure: validate_inputs
#   Validate all required EMIR inputs are present
# --------------------------------------------------------------------------
flow_proc validate_inputs {
    global emir project tech
    handle_info "Validating EMIR inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors {}

    if {![info exists ::emir_def_file] || ![file exists $::emir_def_file]} {
        lappend errors "DEF file not loaded"
    }

    if {![info exists project(top_module)] && ![info exists emir(common,top_cell)]} {
        lappend errors "Top cell not defined"
    }

    # Generate validation summary
    set vf "$::REPORTS_DIR/inputs_validation.rpt"
    set fp [open $vf w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow EMIR - Input Validation Report"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Synopsys RedHawk"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp ""

    if {[llength $errors] > 0} {
        puts $fp "VALIDATION STATUS: FAIL"
        foreach e $errors { puts $fp "  - $e" }
        close $fp
        foreach e $errors { handle_error "Input validation: $e" }
    } else {
        puts $fp "VALIDATION STATUS: PASS"
        close $fp
        handle_info "EMIR input validation PASSED"
    }
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all setup_dirs read_design read_power_data validate_inputs

# Exit tool after stage completion
exit
