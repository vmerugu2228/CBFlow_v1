#!/usr/bin/env tclsh
# SYNTH synthesis - Cadence Genus
# Complete synthesis flow: library setup → RTL read → elaborate → compile → optimize → save

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "synthesis"
set NODE_NAME "synthesis1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: setup_libraries
# Genus-RM: set_db / read_libs / read_physical -- tech LEF, cell LEFs, timing libs
# ==============================================================================
flow_proc setup_libraries {
    handle_info "Setting up libraries..."
    global synth tech project

    set _trk $project(track_variant)
    set _ms  $project(metal_stack)

    # ── Tech LEF ──
    handle_info "Tech LEF: [file tail $tech(${_ms},${_trk},lef_tech)]"
    read_physical -lef $tech(${_ms},${_trk},lef_tech)

    # ── Cell LEFs (stdcell + memory + IO) ──
    handle_info "Cell LEFs ($_trk): [llength $tech(${_trk},lef)] files"
    foreach _lef $tech(${_trk},lef) {
        read_physical -lef $_lef
    }

    # ── Timing libs (nominal for synthesis) ──
    handle_info "Timing libs ($_trk): [llength $tech(${_trk},lib_nom)] files"
    read_libs $tech(${_trk},lib_nom)

    # ── QRC tech file (physical-aware synthesis) ──
    if {[info exists tech(rcx,${_ms},rc_typ,qrc)] && $tech(rcx,${_ms},rc_typ,qrc) ne ""} {
        handle_info "QRC tech: [file tail $tech(rcx,${_ms},rc_typ,qrc)]"
        set_db qrc_tech_file $tech(rcx,${_ms},rc_typ,qrc)
    }

    handle_info "Library setup completed"
}

