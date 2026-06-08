#!/usr/bin/env tclsh
# SYNTH init_design - Cadence Genus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "init_design"
set NODE_NAME "init_design1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: setup_libraries
# Genus-RM: set_db / read_libs -- Liberty timing libraries, LEF physical
#           libraries, and technology setup from tech() array
# ==============================================================================
flow_proc setup_libraries {
    handle_info "Setting up libraries..."
    global synth tech project

    set _trk $project(track_variant)

    # ── Tech LEF (metal_stack × track from tech_config) ──
    set _ms $project(metal_stack)
    handle_info "Tech LEF: [file tail $tech(${_ms},${_trk},lef_tech)]"
    read_physical -lef $tech(${_ms},${_trk},lef_tech)

    # ── Cell LEFs (stdcell + memory + IO — from lib_config) ──
    handle_info "Cell LEFs ($_trk): [llength $tech(${_trk},lef)] files"
    foreach _lef $tech(${_trk},lef) {
        read_physical -lef $_lef
    }

    # ── Timing libs (nominal for synthesis — from lib_config) ──
    handle_info "Timing libs ($_trk): [llength $tech(${_trk},lib_nom)] files"
    read_libs $tech(${_trk},lib_nom)

    # ── QRC tech file (physical-aware synthesis — typical RC) ──
    if {[info exists tech(rcx,${_ms},rc_typ,qrc)] && $tech(rcx,${_ms},rc_typ,qrc) ne ""} {
        handle_info "QRC tech: [file tail $tech(rcx,${_ms},rc_typ,qrc)]"
        set_db qrc_tech_file $tech(rcx,${_ms},rc_typ,qrc)
    }

    handle_info "Library setup completed"
}

# ==============================================================================
# flow_proc: setup_genus_options
# Genus-RM: set_db options -- global Genus settings for synthesis quality
# ==============================================================================
flow_proc setup_genus_options {
    handle_info "Setting Genus options..."
    global synth tech project

    # -- Design name -----------------------------------------------------------
    set design_name ""
    if {[info exists synth(common,design_name)]} { set design_name $synth(common,design_name) }

    # -- Genus application options ---------------------------------------------
    # Effort level
    set effort [expr {[info exists synth(compile,effort)] ? $synth(compile,effort) : "medium"}]
    set_db syn_global_effort $effort
    handle_info "Synthesis effort: $effort"

    # Enable physical-aware synthesis if QRC is available
    set _ms $project(metal_stack)
    if {[info exists tech(rcx,${_ms},rc_typ,qrc)] && $tech(rcx,${_ms},rc_typ,qrc) ne ""} {
        set_db / .phys_syn_effort $effort
        handle_info "Physical-aware synthesis enabled"
    }

    # Leakage power optimization
    if {[info exists synth(compile,leakage_power_effort)] && $synth(compile,leakage_power_effort) ne ""} {
        set_db / .leakage_power_effort $synth(compile,leakage_power_effort)
        handle_info "Leakage power effort: $synth(compile,leakage_power_effort)"
    }

    # Dynamic power optimization
    if {[info exists synth(compile,dynamic_power_effort)] && $synth(compile,dynamic_power_effort) ne ""} {
        set_db / .dynamic_power_effort $synth(compile,dynamic_power_effort)
        handle_info "Dynamic power effort: $synth(compile,dynamic_power_effort)"
    }

    # Max routing layers (for physical-aware)
    if {[info exists synth(common,route_max_layer)] && $synth(common,route_max_layer) ne ""} {
        set_db design_top_routing_layer $synth(common,route_max_layer)
    }
    if {[info exists synth(common,route_min_layer)] && $synth(common,route_min_layer) ne ""} {
        set_db design_bottom_routing_layer $synth(common,route_min_layer)
    }

    # Genus user options file
    if {[info exists synth(common,genus_options_file)] && [file exists $synth(common,genus_options_file)]} {
        handle_info "Sourcing Genus options: $synth(common,genus_options_file)"
        source $synth(common,genus_options_file)
    }

    handle_info "Genus options set"
}

