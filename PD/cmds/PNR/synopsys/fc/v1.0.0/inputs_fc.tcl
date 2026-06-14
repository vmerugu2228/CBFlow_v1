#!/usr/bin/env tclsh
# CBFlow PNR inputs1 - Synopsys Fusion Compiler | Input preparation for PNR

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
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
#   pnr(input,netlist_release_tag) = "v1.0.2"  -> auto-resolves from release
#   pnr(input,netlist)             = "/path"    -> direct path
# Release tag always takes priority if set.
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

# ==============================================================================
# flow_proc: create_design_lib
# Description: Create design library with technology and reference libraries
# ==============================================================================
flow_proc create_design_lib {
    handle_info "Creating design library..."
    global pnr tech

    # Remove stale library if it exists
    if {[file exists $pnr(common,design_lib_name)]} {
        file delete -force $pnr(common,design_lib_name)
    }

    # Build create_lib command with technology and reference libraries
    set create_lib_cmd "create_lib $pnr(common,design_lib_name)"
    if {[info exists tech(tech_file)] && [file exists [which $tech(tech_file)]]} {
        lappend create_lib_cmd -tech $tech(tech_file)
    } elseif {[info exists tech(tech_lib)] && $tech(tech_lib) ne ""} {
        lappend create_lib_cmd -use_technology_lib $tech(tech_lib)
    }
    if {[info exists pnr(common,design_lib_scale_factor)] && $pnr(common,design_lib_scale_factor) ne ""} {
        lappend create_lib_cmd -scale_factor $pnr(common,design_lib_scale_factor)
    }

    # Assemble reference library list
    set ref_libs [list]
    if {[info exists pnr(common,ndm_libs)]} {
        foreach lib $pnr(common,ndm_libs) { lappend ref_libs $lib }
    }
    if {[info exists pnr(common,sub_block_libs)]} {
        foreach lib $pnr(common,sub_block_libs) { lappend ref_libs $lib }
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
    if {[info exists pnr(common,input_netlist)] && $pnr(common,input_netlist) ne ""} {
        handle_info "Reading Verilog netlist: $pnr(common,input_netlist)"
        read_verilog -top $pnr(common,design_name) $pnr(common,input_netlist)
        current_block $pnr(common,design_name)
    } else {
        handle_error "No input netlist specified in pnr(common,input_netlist)"
        return -code error "Missing netlist"
    }

    # Set early data check policy if applicable
    if {[info exists pnr(common,early_data_check_policy)] && $pnr(common,early_data_check_policy) ne "none"} {
        set_early_data_check_policy -policy $pnr(common,early_data_check_policy) -if_not_exist
    }

    # Link the block
    handle_info "Linking block..."
    link_block
    save_lib

    # Read floorplan DEF if provided
    if {[info exists pnr(common,input_def)] && $pnr(common,input_def) ne ""} {
        if {[file exists $pnr(common,input_def)]} {
            handle_info "Reading floorplan DEF: $pnr(common,input_def)"
            read_def $pnr(common,input_def)
        } else {
            handle_warning "DEF file not found: $pnr(common,input_def)"
        }
    }

    # Source floorplan Tcl if provided
    if {[info exists pnr(common,fp_tcl)] && [file exists $pnr(common,fp_tcl)]} {
        handle_info "Sourcing floorplan Tcl: $pnr(common,fp_tcl)"
        source $pnr(common,fp_tcl)
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
    if {[info exists pnr(common,input_sdc)] && $pnr(common,input_sdc) ne ""} {
        foreach sdc_file $pnr(common,input_sdc) {
            if {[file exists $sdc_file]} {
                handle_info "Reading SDC: $sdc_file"
                read_sdc $sdc_file
            } else {
                handle_warning "SDC file not found: $sdc_file"
            }
        }
    } else {
        handle_error "No SDC constraints specified in pnr(common,input_sdc)"
    }

    # Read UPF power intent
    if {[info exists pnr(common,input_upf)] && $pnr(common,input_upf) ne ""} {
        foreach upf_file $pnr(common,input_upf) {
            if {[file exists $upf_file]} {
                handle_info "Reading UPF: $upf_file"
                load_upf $upf_file
            } else {
                handle_warning "UPF file not found: $upf_file"
            }
        }
        # Read supplemental UPF if provided
        if {[info exists pnr(common,input_upf_supplemental)] && [file exists $pnr(common,input_upf_supplemental)]} {
            load_upf -supplemental $pnr(common,input_upf_supplemental)
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

    if {![info exists tech(tluplus_map)]} {
        handle_error "tech(tluplus_map) not defined in tech_config.tcl"
        return
    }
    if {[info exists tech(rcx,rc_max,tluplus)]} {
        handle_info "Setting TLU+ parasitic models (per RC corner)..."
        read_parasitic_tech \
            -tlup $tech(rcx,rc_max,tluplus) \
            -layermap $tech(tluplus_map)
        if {[info exists tech(rcx,rc_min,tluplus)]} {
            set_parasitic_parameters \
                -early_spec $tech(rcx,rc_min,tluplus) \
                -late_spec $tech(rcx,rc_max,tluplus)
        }
    } elseif {[info exists tech(rcx,rc_max,nxtgrd)]} {
        handle_info "Setting NXTGRD parasitic models (per RC corner)..."
        read_parasitic_tech \
            -tlup $tech(rcx,rc_max,nxtgrd) \
            -layermap $tech(tluplus_map)
        if {[info exists tech(rcx,rc_min,nxtgrd)]} {
            set_parasitic_parameters \
                -early_spec $tech(rcx,rc_min,nxtgrd) \
                -late_spec $tech(rcx,rc_max,nxtgrd)
        }
    } else {
        handle_error "No parasitic tech files defined. Set tech(rcx,rc_max,tluplus) or tech(rcx,rc_max,nxtgrd) in tech_config.tcl"
        return
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
    if {[info exists pnr(compile,qor_metric)] && $pnr(compile,qor_metric) ne ""} {
        lappend set_qor_strategy_cmd -metric $pnr(compile,qor_metric)
    }
    if {[info exists pnr(compile,qor_mode)] && $pnr(compile,qor_mode) ne ""} {
        lappend set_qor_strategy_cmd -mode $pnr(compile,qor_mode)
    }

    handle_info "Running: $set_qor_strategy_cmd"
    eval $set_qor_strategy_cmd

    # Set technology node if specified
    if {[info exists pnr(common,technology_node)] && $pnr(common,technology_node) ne ""} {
        set_technology -node $pnr(common,technology_node)
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

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling) ne "" && [string is true -strict $pnr(output,block_labeling)]} {
        save_block -as $pnr(common,design_name)/inputs
        handle_info "Block saved as $pnr(common,design_name)/inputs"
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
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
