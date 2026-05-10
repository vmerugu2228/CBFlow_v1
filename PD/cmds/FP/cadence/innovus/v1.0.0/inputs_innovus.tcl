#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP Inputs Stage for Innovus
# Description: Read libraries, design netlist, and constraints for floorplanning
# Usage: Source this file in Innovus or run via CBFlow
# Output: Libraries, netlist, and constraints loaded into Innovus session
# ═══════════════════════════════════════════════════════════════════════════════

# Validate required environment variables
if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
    puts "ERROR: FLOW_DIR not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

set flow_dir $::env(FLOW_DIR)

# Source flow utilities using release version
set utils_path "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find flow utilities at: $utils_path"
    exit 1
}

set run_dir $::env(CBFLOW_RUN_DIR)

set WORK_DIR "$run_dir/work/FP/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

handle_info "Starting CBFlow FP inputs stage for Innovus"

# Define common procedures used in config files
if {[info procs INFO] eq ""} {
    proc INFO {} {
        return "INFO"
    }
}
if {[info procs WARNING] eq ""} {
    proc WARNING {} {
        return "WARNING"
    }
}

# Define flow_proc if not already defined
if {[info procs flow_proc] eq ""} {
    proc flow_proc {name body} {
        proc $name {} $body
        handle_info "Flow procedure '$name' defined"
    }
}

# Source generated configuration file (from setup stage)
set flow_type "FP"
set config_files [list \
    "config.tcl" \
    "work/$flow_type/inputs/run/config.tcl" \
    "../work/$flow_type/inputs/run/config.tcl" \
]

set config_found 0
foreach config_file $config_files {
    if {[file exists $config_file]} {
        handle_info "Sourcing configuration: $config_file"
        if {[catch {source $config_file} error]} {

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
            handle_warning "Minor error in config file $config_file: $error"
            handle_info "Continuing with available configuration..."
        }
        set config_found 1
        break
    }
}

