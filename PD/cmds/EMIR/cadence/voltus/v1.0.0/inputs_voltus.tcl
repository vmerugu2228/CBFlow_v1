#!/usr/bin/env tclsh
# EMIR Inputs - Cadence Voltus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting EMIR inputs stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/inputs1"
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
# │                        RESOLVE INPUTS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global emir flow project flow_input_handshake

    set design_name [expr {[info exists emir(common,design_name)] && $emir(common,design_name) ne "" ? $emir(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available -- using direct paths only"
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

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_libraries {
    global emir tech flow
    handle_info "Reading timing libraries..."

    # Read Liberty (.lib) files from tech config
    # Uses track-specific combined timing list: tech($tech(track),lib_nom)
    set _trk $tech(track)
    if {[info exists tech(${_trk},lib_nom)]} {
        foreach lib $tech(${_trk},lib_nom) {
            if {[file exists $lib]} {
                handle_info "  read_lib $lib"
                read_lib $lib
            } else {
                handle_warning "Liberty file not found: $lib"
            }
        }
    } elseif {[info exists tech(lib,timing)]} {
        # Fallback to backward-compat alias
        foreach lib $tech(lib,timing) {
            if {[file exists $lib]} {
                handle_info "  read_lib $lib"
                read_lib $lib
            } else {
                handle_warning "Liberty file not found: $lib"
            }
        }
    } else {
        handle_error "No timing libraries defined -- set tech($tech(track),lib_nom) in tech config"
    }

    handle_info "Timing libraries loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ PHYSICAL                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_physical {
    global emir flow project tech
    handle_info "Reading LEF physical data..."

    # Read technology LEF (metal_stack × track)
    set _tech_lef $tech($project(metal_stack),$project(track_variant),lef_tech)
    if {$_tech_lef ne ""} {
        handle_info "  read_lef [file tail $_tech_lef]"
        read_lef $_tech_lef
    }

    # Read cell LEFs from track-specific list: tech($tech(track),lef)
    set _trk $tech(track)
    if {[info exists tech(${_trk},lef)]} {
        foreach lef $tech(${_trk},lef) {
            if {[file exists $lef]} {
                handle_info "  read_lef $lef"
                read_lef $lef
            } else {
                handle_warning "Cell LEF not found: $lef"
            }
        }
    } else {
        handle_error "No LEF files defined -- set tech($tech(track),lef) in tech config"
    }

    handle_info "LEF data loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ DESIGN                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_design {
    global emir flow
    handle_info "Reading design netlist and DEF..."

    # Read gate-level netlist
    if {[info exists emir(input,netlist)] && $emir(input,netlist) ne ""} {
        if {[file exists $emir(input,netlist)]} {
            handle_info "  read_verilog $emir(input,netlist)"
            read_verilog $emir(input,netlist)
        } else {
            handle_error "Netlist file not found: $emir(input,netlist)"
        }
    } else {
        handle_error "emir(input,netlist) not defined"
    }

    # Set top module
    handle_info "  set_top_module $flow(design_name)"
    set_top_module $flow(design_name)

    # Read DEF (placement + routing)
    if {[info exists emir(input,def_file)] && $emir(input,def_file) ne ""} {
        if {[file exists $emir(input,def_file)]} {
            handle_info "  read_def $emir(input,def_file)"
            read_def $emir(input,def_file)
        } else {
            handle_error "DEF file not found: $emir(input,def_file)"
        }
    } else {
        handle_error "emir(input,def_file) not defined"
    }

    handle_info "Design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ PARASITICS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_parasitics {
    global emir flow
    handle_info "Reading parasitic data..."

    if {[info exists emir(input,spef)] && $emir(input,spef) ne ""} {
        if {[file exists $emir(input,spef)]} {
            handle_info "  read_spef $emir(input,spef)"
            read_spef $emir(input,spef)
        } else {
            handle_error "SPEF file not found: $emir(input,spef)"
        }
    } else {
        handle_warning "emir(input,spef) not defined -- IR drop accuracy may be reduced"
    }

    handle_info "Parasitics loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        SETUP POWER NETS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_power_nets {
    global emir flow
    handle_info "Configuring power/ground net connections..."

    # Get power/ground net names from config
    set vdd_net [expr {[info exists emir(power,vdd_net)] && $emir(power,vdd_net) ne "" ? $emir(power,vdd_net) : "VDD"}]
    set vss_net [expr {[info exists emir(power,vss_net)] && $emir(power,vss_net) ne "" ? $emir(power,vss_net) : "VSS"}]

    # Connect global power nets to cell pins
    handle_info "  globalNetConnect $vdd_net -type pgpin -pin $vdd_net -all"
    globalNetConnect $vdd_net -type pgpin -pin $vdd_net -all
    handle_info "  globalNetConnect $vss_net -type pgpin -pin $vss_net -all"
    globalNetConnect $vss_net -type pgpin -pin $vss_net -all

    # Tie-high/tie-low connections
    globalNetConnect $vdd_net -type tiehi
    globalNetConnect $vss_net -type tielo

    # Register power/ground nets with Voltus
    handle_info "  set_db init_power_nets {$vdd_net}"
    set_db init_power_nets [list $vdd_net]
    handle_info "  set_db init_ground_nets {$vss_net}"
    set_db init_ground_nets [list $vss_net]

    handle_info "Power net setup completed: VDD=$vdd_net VSS=$vss_net"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        READ CONSTRAINTS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_constraints {
    global emir flow
    handle_info "Reading timing constraints..."

    # Read SDC if available (needed for clock-aware power analysis)
    if {[info exists emir(input,sdc)] && $emir(input,sdc) ne ""} {
        if {[file exists $emir(input,sdc)]} {
            handle_info "  read_sdc $emir(input,sdc)"
            read_sdc $emir(input,sdc)
        } else {
            handle_warning "SDC file not found: $emir(input,sdc)"
        }
    } else {
        handle_warning "No SDC file specified -- clock power estimation disabled"
    }

    handle_info "Constraints loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        SETUP POWER CONFIG                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_power_config {
    global emir flow
    handle_info "Setting power analysis configuration..."

    # Operating temperature
    if {[info exists emir(thermal,ambient_temperature)] && $emir(thermal,ambient_temperature) ne ""} {
        handle_info "  set_db power_temperature $emir(thermal,ambient_temperature)"
        set_db power_temperature $emir(thermal,ambient_temperature)
    } elseif {[info exists emir(voltus,junction_temp)] && $emir(voltus,junction_temp) ne ""} {
        handle_info "  set_db power_temperature $emir(voltus,junction_temp)"
        set_db power_temperature $emir(voltus,junction_temp)
    }

    # Default supply voltage
    if {[info exists emir(power,supply_voltage)] && $emir(power,supply_voltage) ne ""} {
        handle_info "  set_db power_default_voltage $emir(power,supply_voltage)"
        set_db power_default_voltage $emir(power,supply_voltage)
    }

    # Multi-threading
    if {[info exists emir(voltus,num_cpus)] && $emir(voltus,num_cpus) ne ""} {
        handle_info "  set_multi_cpu_usage -local_cpu $emir(voltus,num_cpus)"
        set_multi_cpu_usage -local_cpu $emir(voltus,num_cpus)
    }

    handle_info "Power configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        VALIDATE INPUTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_inputs {
    global emir flow
    handle_info "Validating EMIR input completeness..."
    set errors 0

    # Check mandatory inputs
    if {![info exists emir(input,netlist)] || $emir(input,netlist) eq ""} {
        handle_warning "emir(input,netlist) not defined"
        incr errors
    } elseif {![file exists $emir(input,netlist)]} {
        handle_warning "Netlist file not found: $emir(input,netlist)"
        incr errors
    }

    if {![info exists emir(input,def_file)] || $emir(input,def_file) eq ""} {
        handle_warning "emir(input,def_file) not defined"
        incr errors
    } elseif {![file exists $emir(input,def_file)]} {
        handle_warning "DEF file not found: $emir(input,def_file)"
        incr errors
    }

    # Optional but recommended
    if {![info exists emir(input,spef)] || $emir(input,spef) eq ""} {
        handle_warning "emir(input,spef) not defined -- IR analysis accuracy reduced"
    }

    # Generate validation summary
    set summary_file "$::REPORTS_DIR/inputs_summary.txt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "================================================================"
    puts $fp "CBFlow EMIR Input Summary - Voltus"
    puts $fp "================================================================"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Voltus"
    puts $fp "Design: $flow(design_name)"
    puts $fp ""
    puts $fp "Input Files:"
    if {[info exists emir(input,netlist)]}  { puts $fp "  Netlist:  $emir(input,netlist)" }
    if {[info exists emir(input,def_file)]} { puts $fp "  DEF:      $emir(input,def_file)" }
    if {[info exists emir(input,spef)]}     { puts $fp "  SPEF:     $emir(input,spef)" }
    if {[info exists emir(input,sdc)]}      { puts $fp "  SDC:      $emir(input,sdc)" }
    puts $fp ""
    if {$errors > 0} {
        puts $fp "WARNINGS: $errors input issues detected"
    } else {
        puts $fp "STATUS: All required inputs present"
    }
    close $fp

    handle_info "Input validation completed ($errors warnings)"
    handle_info "  Summary: $summary_file"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "================================================================"
handle_info " CBFlow EMIR inputs with Voltus"
handle_info "================================================================"

flow_proc inputs_flow {
    handle_info "Executing EMIR inputs flow..."
    flow_exec resolve_inputs
    flow_exec read_libraries
    flow_exec read_physical
    flow_exec read_design
    flow_exec read_parasitics
    flow_exec setup_power_nets
    flow_exec read_constraints
    flow_exec setup_power_config
    flow_exec validate_inputs
    handle_info "EMIR inputs completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " EMIR inputs procedures loaded" }

# Exit tool after stage completion
exit
