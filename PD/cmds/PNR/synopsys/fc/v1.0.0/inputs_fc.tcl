#!/usr/bin/env tclsh
# CBFlow PNR inputs1 - Synopsys Fusion Compiler | Input preparation for PNR
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/PNR/inputs1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR inputs1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/inputs1"
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

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# User sets EITHER:
#   pnr(input,netlist_release_tag) = "v1.0.2"  -> auto-resolves from release
#   pnr(input,netlist)             = "/path"    -> direct path
# Release tag always takes priority if set.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global pnr flow project flow_input_handshake

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

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

# ==============================================================================
# flow_proc: create_design_lib
# Description: Create design library with technology and reference libraries
# ==============================================================================
flow_proc create_design_lib {
    handle_info "Creating design library..."
    global pnr tech

    # Remove stale library if it exists
    if {[file exists $fc(common,design_lib_name)]} {
        file delete -force $fc(common,design_lib_name)
    }

    # Build create_lib command with technology and reference libraries
    set create_lib_cmd "create_lib $fc(common,design_lib_name)"
    if {[info exists tech(tech_file)] && [file exists [which $tech(tech_file)]]} {
        lappend create_lib_cmd -tech $tech(tech_file)
    } elseif {[info exists tech(tech_lib)] && $tech(tech_lib) ne ""} {
        lappend create_lib_cmd -use_technology_lib $tech(tech_lib)
    }
    if {[info exists fc(common,design_lib_scale_factor)] && $fc(common,design_lib_scale_factor) ne ""} {
        lappend create_lib_cmd -scale_factor $fc(common,design_lib_scale_factor)
    }

    # Assemble reference library list
    set ref_libs [list]
    if {[info exists fc(common,ndm_libs)]} {
        foreach lib $fc(common,ndm_libs) { lappend ref_libs $lib }
    }
    if {[info exists fc(common,sub_block_libs)]} {
        foreach lib $fc(common,sub_block_libs) { lappend ref_libs $lib }
    }
    if {[llength $ref_libs] > 0} {
        lappend create_lib_cmd -ref_libs $ref_libs
    }

    handle_info "Running: $create_lib_cmd"
    eval $create_lib_cmd

    handle_info "Design library created successfully"
}

# ==============================================================================
# flow_proc: read_design_inputs
# Description: Read synthesized netlist or DEF, link and elaborate the design
# ==============================================================================
flow_proc read_design_inputs {
    handle_info "Reading design inputs..."
    global pnr

    # Read the gate-level netlist
    if {[info exists fc(common,input_netlist)] && $fc(common,input_netlist) ne ""} {
        handle_info "Reading Verilog netlist: $fc(common,input_netlist)"
        read_verilog -top $fc(common,design_name) $fc(common,input_netlist)
        current_block $fc(common,design_name)
    } else {
        handle_error "No input netlist specified in fc(common,input_netlist)"
        return -code error "Missing netlist"
    }

    # Set early data check policy if applicable
    if {[info exists fc(common,early_data_check_policy)] && $fc(common,early_data_check_policy) ne "none"} {
        set_early_data_check_policy -policy $fc(common,early_data_check_policy) -if_not_exist
    }

    # Link the block
    handle_info "Linking block..."
    link_block
    save_lib

    # Read floorplan DEF if provided
    if {[info exists fc(common,input_def)] && $fc(common,input_def) ne ""} {
        if {[file exists $fc(common,input_def)]} {
            handle_info "Reading floorplan DEF: $fc(common,input_def)"
            read_def $fc(common,input_def)
        } else {
            handle_warning "DEF file not found: $fc(common,input_def)"
        }
    }

    # Source floorplan Tcl if provided
    if {[info exists fc(common,fp_tcl)] && [file exists $fc(common,fp_tcl)]} {
        handle_info "Sourcing floorplan Tcl: $fc(common,fp_tcl)"
        source -e $fc(common,fp_tcl)
    }

    handle_info "Design inputs loaded successfully"
}