if {!$config_found} {
    handle_error "Cannot find generated config file. Run 'make inputs_setup' first."
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOKS - Inputs Process
# ═══════════════════════════════════════════════════════════════════════════════

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global fp flow project flow_input_handshake

    set design_name [expr {[info exists fp(design_name)] ? $fp(design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: fp(input,netlist_release_tag) -> fp(input,netlist) ──────────
    if {[info exists fp(input,netlist_release_tag)] && $fp(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "FP" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve fp "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set fp(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── sdc: fp(input,sdc_release_tag) -> fp(input,sdc) ────────────────────
    if {[info exists fp(input,sdc_release_tag)] && $fp(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "FP" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve fp "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set fp(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

flow_proc setup_dirs {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Setting up working directories for inputs stage..."

    # Create standard directory structure
    set work_dirs {"reports" "results" "logs" "scripts" "data"}
    foreach dir $work_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created directory: $dir"
        }
    }

    # Set project root relative to FLOW_DIR
    if {[info exists FLOW_DIR]} {
        set ::project_root [file dirname $FLOW_DIR]
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set ::project_root [file dirname $::env(FLOW_DIR)]
    } else {
        handle_error "Cannot determine project root directory"
        return 0
    }

    handle_info "Project root: $::project_root"
    handle_info "Working directories setup completed"
}

flow_proc read_libraries {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Reading technology and standard cell libraries..."

    set project_root [file dirname $FLOW_DIR]

    # Read technology LEF
    if {[info exists tech(lef,technology)]} {
        set expanded_lef [subst $tech(lef,technology)]
        set lef_path [file join $project_root $expanded_lef]
        if {[file exists $lef_path]} {
            handle_info "Reading technology LEF: [file tail $lef_path]"
            read_lef $lef_path
        } else {
            handle_error "Technology LEF not found: $lef_path"
            return 0
        }
    } else {
        handle_error "tech(lef,technology) not defined in configuration"
        return 0
    }

    # Read standard cell LEF
    if {[info exists tech(lef,standard_cells)]} {
        set expanded_lef [subst $tech(lef,standard_cells)]
        set lef_path [file join $project_root $expanded_lef]
        if {[file exists $lef_path]} {
            handle_info "Reading standard cell LEF: [file tail $lef_path]"
            read_lef $lef_path
        } else {
            handle_error "Standard cell LEF not found: $lef_path"
            return 0
        }
    } else {
        handle_error "tech(lef,standard_cells) not defined in configuration"
        return 0
    }

    # Read macro LEF files if any
    if {[info exists tech(lef,macros)]} {
        foreach lef $tech(lef,macros) {
            set expanded_lef [subst $lef]
            set lef_path [file join $project_root $expanded_lef]
            if {[file exists $lef_path]} {
                handle_info "Reading macro LEF: [file tail $lef_path]"
                read_lef $lef_path
            } else {
                handle_warning "Macro LEF not found: $lef_path"
            }
        }
    }

    # Read timing libraries
    if {[info exists tech(lib,timing)]} {
        foreach lib $tech(lib,timing) {
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                handle_info "Reading timing library: [file tail $lib_path]"
                read_lib $lib_path
            } else {
                handle_warning "Timing library not found: $lib_path"
            }
        }
    } else {
        handle_warning "tech(lib,timing) not defined - no timing libraries loaded"
    }

    handle_info "Libraries loaded successfully"
}

flow_proc read_design {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Reading design netlist from synthesis output..."

    # Get netlist from synthesis output
    if {[info exists fp(input,netlist)]} {
        set netlist_file $fp(input,netlist)
    } elseif {[info exists project(synth,netlist)]} {
        set netlist_file $project(synth,netlist)
    } else {
        handle_error "No netlist specified. Set fp(input,netlist) or project(synth,netlist)."
        return 0
    }

    # Resolve path
    if {![file exists $netlist_file]} {
        set project_root [file dirname $FLOW_DIR]
        set netlist_file [file join $project_root $netlist_file]
    }

    if {![file exists $netlist_file]} {
        handle_error "Netlist file not found: $netlist_file"
        return 0
    }

    handle_info "Reading Verilog netlist: [file tail $netlist_file]"
    read_verilog $netlist_file

    # Set top module
    if {[info exists project(top_module)]} {
        handle_info "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    } else {
        handle_error "project(top_module) not defined"
        return 0
    }

    handle_info "Design netlist loaded successfully"
}

flow_proc read_constraints {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Reading timing constraints and power intent..."

    set project_root [file dirname $FLOW_DIR]

    # Read SDC constraints
    if {[info exists fp(input,sdc)]} {
        set sdc_file $fp(input,sdc)
        if {![file exists $sdc_file]} {
            set sdc_file [file join $project_root $sdc_file]
        }
        if {[file exists $sdc_file]} {
            handle_info "Reading SDC constraints: [file tail $sdc_file]"
            read_sdc $sdc_file
        } else {
            handle_warning "SDC file not found: $sdc_file"
        }
    } else {
        handle_warning "fp(input,sdc) not defined - no SDC constraints loaded"
    }

    # Read power intent (CPF or UPF)
    if {[info exists fp(input,cpf)]} {
        set cpf_file $fp(input,cpf)
        if {![file exists $cpf_file]} {
            set cpf_file [file join $project_root $cpf_file]
        }
        if {[file exists $cpf_file]} {
            handle_info "Reading CPF power intent: [file tail $cpf_file]"
            read_power_intent -cpf $cpf_file
        } else {
            handle_warning "CPF file not found: $cpf_file"
        }
    } elseif {[info exists fp(input,upf)]} {
        set upf_file $fp(input,upf)
        if {![file exists $upf_file]} {
            set upf_file [file join $project_root $upf_file]
        }
        if {[file exists $upf_file]} {
            handle_info "Reading UPF power intent: [file tail $upf_file]"
            read_power_intent -1801 $upf_file
        } else {
            handle_warning "UPF file not found: $upf_file"
        }
    } else {
        handle_info "No power intent file (CPF/UPF) specified"
    }

    handle_info "Constraints loaded successfully"
}

flow_proc validate_inputs {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Validating loaded inputs..."

    set validation_errors 0

    # Check design is loaded
    handle_info "Checking design connectivity..."
    if {[catch {check_design -all} result]} {
        handle_warning "Design check reported issues: $result"
        incr validation_errors
    }

    # Verify timing constraints are present
    handle_info "Verifying timing constraints..."
    if {[catch {report_constraint -all_violators} result]} {
        handle_warning "Constraint check reported issues: $result"
    }

    # Check for missing cells/macros
    handle_info "Checking for unresolved references..."
    if {[catch {check_library} result]} {
        handle_warning "Library check reported issues: $result"
        incr validation_errors
    }

    # Generate input validation report
    set report_file "$::REPORTS_DIR/inputs_validation.rpt"
    handle_info "Generating validation report: $report_file"
    if {[catch {report_design > $report_file} result]} {
        handle_warning "Could not generate design report: $result"
    }

    # Generate cell usage report
    if {[catch {report_cells > $::REPORTS_DIR/cell_usage.rpt} result]} {
        handle_warning "Could not generate cell usage report: $result"
    }

    if {$validation_errors > 0} {
        handle_warning "Input validation completed with $validation_errors warning(s)"
    } else {
        handle_info "Input validation passed - all inputs loaded correctly"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "═══════════════════════════════════════════════════════════════"
handle_info "CBFlow FP Inputs Stage - Starting Execution"
handle_info "═══════════════════════════════════════════════════════════════"

# Execute flow procedures in sequence
set flow_steps {
    setup_dirs
    read_libraries
    read_design
    read_constraints
    validate_inputs
}

foreach step $flow_steps {
    handle_info "Executing flow step: $step"

    if {[catch {$step} error]} {
        handle_error "Flow step '$step' failed: $error"
        exit 1
    }

    handle_info "Flow step '$step' completed successfully"
}

handle_info "CBFlow FP inputs stage completed successfully"

# Exit tool after stage completion
exit