# ==============================================================================
# flow_proc: setup_genus_options
# Genus-RM: set_db -- global synthesis settings
# ==============================================================================
flow_proc setup_genus_options {
    handle_info "Setting Genus options..."
    global synth tech project

    # ── Effort ──
    if {[info exists synth(compile,effort)] && $synth(compile,effort) ne ""} {
        set_db syn_global_effort $synth(compile,effort)
        handle_info "Global effort: $synth(compile,effort)"
    }

    # ── Physical-aware synthesis ──
    set _ms $project(metal_stack)
    if {[info exists tech(rcx,${_ms},rc_typ,qrc)] && $tech(rcx,${_ms},rc_typ,qrc) ne ""} {
        set _effort [expr {[info exists synth(compile,effort)] ? $synth(compile,effort) : "medium"}]
        set_db / .phys_syn_effort $_effort
        handle_info "Physical-aware synthesis enabled"
    }

    # ── Leakage power ──
    if {[info exists synth(compile,leakage_power_effort)] && $synth(compile,leakage_power_effort) ne ""} {
        set_db / .leakage_power_effort $synth(compile,leakage_power_effort)
    }

    # ── Dynamic power ──
    if {[info exists synth(compile,dynamic_power_effort)] && $synth(compile,dynamic_power_effort) ne ""} {
        set_db / .dynamic_power_effort $synth(compile,dynamic_power_effort)
    }

    # ── Routing layers ──
    if {[info exists synth(common,route_max_layer)] && $synth(common,route_max_layer) ne ""} {
        set_db design_top_routing_layer $synth(common,route_max_layer)
    }
    if {[info exists synth(common,route_min_layer)] && $synth(common,route_min_layer) ne ""} {
        set_db design_bottom_routing_layer $synth(common,route_min_layer)
    }

    # ── Max fanout / transition / capacitance ──
    if {[info exists synth(synthesis,max_fanout)] && $synth(synthesis,max_fanout) ne ""} {
        set_db design_max_fanout $synth(synthesis,max_fanout)
    }
    if {[info exists synth(synthesis,max_transition)] && $synth(synthesis,max_transition) ne ""} {
        set_db design_max_transition $synth(synthesis,max_transition)
    }
    if {[info exists synth(synthesis,max_capacitance)] && $synth(synthesis,max_capacitance) ne ""} {
        set_db design_max_capacitance $synth(synthesis,max_capacitance)
    }

    # ── Multi-CPU ──
    if {[info exists synth(synthesis,max_cores)] && $synth(synthesis,max_cores) ne ""} {
        set_db max_cpus_per_server $synth(synthesis,max_cores)
    }

    # ── Clock gating ──
    if {[info exists synth(synthesis,clock_gating)] && $synth(synthesis,clock_gating) eq "true"} {
        set_db lp_insert_clock_gating true
        handle_info "Clock gating: enabled"
    }

    # ── Boundary optimization ──
    if {[info exists synth(synthesis,boundary_opt)] && $synth(synthesis,boundary_opt) ne ""} {
        set_db syn_opt_boundary_optimization $synth(synthesis,boundary_opt)
    }

    # ── Auto ungroup ──
    if {[info exists synth(compile,auto_ungroup)] && $synth(compile,auto_ungroup) eq "true"} {
        set_db auto_ungroup both
        handle_info "Auto ungroup: enabled"
    }

    # ── Genus options file ──
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
        return
    }

    set _rtl_file $synth(input,rtl_filelist)
    if {![file exists $_rtl_file]} {
        handle_error "RTL filelist not found: $_rtl_file"
        return
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

    # ── Include directories ──
    if {[info exists synth(input,include_dirs)] && [llength $synth(input,include_dirs)] > 0} {
        foreach inc_dir $synth(input,include_dirs) {
            if {[file isdirectory $inc_dir]} {
                set_db hdl_search_path [concat [get_db hdl_search_path] $inc_dir]
            }
        }
    }

    # ── Define macros ──
    if {[info exists synth(input,defines)] && [llength $synth(input,defines)] > 0} {
        foreach def $synth(input,defines) {
            set_db hdl_define_list [concat [get_db hdl_define_list] $def]
        }
    }

    # ── Elaborate design ──
    handle_info "Elaborating design: $design_name"
    elaborate $design_name

    if {[get_db current_design] eq ""} {
        handle_error "Elaboration failed for $design_name"
        return -code error "Elaboration failed"
    }

    handle_info "Design elaborated: $design_name"
}

# ==============================================================================
# flow_proc: setup_design_checks
# Genus-RM: check_design, uniquify
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global flow

    uniquify $flow(design_name)
    check_design -unresolved > $::REPORTS_DIR/check_design_unresolved.rpt
    handle_info "Design checks completed"
}

# ==============================================================================
# flow_proc: load_constraints
# Genus-RM: read_sdc -- timing constraints
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading timing constraints..."
    global synth flow

    # ── SDC from config ──
    if {[info exists synth(input,sdc_func_file)] && $synth(input,sdc_func_file) ne "" && [file exists $synth(input,sdc_func_file)]} {
        handle_info "Reading SDC: $synth(input,sdc_func_file)"
        read_sdc $synth(input,sdc_func_file)
    } elseif {[info exists synth(input,sdc_file)] && $synth(input,sdc_file) ne "" && [file exists $synth(input,sdc_file)]} {
        handle_info "Reading SDC: $synth(input,sdc_file)"
        read_sdc $synth(input,sdc_file)
    } else {
        handle_warning "No SDC file found — synthesis will run without timing constraints"
    }

    # ── Additional constraints ──
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

    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        if {[file exists $synth(input,upf_file)]} {
            handle_info "Reading UPF: $synth(input,upf_file)"
            read_power_intent -1801 $synth(input,upf_file)
        } else {
            handle_warning "UPF file not found: $synth(input,upf_file)"
        }
    } elseif {[info exists synth(input,cpf_file)] && $synth(input,cpf_file) ne ""} {
        if {[file exists $synth(input,cpf_file)]} {
            handle_info "Reading CPF: $synth(input,cpf_file)"
            read_power_intent -cpf $synth(input,cpf_file)
        }
    } else {
        handle_info "No power intent file — single power domain"
    }

    handle_info "Power intent setup completed"
}