# ==============================================================================
# flow_proc: read_design
# Genus-RM: read_hdl / elaborate -- RTL file reading and design elaboration
# ==============================================================================
flow_proc read_design {
    handle_info "Reading RTL design..."
    global synth flow

    set design_name $flow(design_name)

    # ── Read RTL from filelist (mandatory) ──
    if {![info exists synth(input,rtl_filelist)] || $synth(input,rtl_filelist) eq ""} {
        handle_error "synth(input,rtl_filelist) not set — RTL filelist required"
        exit 1
    }

    set _rtl_file $synth(input,rtl_filelist)
    if {![file exists $_rtl_file]} {
        handle_error "RTL filelist not found: $_rtl_file"
        exit 1
    }

    handle_info "Reading RTL from filelist: $_rtl_file"

    # Parse filelist and classify by extension
    set _vhdl_files {}
    set _sv_files {}
    set _v_files {}

    set _fh [open $_rtl_file r]
    while {[gets $_fh _line] >= 0} {
        set _line [string trim $_line]
        if {$_line eq "" || [string index $_line 0] eq "#"} { continue }
        if {![file exists $_line]} {
            handle_warning "RTL file not found: $_line"
            continue
        }
        set _ext [file extension $_line]
        switch -- $_ext {
            ".vhd"  { lappend _vhdl_files $_line }
            ".vhdl" { lappend _vhdl_files $_line }
            ".sv"   { lappend _sv_files $_line }
            ".svh"  { lappend _sv_files $_line }
            default { lappend _v_files $_line }
        }
    }
    close $_fh

    # Read VHDL first, then SystemVerilog, then Verilog
    if {[llength $_vhdl_files] > 0} {
        handle_info "Reading [llength $_vhdl_files] VHDL files"
        read_hdl -vhdl $_vhdl_files
    }
    if {[llength $_sv_files] > 0} {
        handle_info "Reading [llength $_sv_files] SystemVerilog files"
        read_hdl -sv $_sv_files
    }
    if {[llength $_v_files] > 0} {
        handle_info "Reading [llength $_v_files] Verilog files"
        read_hdl -v2001 $_v_files
    }

    # -- Include directories ---------------------------------------------------
    if {[info exists synth(input,include_dirs)] && [llength $synth(input,include_dirs)] > 0} {
        foreach inc_dir $synth(input,include_dirs) {
            if {[file isdirectory $inc_dir]} {
                set_db hdl_search_path [concat [get_db hdl_search_path] $inc_dir]
            }
        }
    }

    # -- Define macros ---------------------------------------------------------
    if {[info exists synth(input,defines)] && [llength $synth(input,defines)] > 0} {
        foreach def $synth(input,defines) {
            set_db hdl_define_list [concat [get_db hdl_define_list] $def]
        }
    }

    # -- Elaborate design ------------------------------------------------------
    handle_info "Elaborating design: $design_name"
    elaborate $design_name

    # Check elaboration result
    if {[get_db current_design] eq ""} {
        handle_error "Elaboration failed for $design_name"
        return -code error "Elaboration failed"
    }

    handle_info "Design elaborated: $design_name"
}

# ==============================================================================
# flow_proc: setup_design_checks
# Genus-RM: check_design, uniquify, report
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global synth flow

    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : $flow(design_name)}]

    # Uniquify the design
    uniquify $design_name

    # Check design for issues
    check_design -unresolved > $::REPORTS_DIR/check_design_unresolved.rpt
    handle_info "Design check report: $::REPORTS_DIR/check_design_unresolved.rpt"

    handle_info "Design checks completed"
}

# ==============================================================================
# flow_proc: load_constraints
# Genus-RM: read_sdc -- timing constraints
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing constraints..."
    global synth flow

    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : $flow(design_name)}]

    # -- SDC constraints -------------------------------------------------------
    set sdc_file ""
    if {[info exists synth(input,sdc_file)] && $synth(input,sdc_file) ne ""} {
        set sdc_file $synth(input,sdc_file)
    } else {
        set sdc_file "$::SDC_DIR/${design_name}.sdc"
    }

    if {$sdc_file ne "" && [file exists $sdc_file]} {
        handle_info "Reading SDC: $sdc_file"
        read_sdc $sdc_file
    } else {
        # Try constraints directory
        set sdc_files [glob -nocomplain "$::SDC_DIR/*.sdc"]
        if {[llength $sdc_files] > 0} {
            foreach sdc $sdc_files {
                handle_info "Reading SDC: $sdc"
                read_sdc $sdc
            }
        } else {
            handle_warning "No SDC file found -- synthesis will run without timing constraints"
        }
    }

    # -- Additional constraint files -------------------------------------------
    if {[info exists synth(input,additional_sdc)] && [llength $synth(input,additional_sdc)] > 0} {
        foreach sdc $synth(input,additional_sdc) {
            if {[file exists $sdc]} {
                handle_info "Reading additional SDC: $sdc"
                read_sdc $sdc
            }
        }
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_power_intent
# Genus-RM: read_power_intent (UPF/CPF)
# ==============================================================================
flow_proc setup_power_intent {
    handle_info "Setting up power intent..."
    global synth

    # UPF (IEEE 1801)
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        if {[file exists $synth(input,upf_file)]} {
            handle_info "Reading UPF: $synth(input,upf_file)"
            read_power_intent -1801 $synth(input,upf_file)
            handle_info "UPF loaded"
        } else {
            handle_warning "UPF file not found: $synth(input,upf_file)"
        }
    } elseif {[info exists synth(input,cpf_file)] && $synth(input,cpf_file) ne ""} {
        # CPF (Cadence Power Format)
        if {[file exists $synth(input,cpf_file)]} {
            handle_info "Reading CPF: $synth(input,cpf_file)"
            read_power_intent -cpf $synth(input,cpf_file)
            handle_info "CPF loaded"
        }
    } else {
        handle_info "No power intent file specified -- single power domain"
    }

    handle_info "Power intent setup completed"
}

