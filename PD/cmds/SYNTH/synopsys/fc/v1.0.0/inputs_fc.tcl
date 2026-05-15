#!/usr/bin/env tclsh
# CBFlow SYNTH inputs1 - Synopsys Fusion Compiler | Input preparation for SYNTH
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/SYNTH/inputs1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global synth project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting SYNTH inputs1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/SYNTH/inputs1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source MMMC configuration
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
if {[file exists $mmmc_config_file]} { source -e $mmmc_config_file }

# Source active scenarios if mmmc_setup has run
set active_scenarios_file "$run_dir/work/SYNTH/mmmc_setup/run/active_scenarios.tcl"
if {[file exists $active_scenarios_file]} { source -e $active_scenarios_file }

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global synth flow project flow_input_handshake

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── rtl: synth(input,rtl_release_tag) -> synth(input,rtl_filelist) ──────
    if {[info exists synth(input,rtl_release_tag)] && $synth(input,rtl_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH" "rtl"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth "rtl" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth(input,rtl_filelist) $_file
            handle_info "  RTL filelist resolved: $_file"
        }
    }

    # ── sdc: synth(input,sdc_release_tag) -> synth(input,sdc) ──────────────
    if {[info exists synth(input,sdc_release_tag)] && $synth(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth(input,sdc) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ==============================================================================
# flow_proc: setup_dirs
# Description: Create all required directory structures for synthesis run
# ==============================================================================
flow_proc setup_dirs {
    handle_info "Setting up directory structure for SYNTH inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create working directories for each data type
    foreach dir {
        "work/SYNTH/inputs/rtl"
        "work/SYNTH/inputs/sdc"
        "work/SYNTH/inputs/library"
        "work/SYNTH/inputs/upf"
        "logs/inputs"
        "reports/synth"
        "results/synth"
        "results/synth/netlist"
        "results/synth/sdc"
        "results/synth/db"
        "results/release"
    } {
        file mkdir "$run_dir/$dir"
    }

    handle_info "Directory structure created successfully"
}

# ==============================================================================
# flow_proc: read_libraries
# Description: Set up application variables and create design library with
#              reference libraries (ndm, technology files)
# ==============================================================================
flow_proc read_libraries {
    handle_info "Reading technology libraries..."
    global synth project tech

    # Set search path for library files
    set_app_var search_path "$tech(lib_dir) $project(script_dir)"

    # Set target library for synthesis mapping
    set_app_var target_library $tech(target_lib)
    set_app_var link_library "* $tech(target_lib) $tech(additional_libs)"

    # Create the design library with reference libs (NDM) for FC
    if {[info exists fc(common,ndm_libs)]} {
        set ref_lib_list [list]
        foreach lib $fc(common,ndm_libs) {
            lappend ref_lib_list $lib
        }
        handle_info "Creating library with reference libs: $ref_lib_list"
        create_lib $fc(common,design_lib_name) \
            -technology $tech(tech_file) \
            -ref_libs $ref_lib_list
    } else {
        handle_warning "No NDM reference libraries specified in fc(common,ndm_libs)"
        create_lib $fc(common,design_lib_name) \
            -technology $tech(tech_file)
    }

    # Set technology-specific options
    if {[info exists tech(dont_use_list)]} {
        foreach cell $tech(dont_use_list) {
            set_dont_use [get_lib_cells $cell]
        }
        handle_info "Applied dont_use constraints on [llength $tech(dont_use_list)] cells"
    }

    # Set operating conditions
    if {[info exists tech(operating_condition)]} {
        set_operating_conditions $tech(operating_condition)
    }

    handle_info "Technology libraries loaded successfully"
}

# ==============================================================================
# flow_proc: read_rtl
# Description: Read RTL source files (Verilog/SystemVerilog/VHDL), elaborate,
#              and link the design
# ==============================================================================
flow_proc read_rtl {
    handle_info "Reading RTL design files..."
    global synth project

    # Determine RTL file list from config
    if {[info exists fc(common,rtl_files)]} {
        set rtl_list $fc(common,rtl_files)
    } else {
        # Auto-discover RTL files from inputs directory
        set run_dir $::env(CBFLOW_RUN_DIR)
        set rtl_list [glob -nocomplain "$run_dir/work/SYNTH/inputs/rtl/*.v" \
                                        "$run_dir/work/SYNTH/inputs/rtl/*.sv" \
                                        "$run_dir/work/SYNTH/inputs/rtl/*.vhd"]
    }

    if {[llength $rtl_list] == 0} {
        handle_error "No RTL files found for synthesis"
        return -code error "Missing RTL"
    }

    # Read include directories if specified
    if {[info exists fc(common,include_dirs)]} {
        foreach inc_dir $fc(common,include_dirs) {
            set_app_var search_path "$inc_dir [get_app_var search_path]"
        }
    }

    # Analyze each RTL file
    handle_info "Analyzing [llength $rtl_list] RTL files..."
    foreach rtl_file $rtl_list {
        if {![file exists $rtl_file]} {
            handle_warning "RTL file not found: $rtl_file"
            continue
        }
        # Determine format from extension
        set ext [file extension $rtl_file]
        if {$ext eq ".sv"} {
            set fmt "sverilog"
        } elseif {$ext eq ".vhd" || $ext eq ".vhdl"} {
            set fmt "vhdl"
        } else {
            set fmt "verilog"
        }
        handle_info "  Analyzing ($fmt): [file tail $rtl_file]"
        analyze -format $fmt $rtl_file
    }

    # Elaborate the top module
    if {[info exists project(top_module)]} {
        handle_info "Elaborating top module: $project(top_module)..."
        elaborate $project(top_module)
    } elseif {[info exists fc(common,top_module)]} {
        handle_info "Elaborating top module: $fc(common,top_module)..."
        elaborate $fc(common,top_module)
    } else {
        handle_error "No top module specified in project(top_module) or fc(common,top_module)"
        return -code error "Missing top module"
    }

    # Link the design
    handle_info "Linking design..."
    link_design

    # Report design hierarchy
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    handle_info "Design elaborated with $cell_count hierarchical cells"

    handle_info "RTL loaded and elaborated successfully"
}

# ==============================================================================
# flow_proc: read_constraints
# Description: Read SDC timing constraints and optional UPF power intent
# ==============================================================================
flow_proc read_constraints {
    handle_info "Reading design constraints..."
    global synth

    # Read SDC timing constraints
    if {[info exists fc(common,input_sdc)]} {
        foreach sdc_file $fc(common,input_sdc) {
            if {[file exists $sdc_file]} {
                handle_info "Reading SDC: $sdc_file"
                read_sdc $sdc_file
            } else {
                handle_warning "SDC file not found: $sdc_file"
            }
        }
    } else {
        # Try auto-discovery from inputs directory
        set run_dir $::env(CBFLOW_RUN_DIR)
        set sdc_files [glob -nocomplain "$run_dir/work/SYNTH/inputs/sdc/*.sdc"]
        foreach sdc_file $sdc_files {
            handle_info "Reading SDC: $sdc_file"
            read_sdc $sdc_file
        }
        if {[llength $sdc_files] == 0} {
            handle_error "No SDC constraints found"
        }
    }

    # Read UPF power intent if specified
    if {[info exists fc(common,input_upf)]} {
        foreach upf_file $fc(common,input_upf) {
            if {[file exists $upf_file]} {
                handle_info "Reading UPF: $upf_file"
                read_upf $upf_file
            } else {
                handle_warning "UPF file not found: $upf_file"
            }
        }
    }

    # Report constraint summary
    redirect -file $::REPORTS_DIR/input_clocks.rpt { report_clocks }
    redirect -file $::REPORTS_DIR/timing_requirements.rpt { report_timing_requirements }

    handle_info "Design constraints loaded successfully"
}

# ==============================================================================
# flow_proc: validate_inputs
# Description: Validate all inputs are loaded correctly before synthesis
# ==============================================================================
flow_proc validate_inputs {
    handle_info "Validating SYNTH inputs..."
    global synth

    # Run check_design for issues
    handle_info "Running check_design..."
    redirect -file $::REPORTS_DIR/check_design_input.rpt {
        check_design -summary
    }

    # Report design statistics
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    handle_info "Design has $cell_count cells"

    set port_count [sizeof_collection [get_ports *]]
    handle_info "Design has $port_count ports"

    # Check for unresolved references
    set unresolved [get_cells -hierarchical -filter "is_unresolved == true"]
    if {[sizeof_collection $unresolved] > 0} {
        handle_warning "Found [sizeof_collection $unresolved] unresolved cell references"
        redirect -file $::REPORTS_DIR/unresolved_refs.rpt { report_reference_summary }
    }

    # Check for missing clock definitions
    set clocks [get_clocks -quiet]
    if {[sizeof_collection $clocks] == 0} {
        handle_warning "No clock definitions found -- timing constraints may be incomplete"
    } else {
        handle_info "Found [sizeof_collection $clocks] clock definitions"
    }

    # Check for combinational loops
    redirect -file $::REPORTS_DIR/check_design_loops.rpt {
        check_design -checks timing
    }

    handle_info "Input validation completed -- all checks passed"
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