# ==============================================================================
# flow_proc: setup_mmmc
# Genus-RM: Multi-mode multi-corner setup
# ==============================================================================
flow_proc setup_mmmc {
    handle_info "Setting up MMMC for Genus..."
    global synth project mmmc STAGE_NAME

    set _vd_file "$::env(FLOW_DIR)/config/project/$project(name)/$project(cbflow_release)/mmmc_view_definition.tcl"

    if {[info exists synth(input,mmmc_file)] && $synth(input,mmmc_file) ne ""} {
        set _vd_file $synth(input,mmmc_file)
    }

    if {[file exists $_vd_file]} {
        handle_info "Sourcing MMMC view definition: [file tail $_vd_file]"
        source $_vd_file
    } else {
        handle_info "No MMMC view definition — single corner mode"
        return
    }

    # Activate synthesis node scenarios
    if {[info exists mmmc($STAGE_NAME)]} {
        array set _nd $mmmc($STAGE_NAME)
        set _setup [expr {[info exists _nd(setup)] ? $_nd(setup) : {}}]
        set _hold  [expr {[info exists _nd(hold)]  ? $_nd(hold)  : {}}]

        handle_info "  Setup scenarios: $_setup"
        handle_info "  Hold scenarios:  $_hold"

        set_analysis_view -setup {} -hold {}
        set_analysis_view -setup $_setup -hold $_hold
    }

    handle_info "MMMC setup completed"
}

