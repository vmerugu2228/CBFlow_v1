#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR inputs - Synopsys Fusion Compiler | Input preparation for unified synthesis-to-signoff
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
global synth_pnr project tech flow
# Source MMMC config
set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
# Source FC tool config
set _fc_config "[file dirname [info script]]/fc_config.tcl"

handle_info "Starting SYNTH_PNR inputs..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/SYNTH_PNR/inputs1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }

# Source release config for handshake map
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# ==============================================================================
# flow_proc: resolve_inputs
# Resolve input files from release tags or direct paths.
# User sets EITHER:
#   synth_pnr(input,rtl_release_tag) = "v1.0.2"  → auto-resolves from release
#   synth_pnr(input,rtl)             = "/path"    → direct path
# Release tag always takes priority if set.
# ==============================================================================
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global synth_pnr flow project flow_input_handshake

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── Resolve each input type using handshake map ──────────────────────────
    # RTL: synth_pnr(input,rtl_release_tag) → $release_path/.../rtl/${design_name}.f
    if {[info exists synth_pnr(input,rtl_release_tag)] && $synth_pnr(input,rtl_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH_PNR" "rtl"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth_pnr "rtl" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth_pnr(input,rtl_filelist) $_file
            handle_info "  RTL filelist resolved: $_file"
        }
    }

    # SDC: synth_pnr(input,sdc_release_tag) → $release_path/.../sdc/${design_name}.sdc
    if {[info exists synth_pnr(input,sdc_release_tag)] && $synth_pnr(input,sdc_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH_PNR" "sdc"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth_pnr "sdc" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth_pnr(input,sdc_file) $_file
            handle_info "  SDC resolved: $_file"
        }
    }

    # UPF: synth_pnr(input,upf_release_tag) → $release_path/.../upf/${design_name}.upf
    if {[info exists synth_pnr(input,upf_release_tag)] && $synth_pnr(input,upf_release_tag) ne ""} {
        set hs [get_input_handshake "SYNTH_PNR" "upf"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve synth_pnr "upf" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set synth_pnr(input,upf) $_file
            handle_info "  UPF resolved: $_file"
        }
    }

    # Validate release tag if provided
    foreach tag_var {input,rtl_release_tag input,sdc_release_tag input,upf_release_tag} {
        if {[info exists synth_pnr($tag_var)] && $synth_pnr($tag_var) ne ""} {
            ::CBFlow::InputResolve::validate_release_tag $synth_pnr($tag_var)
        }
    }

    handle_info "Input resolution completed"