# ==============================================================================
# flow_proc: setup_mmmc
# Genus-RM: Multi-mode multi-corner setup via library_sets and analysis_views
# ==============================================================================
flow_proc setup_mmmc {
    handle_info "Setting up MMMC for Genus..."
    global synth project mmmc STAGE_NAME

    # Source the pre-generated MMMC view definition file
    set _vd_file "$::env(FLOW_DIR)/config/project/$project(name)/$project(cbflow_release)/mmmc_view_definition.tcl"

    # User override
    if {[info exists synth(input,mmmc_file)] && $synth(input,mmmc_file) ne ""} {
        set _vd_file $synth(input,mmmc_file)
    }

    if {[file exists $_vd_file]} {
        handle_info "Sourcing MMMC view definition: [file tail $_vd_file]"
        source $_vd_file
        handle_info "MMMC views loaded"
    } else {
        handle_info "No MMMC view definition — single corner mode"
        handle_info "  Generate with: cbflow flow mmmc-manager generate --project $project(name)"
        return
    }

    # Activate only synthesis node scenarios
    if {[info exists mmmc($STAGE_NAME)]} {
        array set _nd $mmmc($STAGE_NAME)
        set _setup [expr {[info exists _nd(setup)] ? $_nd(setup) : {}}]
        set _hold  [expr {[info exists _nd(hold)]  ? $_nd(hold)  : {}}]

        handle_info "  Activating scenarios for: $STAGE_NAME"
        handle_info "    Setup: $_setup"
        handle_info "    Hold:  $_hold"

        set_analysis_view -setup {} -hold {}
        set_analysis_view -setup $_setup -hold $_hold
    }

    handle_info "MMMC setup completed"
}

# ==============================================================================
# flow_proc: setup_dont_use
# Genus-RM: set_dont_use / set_attribute -- library cell restrictions
# ==============================================================================
flow_proc setup_dont_use {
    handle_info "Setting library cell restrictions..."
    global synth tech

    # Dont-use cells
    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            set_dont_use $cell
        }
        handle_info "Dont-use applied: [llength $tech(dont_use_cells)] cells"
    }

    # Dont-touch cells
    if {[info exists tech(dont_touch_cells)] && $tech(dont_touch_cells) ne ""} {
        foreach cell $tech(dont_touch_cells) {
            set_dont_touch $cell
        }
        handle_info "Dont-touch applied: [llength $tech(dont_touch_cells)] cells"
    }

    # Lib cell purpose file
    if {[info exists synth(common,lib_cell_purpose_file)] && [file exists $synth(common,lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose: $synth(common,lib_cell_purpose_file)"
        source $synth(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        handle_info "Sourcing lib cell purpose from tech: $tech(lib_cell_purpose_file)"
        source $tech(lib_cell_purpose_file)
    }

    handle_info "Library cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_dft
# Genus-RM: DFT scan configuration
# ==============================================================================
flow_proc setup_dft {
    handle_info "Setting up DFT..."
    global synth

    if {[info exists synth(common,dft_setup_file)] && [file exists $synth(common,dft_setup_file)]} {
        handle_info "Sourcing DFT setup: $synth(common,dft_setup_file)"
        source $synth(common,dft_setup_file)
    } elseif {[info exists synth(common,dft_ports_file)] && [file exists $synth(common,dft_ports_file)]} {
        handle_info "Sourcing DFT ports: $synth(common,dft_ports_file)"
        source $synth(common,dft_ports_file)
    }

    handle_info "DFT setup completed"
}

# ==============================================================================
# flow_proc: save_design
# Genus-RM: write_db, write_snapshot
# ==============================================================================
flow_proc save_design {
    handle_info "Saving init_design checkpoint..."
    global synth flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : $flow(design_name)}]

    file mkdir "$run_dir/outputs"

    # Write Genus database
    write_db $::OUTPUTS_DIR/init_design_genus.db
    handle_info "Genus DB saved: $::OUTPUTS_DIR/init_design_genus.db"

    # Write design snapshot
    catch {
        write_snapshot -outdir $::REPORTS_DIR -tag init_design
        handle_info "Design snapshot saved"
    }

    handle_info "Init design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# Genus-RM: report_summary, report_timing, report_dp, report_messages
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating init_design reports..."
    global synth

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists synth(analysis,max_paths)] ? $synth(analysis,max_paths) : 100}]

    # Design summary
    catch { report_summary > $::REPORTS_DIR/report_summary.rpt }

    # Timing report
    catch {
        report_timing -max_paths $max_paths > $::REPORTS_DIR/report_timing.rpt
    }

    # Area report
    catch { report_area > $::REPORTS_DIR/report_area.rpt }

    # Power report
    catch { report_power > $::REPORTS_DIR/report_power.rpt }

    # Design quality metrics
    catch { report_qor > $::REPORTS_DIR/report_qor.rpt }

    # Messages summary
    catch { report_messages > $::REPORTS_DIR/report_messages.rpt }

    handle_info "Init design reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Init design completed -- exiting Genus"
exit
