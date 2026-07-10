#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR inputs - Synopsys Fusion Compiler
# Input preparation for unified synthesis-to-signoff

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

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
            set synth_pnr(input,upf_file) $_file
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
}
flow_proc create_design_lib {
    handle_info "Creating design library..."
    global synth_pnr tech

    # Remove stale library if it exists
    if {[info exists synth_pnr(common,design_lib_name)] && $synth_pnr(common,design_lib_name) ne "" && [file exists $synth_pnr(common,design_lib_name)]} {
        file delete -force $synth_pnr(common,design_lib_name)
    }

    # Build create_lib command with technology and reference libraries
    set create_lib_cmd "create_lib $synth_pnr(common,design_lib_name)"
    if {[info exists tech($project(metal_stack),$tech(track),tech_file)] && $tech($project(metal_stack),$tech(track),tech_file) ne "" && [file exists [which $tech($project(metal_stack),$tech(track),tech_file)]]} {
        lappend create_lib_cmd -tech $tech($project(metal_stack),$tech(track),tech_file)
    } elseif {[info exists tech(tech_lib)] && $tech(tech_lib) ne ""} {
        lappend create_lib_cmd -use_technology_lib $tech(tech_lib)
    }
    if {[info exists synth_pnr(init_design,design_lib_scale_factor)] && $synth_pnr(init_design,design_lib_scale_factor) ne ""} {
        lappend create_lib_cmd -scale_factor $synth_pnr(init_design,design_lib_scale_factor)
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
}
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
    handle_info "Elaborating design: $synth_pnr(common,design_name)"
    elaborate $synth_pnr(common,design_name)
    current_block $synth_pnr(common,design_name)

    # Link the block
    handle_info "Linking block..."
    link_block
    save_lib

    handle_info "RTL inputs loaded and elaborated successfully"
# ==============================================================================
# flow_proc: read_floorplan
# Description: Read floorplan DEF from floorplan stage
# ==============================================================================
}
flow_proc read_floorplan {
    handle_info "Reading floorplan data..."
    global synth_pnr

    # Read floorplan DEF if provided
    if {[info exists synth_pnr(input,def_file)] && $synth_pnr(input,def_file) ne ""} {
        if {[file exists $synth_pnr(input,def_file)]} {
            handle_info "Reading floorplan DEF: $synth_pnr(input,def_file)"
            read_def $synth_pnr(input,def_file)
        } else {
            handle_warning "DEF file not found: $synth_pnr(input,def_file)"
        }
    }

    # Source floorplan Tcl if provided
    if {[info exists synth_pnr(input,fp_tcl)] && [file exists $synth_pnr(input,fp_tcl)]} {
        handle_info "Sourcing floorplan Tcl: $synth_pnr(input,fp_tcl)"
        source $synth_pnr(input,fp_tcl)
    }

    handle_info "Floorplan data loaded successfully"
# ==============================================================================
# flow_proc: read_constraints
# Description: Read SDC timing constraints and UPF power intent
# ==============================================================================
}
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
    if {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
        foreach upf_file $synth_pnr(input,upf_file) {
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
}
flow_proc read_parasitics {
    handle_info "Reading parasitic technology files..."
    global tech synth_pnr

    # tech($project(metal_stack),tluplus_map) must be defined in tech_config — crash if missing
    if {[info exists tech(rcx,$project(metal_stack),rc_max,tluplus)] && $tech(rcx,$project(metal_stack),rc_max,tluplus) ne ""} {
        handle_info "Setting TLU+ parasitic models (per RC corner)..."
        read_parasitic_tech \
            -tlup $tech(rcx,$project(metal_stack),rc_max,tluplus) \
            -layermap $tech($project(metal_stack),tluplus_map)
        if {[info exists tech(rcx,$project(metal_stack),rc_min,tluplus)] && $tech(rcx,$project(metal_stack),rc_min,tluplus) ne ""} {
            set_parasitic_parameters \
                -early_spec $tech(rcx,$project(metal_stack),rc_min,tluplus) \
                -late_spec $tech(rcx,$project(metal_stack),rc_max,tluplus)
        }
    } elseif {[info exists tech(rcx,$project(metal_stack),rc_max,nxtgrd)] && $tech(rcx,$project(metal_stack),rc_max,nxtgrd) ne ""} {
        handle_info "Setting NXTGRD parasitic models (per RC corner)..."
        read_parasitic_tech \
            -tlup $tech(rcx,$project(metal_stack),rc_max,nxtgrd) \
            -layermap $tech($project(metal_stack),tluplus_map)
        if {[info exists tech(rcx,$project(metal_stack),rc_min,nxtgrd)] && $tech(rcx,$project(metal_stack),rc_min,nxtgrd) ne ""} {
            set_parasitic_parameters \
                -early_spec $tech(rcx,$project(metal_stack),rc_min,nxtgrd) \
                -late_spec $tech(rcx,$project(metal_stack),rc_max,nxtgrd)
        }
    } else {
        handle_error "No parasitic tech files defined. Set tech(rcx,$project(metal_stack),rc_max,tluplus) or tech(rcx,$project(metal_stack),rc_max,nxtgrd) in tech_config.tcl"
        return
    }

    handle_info "Parasitic technology loaded successfully"
# ==============================================================================
# flow_proc: set_qor_strategy_init
# Description: Set QoR strategy for initial design setup
# ==============================================================================
}
flow_proc set_qor_strategy_init {
    handle_info "Setting QoR strategy for init design..."
    global synth_pnr

    set set_qor_strategy_cmd "set_qor_strategy -stage pnr"
    if {[info exists synth_pnr(common,compile,qor_metric)] && $synth_pnr(common,compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $synth_pnr(common,compile,qor_metric)
    }
    if {[info exists synth_pnr(common,compile,qor_mode)] && $synth_pnr(common,compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $synth_pnr(common,compile,qor_mode)
    }

    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set technology node if specified
    if {[info exists synth_pnr(common,tech_node)] && $synth_pnr(common,tech_node) ne ""} {
        set_technology -node $synth_pnr(common,tech_node)
        save_lib -all
    }

    handle_info "QoR strategy set successfully"
# ==============================================================================
# flow_proc: connect_power_ground
# Description: Connect PG nets automatically
# ==============================================================================
}
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
}
flow_proc save_design_block {
    handle_info "Saving design block..."
    global synth_pnr

    if {[info exists synth_pnr(common,output,block_labeling)] && $synth_pnr(common,output,block_labeling) ne "" && $synth_pnr(common,output,block_labeling)} {
        save_block -as $synth_pnr(common,design_name)/inputs
        handle_info "Block saved as $synth_pnr(common,design_name)/inputs"
    } else {
        save_block
        handle_info "Block saved"
    }
# ==============================================================================
# flow_proc: generate_reports
# Description: Generate input validation and design quality reports
# ==============================================================================
}
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
# ==============================================================================
}
flow_exec_all

# Exit tool after stage completion
exit
