#!/usr/bin/env tclsh
# CBFlow PNR inputs - Cadence Innovus | Input preparation for PNR
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global pnr project tech flow
# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR inputs with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ═══════════════════════════════════════════════════════════════════════════════
# PNR INPUTS FILE LINKING
# ═══════════════════════════════════════════════════════════════════════════════

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global pnr flow project flow_input_handshake

    set design_name [expr {[info exists innovus(common,design_name)] ? $innovus(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: pnr(input,netlist_release_tag) -> pnr(input,netlist) ────────
    if {[info exists pnr(input,netlist_release_tag)] && $pnr(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "PNR" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pnr "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pnr(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── sdc: pnr(input,sdc_release_tag) -> pnr(input,sdc_file) ──────────────
    if {[info exists pnr(input,sdc_release_tag)] && $pnr(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "PNR" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pnr "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pnr(input,sdc_file) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    # ── def: pnr(input,def_release_tag) -> pnr(input,def_file) ──────────────
    if {[info exists pnr(input,def_release_tag)] && $pnr(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "PNR" "def"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pnr "def" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pnr(input,def_file) $_file
            handle_info "  DEF resolved: $_file"
        }
    }

    # ── upf: pnr(input,upf_release_tag) -> pnr(input,upf) ──────────────────
    if {[info exists pnr(input,upf_release_tag)] && $pnr(input,upf_release_tag) ne ""} {
        set hs [get_input_handshake "PNR" "upf"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pnr "upf" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pnr(input,upf) $_file
            handle_info "  UPF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

flow_proc enable_mmmc {
    # Enable MMMC scenarios for inputs stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for inputs stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "inputs" "setup"]
    set hold_scenarios [get_effective_scenarios "inputs" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for inputs, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "inputs"]
    
    handle_info "inputs MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Tool-specific MMMC scenario setup would go here
    handle_info "MMMC scenarios configured for inputs stage"
}

flow_proc validate_input_files {
    handle_info "Validating PNR input files..."
    
    # Get required input files
    global pnr
    set input_files [list]
    
    # Check netlist
    if {[info exists pnr(input,netlist)]} {
        if {[file exists $pnr(input,netlist)]} {
            handle_info "✓ Netlist: [file tail $pnr(input,netlist)]"
            lappend input_files $pnr(input,netlist)
        } else {
            handle_error "✗ Netlist not found: $pnr(input,netlist)"
        }
    } else {
        handle_error "✗ Netlist not specified in pnr(input,netlist)"
    }
    
    # Check SDC
    if {[info exists pnr(input,sdc)]} {
        if {[file exists $pnr(input,sdc)]} {
            handle_info "✓ SDC: [file tail $pnr(input,sdc)]"
            lappend input_files $pnr(input,sdc)
        } else {
            handle_error "✗ SDC not found: $pnr(input,sdc)"
        }
    } else {
        handle_error "✗ SDC not specified in pnr(input,sdc)"
    }
    
    # Check optional files
    foreach {var_name file_type} {
        "input,def" "DEF"
        "input,upf" "UPF" 
        "input,io_file" "I/O placement"
    } {
        if {[info exists pnr($var_name)] && $pnr($var_name) ne ""} {
            if {[file exists $pnr($var_name)]} {
                handle_info "✓ $file_type: [file tail $pnr($var_name)]"
                lappend input_files $pnr($var_name)
            } else {
                handle_warning "✗ $file_type not found: $pnr($var_name)"
            }
        }
    }
    
    handle_info "Input file validation completed"
    return $input_files
}

flow_proc link_input_files {
    handle_info "Linking input files to work directory..."
    
    # Get validated input files
    set input_files [validate_input_files]
    
    # Create input directories
    set input_dir "work/PNR/inputs"
    ensure_directory "$input_dir/netlist"
    ensure_directory "$input_dir/constraints"
    ensure_directory "$input_dir/def"
    ensure_directory "$input_dir/upf"
    ensure_directory "$input_dir/io"
    
    global pnr project
    
    # Link netlist
    if {[info exists pnr(input,netlist)] && [file exists $pnr(input,netlist)]} {
        set dest_netlist "$input_dir/netlist/[file tail $pnr(input,netlist)]"
        if {![file exists $dest_netlist]} {
            file copy $pnr(input,netlist) $dest_netlist
            handle_info "Linked netlist: $dest_netlist"
        } else {
            handle_info "Netlist already linked: $dest_netlist"
        }
    }
    
    # Link SDC
    if {[info exists pnr(input,sdc)] && [file exists $pnr(input,sdc)]} {
        set dest_sdc "$input_dir/constraints/[file tail $pnr(input,sdc)]"
        if {![file exists $dest_sdc]} {
            file copy $pnr(input,sdc) $dest_sdc
            handle_info "Linked SDC: $dest_sdc"
        } else {
            handle_info "SDC already linked: $dest_sdc"
        }
    }
    
    # Link optional files
    foreach {var_name subdir file_type} {
        "input,def" "def" "DEF"
        "input,upf" "upf" "UPF"
        "input,io_file" "io" "I/O placement"
    } {
        if {[info exists pnr($var_name)] && $pnr($var_name) ne "" && [file exists $pnr($var_name)]} {
            set dest_file "$input_dir/$subdir/[file tail $pnr($var_name)]"
            if {![file exists $dest_file]} {
                file copy $pnr($var_name) $dest_file
                handle_info "Linked $file_type: $dest_file"
            } else {
                handle_info "$file_type already linked: $dest_file"
            }
        }
    }
    
    handle_info "Input file linking completed"
}

flow_proc check_design_consistency {
    handle_info "Checking design consistency..."
    
    global pnr project
    
    # Basic design checks
    if {[info exists project(top_module)]} {
        handle_info "Top module: $project(top_module)"
    } else {
        handle_warning "Top module not specified in project(top_module)"
    }
    
    if {[info exists project(clock,period)]} {
        handle_info "Clock period: $project(clock,period)ns"
    } else {
        handle_warning "Clock period not specified in project(clock,period)"
    }
    
    if {[info exists project(clock,ports)]} {
        handle_info "Clock ports: $project(clock,ports)"
    } else {
        handle_warning "Clock ports not specified in project(clock,ports)"
    }
    
    handle_info "Design consistency check completed"
}

flow_proc inputs_complete {
    handle_info "Inputs stage complete"

    # Generate input summary report
    file mkdir "$::REPORTS_DIR"

    set summary_file "$::REPORTS_DIR/input_summary.rpt"
    set fd [open $summary_file "w"]
    puts $fd "# PNR Input Summary Report"
    puts $fd "# Generated: [clock format [clock seconds]]"
    puts $fd ""
    
    global pnr project
    
    # Write input file information
    puts $fd "=== INPUT FILES ==="
    if {[info exists pnr(input,netlist)]} {
        puts $fd "Netlist: $pnr(input,netlist)"
        if {[file exists $pnr(input,netlist)]} {
            puts $fd "  Size: [file size $pnr(input,netlist)] bytes"
            puts $fd "  Modified: [clock format [file mtime $pnr(input,netlist)]]"
        }
    }
    
    if {[info exists pnr(input,sdc)]} {
        puts $fd "SDC: $pnr(input,sdc)"
        if {[file exists $pnr(input,sdc)]} {
            puts $fd "  Size: [file size $pnr(input,sdc)] bytes"
            puts $fd "  Modified: [clock format [file mtime $pnr(input,sdc)]]"
        }
    }
    
    # Write design information
    puts $fd ""
    puts $fd "=== DESIGN INFORMATION ==="
    if {[info exists project(top_module)]} {
        puts $fd "Top module: $project(top_module)"
    }
    if {[info exists project(clock,period)]} {
        puts $fd "Clock period: $project(clock,period)ns"
    }
    if {[info exists project(clock,ports)]} {
        puts $fd "Clock ports: $project(clock,ports)"
    }
    
    close $fd
    handle_info "Input summary generated: $summary_file"

    log_stage_status "inputs" "COMPLETE" "Input files validated and prepared successfully"
}



# Exit tool after stage completion
exit
