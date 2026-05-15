#!/usr/bin/env tclsh
# CBFlow STA inputs - Synopsys PrimeTime | Input preparation for static timing analysis
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/STA/inputs/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow
# Source PT tool config
set _tool_config "[file dirname [info script]]/pt_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting STA inputs with Synopsys PrimeTime..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/inputs"
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
    global sta flow project flow_input_handshake

    set design_name [expr {[info exists pt(common,design_name)] ? $pt(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: sta(input,netlist_release_tag) -> sta(input,netlist) ────────
    if {[info exists sta(input,netlist_release_tag)] && $sta(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── sdc: sta(input,sdc_release_tag) -> sta(input,sdc) ──────────────────
    if {[info exists sta(input,sdc_release_tag)] && $sta(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    # ── spef: sta(input,spef_release_tag) -> sta(input,spef) ────────────────
    if {[info exists sta(input,spef_release_tag)] && $sta(input,spef_release_tag) ne ""} {
        set hs [get_input_handshake "STA" "spef"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve sta "spef" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set sta(input,spef) $_file
            handle_info "  SPEF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ---------------------------------------------------------------------------
# flow_proc: setup_dirs
# Create directory structure for STA/PT input stage
# ---------------------------------------------------------------------------
flow_proc setup_dirs {
    handle_info "Setting up STA input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/STA/inputs/netlist"
        "work/STA/inputs/sdc"
        "work/STA/inputs/spef"
        "work/STA/inputs/library"
        "work/STA/inputs/scenarios"
        "logs/inputs"
        "reports/sta"
        "results/sta"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "STA input directories created"
}

# ---------------------------------------------------------------------------
# flow_proc: read_design
# Read Verilog netlist and link design in PrimeTime
# ---------------------------------------------------------------------------
flow_proc read_design {
    handle_info "Reading design netlist for STA..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/STA/inputs/netlist"

    # Set search path
    if {[info exists ::tech(SEARCH_PATH)]} {
        set_app_var search_path "$::tech(SEARCH_PATH) $netlist_dir"
    }

    # Set libraries
    if {[info exists ::tech(LINK_LIBRARY)]} {
        set_app_var link_library $::tech(LINK_LIBRARY)
    }
    if {[info exists ::tech(TARGET_LIBRARY)]} {
        set_app_var target_library $::tech(TARGET_LIBRARY)
    }

    # Read netlist files
    if {[info exists ::sta(NETLIST_FILES)]} {
        set netlist_files $::sta(NETLIST_FILES)
    } else {
        set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv"]
    }

    if {[llength $netlist_files] == 0} {
        handle_error "No netlist files found for STA"
        return -code error "Missing netlist files"
    }

    foreach nf $netlist_files {
        handle_info "Reading Verilog: $nf"
        read_verilog $nf
    }

    # Link design
    if {[info exists ::sta(TOP_MODULE)]} {
        set top $::sta(TOP_MODULE)
    } elseif {[info exists ::project(DESIGN_NAME)]} {
        set top $::project(DESIGN_NAME)
    } else {
        handle_error "TOP_MODULE not defined"
        return -code error "Missing TOP_MODULE"
    }

    handle_info "Linking design: $top"
    link_design $top

    # Set operating conditions
    if {[info exists ::sta(OPERATING_CONDITIONS)]} {
        set_operating_conditions $::sta(OPERATING_CONDITIONS)
        handle_info "Operating conditions set: $::sta(OPERATING_CONDITIONS)"
    }

    handle_info "Design read and linked successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_constraints
# Read SDC timing constraints for STA
# ---------------------------------------------------------------------------
flow_proc read_constraints {
    handle_info "Reading timing constraints..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set sdc_dir "$run_dir/work/STA/inputs/sdc"

    if {[info exists ::sta(SDC_FILES)]} {
        set sdc_files $::sta(SDC_FILES)
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

    # Apply mode-specific SDC if defined
    if {[info exists ::sta(MODE_SDC)]} {
        foreach {mode sdc_file} $::sta(MODE_SDC) {
            handle_info "Reading mode SDC ($mode): $sdc_file"
            read_sdc -add $sdc_file
        }
    }

    # Report constraint coverage
    report_constraint -all > "$::REPORTS_DIR/constraint_summary.rpt"
    handle_info "Constraints loaded successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_parasitics
# Read parasitic extraction data (SPEF) for accurate timing
# ---------------------------------------------------------------------------
flow_proc read_parasitics {
    handle_info "Reading parasitic data for STA..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set spef_dir "$run_dir/work/STA/inputs/spef"

    if {[info exists ::sta(SPEF_FILES)]} {
        set spef_files $::sta(SPEF_FILES)
    } else {
        set spef_files [glob -nocomplain "$spef_dir/*.spef" "$spef_dir/*.spef.gz"]
    }

    if {[llength $spef_files] == 0} {
        handle_warning "No SPEF files found - using wireload models"
    } else {
        foreach spef $spef_files {
            handle_info "Reading SPEF: $spef"
            read_parasitics -format spef $spef
        }
        handle_info "Loaded [llength $spef_files] SPEF file(s)"
    }

    # Report annotation coverage
    report_annotated_parasitics > "$::REPORTS_DIR/parasitic_annotation.rpt"

    # Report net with no parasitics
    report_annotated_parasitics -check > "$::REPORTS_DIR/unannotated_nets.rpt"

    handle_info "Parasitic read completed"
}

# ---------------------------------------------------------------------------
# flow_proc: validate
# Validate all STA inputs are loaded and consistent
# ---------------------------------------------------------------------------
flow_proc validate {
    handle_info "Validating STA inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Check design
    set current [current_design]
    if {$current eq ""} {
        handle_error "No design linked"
        incr errors
    }

    # Check clocks
    set clocks [all_clocks]
    if {[sizeof_collection $clocks] == 0} {
        handle_error "No clocks defined - STA requires clocks"
        incr errors
    } else {
        handle_info "Found [sizeof_collection $clocks] clock(s)"
    }

    # Check for unconstrained paths
    set unconstrained [get_timing_paths -slack_lesser_than 1e30 -max_paths 1 -unconstrained]
    if {[sizeof_collection $unconstrained] > 0} {
        handle_warning "Unconstrained timing paths detected"
    }

    # Write validation report
    set fp [open "$::REPORTS_DIR/input_validation.rpt" w]
    puts $fp "STA Input Validation Report - [clock format [clock seconds]]"
    puts $fp "============================================================"
    puts $fp "Design:         $current"
    puts $fp "Clocks:         [sizeof_collection $clocks]"
    puts $fp "Errors:         $errors"
    close $fp

    if {$errors > 0} {
        handle_error "STA input validation failed"
        return -code error "Validation failed"
    }
    handle_info "STA input validation passed"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all input flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc inputs_flow {
    handle_info "Executing STA inputs flow..."
    flow_exec setup_dirs
    flow_exec read_design
    flow_exec read_constraints
    flow_exec read_parasitics
    flow_exec validate
    handle_info "STA inputs completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " STA inputs procedures loaded" }
exit