# ==============================================================================
# flow_proc: read_constraints
# Description: Read SDC timing constraints and UPF power intent
# ==============================================================================
flow_proc read_constraints {
    handle_info "Reading design constraints..."
    global pnr

    # Read SDC timing constraints
    if {[info exists fc(common,input_sdc)] && $fc(common,input_sdc) ne ""} {
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
    if {[info exists fc(common,input_upf)] && $fc(common,input_upf) ne ""} {
        foreach upf_file $fc(common,input_upf) {
            if {[file exists $upf_file]} {
                handle_info "Reading UPF: $upf_file"
                load_upf $upf_file
            } else {
                handle_warning "UPF file not found: $upf_file"
            }
        }
        # Read supplemental UPF if provided
        if {[info exists fc(common,input_upf_supplemental)] && [file exists $fc(common,input_upf_supplemental)]} {
            load_upf -supplemental $fc(common,input_upf_supplemental)
        }
        handle_info "Running commit_upf"
        commit_upf
    }

    handle_info "Design constraints loaded successfully"
}

# ==============================================================================
# flow_proc: read_parasitics
# Description: Read parasitic technology files (TLU+/NXTGRD) for RC estimation
# ==============================================================================
flow_proc read_parasitics {
    handle_info "Reading parasitic technology files..."
    global tech pnr

    if {[info exists tech(tluplus_max)] && [info exists tech(tluplus_map)]} {
        handle_info "Setting TLU+ parasitic models..."
        read_parasitic_tech \
            -tlup $tech(tluplus_max) \
            -layermap $tech(tluplus_map)
        if {[info exists tech(tluplus_min)]} {
            set_parasitic_parameters \
                -early_spec $tech(tluplus_min) \
                -late_spec $tech(tluplus_max)
        }
    } elseif {[info exists tech(nxtgrd_max)] && [info exists tech(tluplus_map)]} {
        handle_info "Setting NXTGRD parasitic models..."
        read_parasitic_tech \
            -tlup $tech(nxtgrd_max) \
            -layermap $tech(tluplus_map)
        if {[info exists tech(nxtgrd_min)]} {
            set_parasitic_parameters \
                -early_spec $tech(nxtgrd_min) \
                -late_spec $tech(nxtgrd_max)
        }
    } else {
        handle_warning "No parasitic tech files specified -- RC estimation may be inaccurate"
    }

    handle_info "Parasitic technology loaded successfully"
}

# ==============================================================================
# flow_proc: set_qor_strategy_init
# Description: Set QoR strategy for PNR init stage
# ==============================================================================
flow_proc set_qor_strategy_init {
    handle_info "Setting QoR strategy for init design..."
    global pnr

    set set_qor_strategy_cmd "set_qor_strategy -stage pnr"
    if {[info exists fc(compile,qor_metric)] && $fc(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $fc(compile,qor_metric)
    }
    if {[info exists fc(compile,qor_mode)] && $fc(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $fc(compile,qor_mode)
    }

    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set technology node if specified
    if {[info exists fc(common,technology_node)] && $fc(common,technology_node) ne ""} {
        set_technology -node $fc(common,technology_node)
        save_lib -all
    }

    handle_info "QoR strategy set successfully"
}

# ==============================================================================
# flow_proc: connect_power_ground
# Description: Connect PG nets automatically
# ==============================================================================
flow_proc connect_power_ground {
    handle_info "Connecting power/ground nets..."

    connect_pg_net
    # Remove duplicate shapes
    check_duplicates -remove

    handle_info "Power/ground nets connected"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after input loading
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global pnr

    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as $fc(common,design_name)/inputs
        handle_info "Block saved as $fc(common,design_name)/inputs"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Generate input validation and design quality reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating input reports..."
    global pnr

    file mkdir "$::REPORTS_DIR"

    # FC-RM: QoR
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }

    # FC-RM: Timing
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths 20 -delay_type max -nosplit
    }

    # FC-RM: Design summary
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }

    # FC-RM: Check design
    redirect -file $::REPORTS_DIR/check_design.rpt {
        check_design -checks all
    }

    # FC-RM: Reference library report
    redirect -file $::REPORTS_DIR/report_ref_libs.rpt { report_ref_libs }

    # FC-RM: Clock report
    redirect -file $::REPORTS_DIR/report_clocks.rpt { report_clocks }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Input reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/PNR/inputs1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.inputs.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