# ==============================================================================
# flow_proc: setup_dont_use
# Genus-RM: set_dont_use / set_dont_touch -- library cell restrictions
# ==============================================================================
flow_proc setup_dont_use {
    handle_info "Setting library cell restrictions..."
    global synth tech

    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            set_dont_use $cell
        }
        handle_info "Dont-use applied: [llength $tech(dont_use_cells)] cells"
    }

    if {[info exists tech(dont_touch_cells)] && $tech(dont_touch_cells) ne ""} {
        foreach cell $tech(dont_touch_cells) {
            set_dont_touch $cell
        }
        handle_info "Dont-touch applied: [llength $tech(dont_touch_cells)] cells"
    }

    if {[info exists synth(common,lib_cell_purpose_file)] && [file exists $synth(common,lib_cell_purpose_file)]} {
        source $synth(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
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
# flow_proc: syn_generic_step
# Genus-RM: syn_generic -- Technology-independent optimization
# ==============================================================================
flow_proc syn_generic_step {
    handle_info "Running syn_generic..."

    syn_generic

    handle_info "syn_generic completed"
}

# ==============================================================================
# flow_proc: syn_map_step
# Genus-RM: syn_map -- Technology mapping
# ==============================================================================
flow_proc syn_map_step {
    handle_info "Running syn_map..."
    global synth

    if {[info exists synth(effort,mapping)] && $synth(effort,mapping) ne ""} {
        set_db syn_map_effort $synth(effort,mapping)
        handle_info "Mapping effort: $synth(effort,mapping)"
    }

    syn_map

    handle_info "syn_map completed"
}

# ==============================================================================
# flow_proc: syn_opt_step
# Genus-RM: syn_opt -- Post-mapping optimization
# ==============================================================================
flow_proc syn_opt_step {
    handle_info "Running syn_opt..."
    global synth

    if {[info exists synth(synthesis,area_recovery)] && $synth(synthesis,area_recovery) eq "true"} {
        set_db syn_opt_area_recovery true
    }
    if {[info exists synth(optimization,hold_fix)] && $synth(optimization,hold_fix) eq "true"} {
        set_db syn_opt_fix_hold_all_clocks true
    }
    if {[info exists synth(optimization,multi_vt)] && $synth(optimization,multi_vt) eq "true"} {
        set_db syn_opt_multiple_vt_optimization true
    }
    if {[info exists synth(power,effort)] && $synth(power,effort) ne ""} {
        set_db syn_opt_power_effort $synth(power,effort)
    }
    if {[info exists synth(effort,timing)] && $synth(effort,timing) ne ""} {
        set_db syn_opt_timing_effort $synth(effort,timing)
    }
    if {[info exists synth(effort,area)] && $synth(effort,area) ne ""} {
        set_db syn_opt_area_effort $synth(effort,area)
    }

    # syn_opt mode: -logical (default) or -spatial
    set _opt_mode [expr {[info exists synth(compile,syn_opt_mode)] && $synth(compile,syn_opt_mode) ne "" ? $synth(compile,syn_opt_mode) : "logical"}]
    if {$_opt_mode eq "spatial"} {
        handle_info "syn_opt -spatial"
        syn_opt -spatial
    } else {
        handle_info "syn_opt -logical"
        syn_opt -logical
    }

    handle_info "syn_opt completed"
}

# ==============================================================================
# flow_proc: generate_reports
# Genus-RM: report_timing, report_area, report_power, report_qor
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating synthesis reports..."
    global synth

    file mkdir "$::REPORTS_DIR"

    set _max_paths 100
    if {[info exists synth(analysis,max_paths)] && $synth(analysis,max_paths) ne ""} {
        set _max_paths $synth(analysis,max_paths)
    }

    catch { report_timing -max_paths $_max_paths > $::REPORTS_DIR/report_timing.rpt }
    catch { report_timing -summary > $::REPORTS_DIR/report_timing_summary.rpt }
    catch { report_area > $::REPORTS_DIR/report_area.rpt }
    catch { report_gates > $::REPORTS_DIR/report_gates.rpt }
    catch { report_power > $::REPORTS_DIR/report_power.rpt }
    catch { report_qor > $::REPORTS_DIR/report_qor.rpt }
    catch { report_constraints > $::REPORTS_DIR/report_constraints.rpt }
    catch { report_summary > $::REPORTS_DIR/report_summary.rpt }
    catch { report_messages > $::REPORTS_DIR/report_messages.rpt }

    handle_info "Reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# flow_proc: save_design
# Genus-RM: write_db, write_hdl, write_sdc -- Save synthesis outputs
# ==============================================================================
flow_proc save_design {
    handle_info "Saving synthesis outputs..."
    global synth flow

    file mkdir "$::OUTPUTS_DIR"

    set _design $flow(design_name)

    # ── Genus DB ──
    write_db $::OUTPUTS_DIR/synthesis_genus.db
    handle_info "Genus DB: $::OUTPUTS_DIR/synthesis_genus.db"

    # ── Verilog netlist ──
    if {![info exists synth(output,save_verilog)] || $synth(output,save_verilog) ne "false"} {
        write_hdl > $::OUTPUTS_DIR/${_design}.v
        handle_info "Netlist: $::OUTPUTS_DIR/${_design}.v"
    }

    # ── SDC constraints ──
    if {![info exists synth(output,save_sdc)] || $synth(output,save_sdc) ne "false"} {
        write_sdc > $::OUTPUTS_DIR/${_design}.sdc
        handle_info "SDC: $::OUTPUTS_DIR/${_design}.sdc"
    }

    # ── SDF (optional) ──
    if {[info exists synth(output,save_sdf)] && $synth(output,save_sdf) eq "true"} {
        write_sdf > $::OUTPUTS_DIR/${_design}.sdf
        handle_info "SDF: $::OUTPUTS_DIR/${_design}.sdf"
    }

    # ── Snapshot ──
    catch {
        write_snapshot -outdir $::REPORTS_DIR -tag synthesis
    }

    handle_info "Synthesis outputs saved"
}

# ==============================================================================
# Execute all flow_procs in definition order
# (setup.tcl and overrides already sourced via bootstrap config.tcl/setup.tcl)
# ==============================================================================
flow_exec_all

handle_info "Synthesis completed -- exiting Genus"
exit
