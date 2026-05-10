#!/usr/bin/env tclsh
# CBFlow POPT inputs - Synopsys PrimeTime | Input preparation for power optimization
set run_dir $::env(CBFLOW_RUN_DIR)
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/POPT/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global popt project tech flow
handle_info "Starting POPT inputs with Synopsys PrimeTime..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/POPT/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ---------------------------------------------------------------------------
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# ---------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global popt flow project flow_input_handshake

    set design_name [expr {[info exists popt(design_name)] ? $popt(design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: popt(input,netlist_release_tag) -> popt(input,netlist) ──────
    if {[info exists popt(input,netlist_release_tag)] && $popt(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "POPT" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve popt "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set popt(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── spef: popt(input,spef_release_tag) -> popt(input,spef) ──────────────
    if {[info exists popt(input,spef_release_tag)] && $popt(input,spef_release_tag) ne ""} {
        set hs [get_input_handshake "POPT" "spef"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve popt "spef" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set popt(input,spef) $_file
            handle_info "  SPEF resolved: $_file"
        }
    }

    # ── sdc: popt(input,sdc_release_tag) -> popt(input,sdc) ────────────────
    if {[info exists popt(input,sdc_release_tag)] && $popt(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "POPT" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve popt "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set popt(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ---------------------------------------------------------------------------
# flow_proc: setup_dirs
# Create directory structure for POPT/PT input stage
# ---------------------------------------------------------------------------
flow_proc setup_dirs {
    handle_info "Setting up POPT input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach d {
        "work/POPT/inputs/netlist"
        "work/POPT/inputs/sdc"
        "work/POPT/inputs/spef"
        "work/POPT/inputs/upf"
        "work/POPT/inputs/library"
        "logs/inputs"
        "reports/popt"
        "results/popt"
    } {
        file mkdir "$run_dir/$d"
    }
    handle_info "POPT input directories created"
}

# ---------------------------------------------------------------------------
# flow_proc: read_design
# Read Verilog netlist and link design in PrimeTime
# ---------------------------------------------------------------------------
flow_proc read_design {
    handle_info "Reading design netlist for POPT..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/POPT/inputs/netlist"

    # Set search path for libraries
    if {[info exists ::tech(SEARCH_PATH)]} {
        set_app_var search_path "$::tech(SEARCH_PATH) $netlist_dir"
    }

    # Read link libraries
    if {[info exists ::tech(LINK_LIBRARY)]} {
        set_app_var link_library $::tech(LINK_LIBRARY)
    }
    if {[info exists ::tech(TARGET_LIBRARY)]} {
        set_app_var target_library $::tech(TARGET_LIBRARY)
    }

    # Read netlist
    if {[info exists ::popt(NETLIST_FILES)]} {
        set netlist_files $::popt(NETLIST_FILES)
    } else {
        set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv"]
    }

    if {[llength $netlist_files] == 0} {
        handle_error "No netlist files found for POPT"
        return -code error "Missing netlist files"
    }

    foreach nf $netlist_files {
        handle_info "Reading Verilog: $nf"
        read_verilog $nf
    }

    # Link design
    if {[info exists ::popt(TOP_MODULE)]} {
        set top $::popt(TOP_MODULE)
    } elseif {[info exists ::project(DESIGN_NAME)]} {
        set top $::project(DESIGN_NAME)
    } else {
        handle_error "TOP_MODULE not defined"
        return -code error "Missing TOP_MODULE"
    }

    handle_info "Linking design: $top"
    link_design $top
    handle_info "Design read and linked successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_constraints
# Read SDC timing constraints
# ---------------------------------------------------------------------------
flow_proc read_constraints {
    handle_info "Reading timing constraints..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set sdc_dir "$run_dir/work/POPT/inputs/sdc"

    if {[info exists ::popt(SDC_FILES)]} {
        set sdc_files $::popt(SDC_FILES)
    } else {
        set sdc_files [glob -nocomplain "$sdc_dir/*.sdc"]
    }

    if {[llength $sdc_files] == 0} {
        handle_error "No SDC constraint files found"
        return -code error "Missing SDC files"
    }

    foreach sdc $sdc_files {
        handle_info "Reading SDC: $sdc"
        read_sdc $sdc
    }

    # Read UPF power intent if available
    if {[info exists ::popt(UPF_FILE)]} {
        handle_info "Reading UPF: $::popt(UPF_FILE)"
        read_power_intent -upf $::popt(UPF_FILE)
        commit_upf
    }

    handle_info "Constraints loaded successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_parasitics
# Read parasitic extraction data (SPEF) for accurate timing
# ---------------------------------------------------------------------------
flow_proc read_parasitics {
    handle_info "Reading parasitic data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set spef_dir "$run_dir/work/POPT/inputs/spef"

    if {[info exists ::popt(SPEF_FILES)]} {
        set spef_files $::popt(SPEF_FILES)
    } else {
        set spef_files [glob -nocomplain "$spef_dir/*.spef" "$spef_dir/*.spef.gz"]
    }

    if {[llength $spef_files] == 0} {
        handle_warning "No SPEF files found - timing will use wireload models"
    } else {
        foreach spef $spef_files {
            handle_info "Reading SPEF: $spef"
            read_parasitics -format spef $spef
        }
        handle_info "Parasitic data loaded - [llength $spef_files] file(s)"
    }

    # Report annotation coverage
    report_annotated_parasitics > "$::REPORTS_DIR/parasitic_annotation.rpt"
    handle_info "Parasitic read completed"
}

# ---------------------------------------------------------------------------
# flow_proc: validate_inputs
# Validate that all required inputs are present and consistent
# ---------------------------------------------------------------------------
flow_proc validate_inputs {
    handle_info "Validating POPT inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Check design is linked
    set current [current_design]
    if {$current eq ""} {
        handle_error "No design linked"
        incr errors
    }

    # Check clocks defined
    set clocks [all_clocks]
    if {[sizeof_collection $clocks] == 0} {
        handle_warning "No clocks defined - check SDC"
    } else {
        handle_info "Found [sizeof_collection $clocks] clock(s)"
    }

    # Write validation report
    set fp [open "$::REPORTS_DIR/input_validation.rpt" w]
    puts $fp "POPT Input Validation Report - [clock format [clock seconds]]"
    puts $fp "============================================================"
    puts $fp "Design:    $current"
    puts $fp "Clocks:    [sizeof_collection $clocks]"
    puts $fp "Errors:    $errors"
    close $fp

    if {$errors > 0} {
        handle_error "Input validation failed"
        return -code error "Validation failed"
    }
    handle_info "POPT input validation passed"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all input flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc inputs_flow {
    handle_info "Executing POPT inputs flow..."
    flow_exec setup_dirs
    flow_exec read_design
    flow_exec read_constraints
    flow_exec read_parasitics
    flow_exec validate_inputs
    handle_info "POPT inputs completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " POPT inputs procedures loaded" }

# Exit tool after stage completion
exit