# ==============================================================================
# flow_proc: create_design_lib
# Description: Create design library with technology and reference libraries
# ==============================================================================
flow_proc create_design_lib {
    handle_info "Creating design library..."
    global synth_pnr tech

    # Remove stale library if it exists
    if {[info exists fc(common,design_lib_name)] && [file exists $fc(common,design_lib_name)]} {
        file delete -force $fc(common,design_lib_name)
    }

    # Build create_lib command with technology and reference libraries
    set create_lib_cmd "create_lib $fc(common,design_lib_name)"
    if {[info exists tech(tech_file)] && [file exists [which $tech(tech_file)]]} {
        lappend create_lib_cmd -tech $tech(tech_file)
    } elseif {[info exists tech(tech_lib)] && $tech(tech_lib) ne ""} {
        lappend create_lib_cmd -use_technology_lib $tech(tech_lib)
    }
    if {[info exists fc(init_design,design_lib_scale_factor)] && $fc(init_design,design_lib_scale_factor) ne ""} {
        lappend create_lib_cmd -scale_factor $fc(init_design,design_lib_scale_factor)
    }

    # Assemble reference library list
    set ref_libs [list]
    if {[info exists synth_pnr(input,ndm_libs)]} {
        foreach lib $synth_pnr(input,ndm_libs) { lappend ref_libs $lib }
    }
    if {[info exists synth_pnr(input,sub_block_libs)]} {
        foreach lib $synth_pnr(input,sub_block_libs) { lappend ref_libs $lib }
    }
    if {[llength $ref_libs] > 0} {
        lappend create_lib_cmd -ref_libs $ref_libs
    }

    handle_info "Running: $create_lib_cmd"
    eval $create_lib_cmd

    handle_info "Design library created successfully"
# ==============================================================================
# flow_proc: read_rtl_inputs
# Description: Read RTL source files and elaborate the design
# ==============================================================================
flow_proc read_rtl_inputs {
    handle_info "Reading RTL design inputs..."
    global synth_pnr

    # Read RTL Verilog/SystemVerilog source files
    if {[info exists synth_pnr(input,rtl)] && $synth_pnr(input,rtl) ne ""} {
        foreach rtl_file $synth_pnr(input,rtl) {
            if {[file exists $rtl_file]} {
                handle_info "Reading RTL: $rtl_file"
                if {[string match "*.sv" $rtl_file] || [string match "*.svh" $rtl_file]} {
                    read_verilog -sverilog $rtl_file
                } else {
                    read_verilog $rtl_file
                }
            } else {
                handle_warning "RTL file not found: $rtl_file"
            }
        }
    } elseif {[info exists synth_pnr(input,rtl_filelist)] && [file exists $synth_pnr(input,rtl_filelist)]} {
        handle_info "Reading RTL filelist: $synth_pnr(input,rtl_filelist)"
        read_verilog -sverilog -f $synth_pnr(input,rtl_filelist)
    } else {
        handle_error "No RTL source specified in synth_pnr(input,rtl) or synth_pnr(input,rtl_filelist)"
        return -code error "Missing RTL source"
    }

    # Elaborate the top-level design
    handle_info "Elaborating design: $fc(common,design_name)"
    elaborate $fc(common,design_name)
    current_block $fc(common,design_name)

    # Link the block
    handle_info "Linking block..."
    link_block
    save_lib

    handle_info "RTL inputs loaded and elaborated successfully"
# ==============================================================================
# flow_proc: read_floorplan
# Description: Read floorplan DEF from floorplan stage
# ==============================================================================
flow_proc read_floorplan {
    handle_info "Reading floorplan data..."
    global synth_pnr

    # Read floorplan DEF if provided
    if {[info exists synth_pnr(input,def)] && $synth_pnr(input,def) ne ""} {
        if {[file exists $synth_pnr(input,def)]} {
            handle_info "Reading floorplan DEF: $synth_pnr(input,def)"
            read_def $synth_pnr(input,def)
        } else {
            handle_warning "DEF file not found: $synth_pnr(input,def)"
        }
    }

    # Source floorplan Tcl if provided
    if {[info exists synth_pnr(input,fp_tcl)] && [file exists $synth_pnr(input,fp_tcl)]} {
        handle_info "Sourcing floorplan Tcl: $synth_pnr(input,fp_tcl)"
        source -e $synth_pnr(input,fp_tcl)
    }

    handle_info "Floorplan data loaded successfully"
# ==============================================================================
# flow_proc: read_constraints
# Description: Read SDC timing constraints and UPF power intent
# ==============================================================================
flow_proc read_constraints {
    handle_info "Reading design constraints..."
    global synth_pnr

    # Read SDC timing constraints
    if {[info exists synth_pnr(input,sdc_file)] && $synth_pnr(input,sdc_file) ne ""} {
        foreach sdc_file $synth_pnr(input,sdc_file) {
            if {[file exists $sdc_file]} {
                handle_info "Reading SDC: $sdc_file"
                read_sdc $sdc_file
            } else {
                handle_warning "SDC file not found: $sdc_file"
            }
        }
    } else {
        handle_error "No SDC constraints specified in synth_pnr(input,sdc_file)"
    }

    # Read UPF power intent
    if {[info exists synth_pnr(input,upf)] && $synth_pnr(input,upf) ne ""} {
        foreach upf_file $synth_pnr(input,upf) {
            if {[file exists $upf_file]} {
                handle_info "Reading UPF: $upf_file"
                load_upf $upf_file
            } else {
                handle_warning "UPF file not found: $upf_file"
            }
        }
        # Read supplemental UPF if provided
        if {[info exists synth_pnr(input,upf_supplemental)] && [file exists $synth_pnr(input,upf_supplemental)]} {
            load_upf -supplemental $synth_pnr(input,upf_supplemental)
        }
        handle_info "Running commit_upf"
        commit_upf
    }

    handle_info "Design constraints loaded successfully"
# ==============================================================================
# flow_proc: read_parasitics
# Description: Read parasitic technology files (TLU+/NXTGRD) for RC estimation
# ==============================================================================
flow_proc read_parasitics {
    handle_info "Reading parasitic technology files..."
    global tech synth_pnr

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
# ==============================================================================
# flow_proc: set_qor_strategy_init
# Description: Set QoR strategy for initial design setup
# ==============================================================================
flow_proc set_qor_strategy_init {
    handle_info "Setting QoR strategy for init design..."
    global synth_pnr

    set set_qor_strategy_cmd "set_qor_strategy -stage pnr"
    if {[info exists fc(common,compile,qor_metric)] && $fc(common,compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $fc(common,compile,qor_metric)
    }
    if {[info exists fc(common,compile,qor_mode)] && $fc(common,compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $fc(common,compile,qor_mode)
    }

    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set technology node if specified
    if {[info exists fc(common,tech_node)] && $fc(common,tech_node) ne ""} {
        set_technology -node $fc(common,tech_node)
        save_lib -all
    }

    handle_info "QoR strategy set successfully"
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
# ==============================================================================
# flow_proc: save_design_block
# Description: Save the design block after input loading
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving design block..."
    global synth_pnr

    if {[info exists fc(common,output,block_labeling)] && $fc(common,output,block_labeling)} {
        save_block -as $fc(common,design_name)/inputs
        handle_info "Block saved as $fc(common,design_name)/inputs"
    } else {
        save_block
        handle_info "Block saved"
    }
# ==============================================================================
# flow_proc: generate_reports
# Description: Generate input validation and design quality reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating input reports..."
    global synth_pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/reports/synth_pnr"

    # QoR summary
    redirect -file "$run_dir/reports/synth_pnr/inputs_qor.rpt" { report_qor }

    # Timing
    redirect -file "$run_dir/reports/synth_pnr/inputs_timing.rpt" {
        report_timing -max_paths 20 -delay_type max -nosplit
    }

    # Design summary
    redirect -file "$run_dir/reports/synth_pnr/inputs_design.rpt" { report_design -summary }

    # Check design
    redirect -file "$run_dir/reports/synth_pnr/inputs_check_design.rpt" {
        check_design -checks all
    }

    # Reference library report
    redirect -file "$run_dir/reports/synth_pnr/inputs_ref_libs.rpt" { report_ref_libs }

    # Clock report
    redirect -file "$run_dir/reports/synth_pnr/inputs_clocks.rpt" { report_clocks }

    handle_info "Input reports generated in reports/synth_pnr/"
# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
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
flow_exec_all

# Exit tool after stage completion
exit
