#!/usr/bin/env tclsh
# PNR inputs - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting PNR inputs with Cadence Innovus..."
set FLOW_TYPE "PNR"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"
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

    set design_name [expr {[info exists pnr(common,design_name)] ? $pnr(common,design_name) : $flow(design_name)}]

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

    # ── upf: pnr(input,upf_release_tag) -> pnr(input,upf_file) ─────────────
    if {[info exists pnr(input,upf_release_tag)] && $pnr(input,upf_release_tag) ne ""} {
        set hs [get_input_handshake "PNR" "upf_file"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pnr "upf_file" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pnr(input,upf_file) $_file
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
    
    # Check SDC — try sdc_func_file first, then sdc_file fallback
    set _sdc_var ""
    if {[info exists pnr(input,sdc_func_file)] && $pnr(input,sdc_func_file) ne ""} {
        set _sdc_var "input,sdc_func_file"
    } elseif {[info exists pnr(input,sdc_file)] && $pnr(input,sdc_file) ne ""} {
        set _sdc_var "input,sdc_file"
    }
    if {$_sdc_var ne ""} {
        if {[file exists $pnr($_sdc_var)]} {
            handle_info "✓ SDC: [file tail $pnr($_sdc_var)]"
            lappend input_files $pnr($_sdc_var)
        } else {
            handle_error "✗ SDC not found: $pnr($_sdc_var)"
        }
    } else {
        handle_error "✗ SDC not specified in pnr(input,sdc_func_file)"
    }
    
    # Check optional files
    foreach {var_name file_type} {
        "input,def_file" "DEF"
        "input,upf_file" "UPF"
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
    
    # Link SDC — try sdc_func_file first, then sdc_file fallback
    set _sdc_src ""
    if {[info exists pnr(input,sdc_func_file)] && $pnr(input,sdc_func_file) ne ""} {
        set _sdc_src $pnr(input,sdc_func_file)
    } elseif {[info exists pnr(input,sdc_file)] && $pnr(input,sdc_file) ne ""} {
        set _sdc_src $pnr(input,sdc_file)
    }
    if {$_sdc_src ne "" && [file exists $_sdc_src]} {
        set dest_sdc "$input_dir/constraints/[file tail $_sdc_src]"
        if {![file exists $dest_sdc]} {
            file copy $_sdc_src $dest_sdc
            handle_info "Linked SDC: $dest_sdc"
        } else {
            handle_info "SDC already linked: $dest_sdc"
        }
    }
    
    # Link optional files
    foreach {var_name subdir file_type} {
        "input,def_file" "def" "DEF"
        "input,upf_file" "upf" "UPF"
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
    
    set _sdc_rpt ""
    if {[info exists pnr(input,sdc_func_file)] && $pnr(input,sdc_func_file) ne ""} {
        set _sdc_rpt $pnr(input,sdc_func_file)
    } elseif {[info exists pnr(input,sdc_file)] && $pnr(input,sdc_file) ne ""} {
        set _sdc_rpt $pnr(input,sdc_file)
    }
    if {$_sdc_rpt ne ""} {
        puts $fd "SDC: $_sdc_rpt"
        if {[file exists $_sdc_rpt]} {
            puts $fd "  Size: [file size $_sdc_rpt] bytes"
            puts $fd "  Modified: [clock format [file mtime $_sdc_rpt]]"
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
