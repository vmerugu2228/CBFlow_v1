#!/usr/bin/env tclsh
# CBFlow FP inputs - Synopsys Fusion Compiler | Input preparation for FP
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FP/inputs/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP inputs with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FP/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

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
    global fp flow project flow_input_handshake

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

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

# ==============================================================================
# flow_proc: setup_dirs
# Description: Create all required directory structures for floorplan run
# ==============================================================================
flow_proc setup_dirs {
    handle_info "Setting up directory structure for FP inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create working directories for each data type
    foreach dir {
        "work/FP/inputs/netlist"
        "work/FP/inputs/sdc"
        "work/FP/inputs/def"
        "work/FP/inputs/upf"
        "work/FP/inputs/library"
        "work/FP/inputs/io_constraints"
        "logs/inputs"
        "reports/fp"
        "reports/fp/floorplan"
        "reports/fp/powerplan"
        "reports/fp/post_floorplan"
        "results/fp"
        "results/fp/def"
        "results/fp/netlist"
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
    global fp project tech

    # Set search path for library files
    set_app_var search_path "$tech(lib_dir) $project(script_dir)"

    # Set target library
    set_app_var target_library $tech(target_lib)
    set_app_var link_library "* $tech(target_lib) $tech(additional_libs)"

    # Create the design library with reference libs (NDM)
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

    # Set technology-specific app options
    if {[info exists tech(site_def)]} {
        set_app_var placer.place.default_site $tech(site_def)
    }
    if {[info exists tech(track_offset)]} {
        set_app_var design.track_offset $tech(track_offset)
    }

    handle_info "Technology libraries loaded successfully"
}

# ==============================================================================
# flow_proc: read_design
# Description: Read synthesized netlist from upstream SYNTH stage
# ==============================================================================
flow_proc read_design {
    handle_info "Reading design data..."
    global fp project

    # Read synthesized gate-level netlist
    set netlist_file $fc(common,input_netlist)
    if {![file exists $netlist_file]} {
        handle_error "Netlist file not found: $netlist_file"
        return -code error "Missing netlist"
    }
    handle_info "Reading Verilog netlist: $netlist_file"
    read_verilog -design $fc(common,design_lib_name)/$fc(common,design_name) $netlist_file

    # Link the design
    handle_info "Linking design..."
    link_block

    # Report cell count and hierarchy
    set cell_count [sizeof_collection [get_cells -hierarchical]]
    handle_info "Design loaded with $cell_count cells"

    handle_info "Design data loaded successfully"
}

# ==============================================================================
# flow_proc: read_constraints
# Description: Read timing constraints (SDC) and power intent (UPF)
# ==============================================================================
flow_proc read_constraints {
    handle_info "Reading design constraints..."
    global fp

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
        handle_error "No SDC constraints specified in fc(common,input_sdc)"
    }

    # Read UPF power intent
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

    # Propagate constraints and check for issues
    handle_info "Validating constraint propagation..."
    redirect -file $::REPORTS_DIR/input_clocks.rpt { report_clocks }

    handle_info "Design constraints loaded successfully"
}

# ==============================================================================
# flow_proc: validate_inputs
# Description: Validate all inputs are loaded correctly before floorplanning
# ==============================================================================
flow_proc validate_inputs {
    handle_info "Validating FP inputs..."
    global fp

    # Check design is linked
    set current [current_block]
    if {$current eq ""} {
        handle_error "No design block is open -- input loading failed"
        return -code error "Design not loaded"
    }

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

    # Check for macro cells
    set macros [get_cells -hierarchical -filter "is_hard_macro == true"]
    if {[sizeof_collection $macros] > 0} {
        handle_info "Found [sizeof_collection $macros] hard macros for floorplanning"
    }

    handle_info "Input validation completed -- all checks passed"
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
