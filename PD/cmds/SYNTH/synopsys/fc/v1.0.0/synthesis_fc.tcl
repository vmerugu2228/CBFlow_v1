#!/usr/bin/env tclsh
# SYNTH synthesis - Synopsys Fusion Compiler
# Complete synthesis flow: create_lib → read RTL → elaborate → MCMM → compile_fusion → save

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
# flow_proc: create_design_library
# FC-RM: create_lib — NDM reference libraries, tech file, fusion libs
# ==============================================================================
flow_proc create_design_library {
    handle_info "Creating design library..."
    global synth tech flow project

    set design_name $flow(design_name)
    set lib_name "${design_name}.nlib"

    # Remove existing library
    if {[file exists $lib_name]} {
        catch {
            foreach nfs_file [glob -nocomplain ${lib_name}/.nfs*] {
                catch { file delete -force $nfs_file }
            }
        }
        catch { file delete -force $lib_name }
    }

    # ── Build reference library list (track-aware) ──
    set ref_libs [list]
    set _trk $project(track_variant)

    if {[info exists tech(${_trk},ndm)] && [llength $tech(${_trk},ndm)] > 0} {
        set ref_libs $tech(${_trk},ndm)
        handle_info "NDM libraries ($_trk): [llength $ref_libs] libs"
    }

    # ── On-the-fly fusion library creation (LEF + DB — when no NDM) ──
    set fusion_lef_list [list]
    set fusion_db_list [list]

    if {[llength $ref_libs] == 0} {
        handle_info "No NDM libraries — creating fusion libs from LEF+DB..."
        if {[info exists tech(${_trk},lef)]} {
            set fusion_lef_list $tech(${_trk},lef)
        }
        if {[info exists tech(${_trk},db)]} {
            set fusion_db_list $tech(${_trk},db)
        }
        if {[llength $fusion_lef_list] > 0 && [llength $fusion_db_list] > 0} {
            set fusion_dir "$run_dir/work/SYNTH/synthesis1/fusion_libs"
            file mkdir $fusion_dir
            create_fusion_reference_library \
                -output_directory $fusion_dir \
                -lef_files $fusion_lef_list \
                -db_files $fusion_db_list
            foreach lib [glob -nocomplain -type d ${fusion_dir}/*] {
                lappend ref_libs $lib
            }
            handle_info "Fusion reference libraries created"
        }
    }

    # ── Technology file ──
    set _ms $project(metal_stack)
    set tech_file ""
    if {[info exists tech(${_ms},tech_file)] && $tech(${_ms},tech_file) ne ""} {
        set tech_file $tech(${_ms},tech_file)
    } elseif {[info exists tech($project(metal_stack),$tech(track),tech_file)] && $tech($project(metal_stack),$tech(track),tech_file) ne ""} {
        set tech_file $tech($project(metal_stack),$tech(track),tech_file)
    }

    # ── Build create_lib command ──
    set create_lib_cmd "create_lib $lib_name"
    if {$tech_file ne "" && [file exists $tech_file]} {
        lappend create_lib_cmd -tech $tech_file
    }
    if {[llength $ref_libs] > 0} {
        lappend create_lib_cmd -ref_libs
        foreach _rl $ref_libs { lappend create_lib_cmd $_rl }
    }

    handle_info "create_lib: $create_lib_cmd"
    eval $create_lib_cmd

    if {[llength $fusion_db_list] > 0} {
        set_app_var link_library $fusion_db_list
    }

    redirect -file $::REPORTS_DIR/report_ref_libs { report_ref_libs }
    handle_info "Design library created: $lib_name"
}

# ==============================================================================
# flow_proc: read_design
# FC-RM: read_verilog / read_sverilog, elaborate, current_block, link_block
# ==============================================================================
flow_proc read_design {
    handle_info "Reading RTL design..."
    global synth flow

    set design_name $flow(design_name)

    # SVF for formality
    set_svf $::OUTPUTS_DIR/synthesis.svf

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
        read_vhdl $_vhdl_files
    }
    if {[llength $_sv_files] > 0} {
        handle_info "Reading [llength $_sv_files] SystemVerilog files"
        read_sverilog $_sv_files
    }
    if {[llength $_v_files] > 0} {
        handle_info "Reading [llength $_v_files] Verilog files"
        read_verilog $_v_files
    }

    elaborate $design_name
    current_block $design_name
    link_block

    save_lib
    handle_info "Design read and linked: $design_name"
}

# ==============================================================================
# flow_proc: setup_technology
# FC-RM: set_technology -node, tech setup script
# ==============================================================================
flow_proc setup_technology {
    handle_info "Setting up technology..."
    global tech

    if {[info exists tech(node)] && $tech(node) ne ""} {
        set_technology -node $tech(node)
        handle_info "Technology node: $tech(node)"
    }

    if {[info exists tech(tech_setup_script)] && [file exists $tech(tech_setup_script)]} {
        source $tech(tech_setup_script)
    }

    save_lib -all
    handle_info "Technology setup completed"
}

# ==============================================================================
# flow_proc: setup_design_checks
# FC-RM: uniquify, check_design, check_duplicates
# ==============================================================================
flow_proc setup_design_checks {
    handle_info "Running design checks..."
    global flow

    set_app_option -name design.uniquify_naming_style -value $flow(design_name)_%s_%d
    uniquify

    redirect -file $::REPORTS_DIR/check_design.rpt { check_design -checks design_mismatch }
    redirect -file $::REPORTS_DIR/report_unbound.rpt { report_unbound }
    check_duplicates -remove

    handle_info "Design checks completed"
}

# ==============================================================================
# flow_proc: load_constraints
# FC-RM: source SDC, load_upf, commit_upf
# ==============================================================================
flow_proc load_constraints {
    handle_info "Loading constraints..."
    global synth flow

    # ── SDC ──
    if {[info exists synth(input,sdc_func_file)] && $synth(input,sdc_func_file) ne "" && [file exists $synth(input,sdc_func_file)]} {
        handle_info "Reading SDC: $synth(input,sdc_func_file)"
        source $synth(input,sdc_func_file)
    } elseif {[info exists synth(input,sdc_file)] && $synth(input,sdc_file) ne "" && [file exists $synth(input,sdc_file)]} {
        handle_info "Reading SDC: $synth(input,sdc_file)"
        source $synth(input,sdc_file)
    } else {
        handle_warning "No SDC file found"
    }

    # ── UPF ──
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne "" && [file exists $synth(input,upf_file)]} {
        handle_info "Loading UPF: $synth(input,upf_file)"
        load_upf $synth(input,upf_file)
        if {[info exists synth(input,upf_supplemental)] && [file exists $synth(input,upf_supplemental)]} {
            load_upf -supplemental $synth(input,upf_supplemental)
        }
        commit_upf
        handle_info "UPF committed"
    }

    handle_info "Constraints loaded"
}

# ==============================================================================
# flow_proc: setup_mcmm
# FC-RM: MCMM — create_mode, create_corner, create_scenario
# ==============================================================================
flow_proc setup_mcmm {
    handle_info "Setting up MCMM scenarios..."
    global synth tech

    if {[info exists synth(common,mcmm_setup_file)] && [file exists $synth(common,mcmm_setup_file)]} {
        handle_info "Sourcing MCMM setup: $synth(common,mcmm_setup_file)"
        source $synth(common,mcmm_setup_file)
    } else {
        # Auto-create from mmmc_config analysis_views
        global analysis_views library_sets
        if {[info exists analysis_views] && [array size analysis_views] > 0} {
            set _modes_created {}
            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                set _mode $_v(mode)
                if {$_mode ni $_modes_created} {
                    create_mode $_mode
                    lappend _modes_created $_mode
                }
                array unset _v
            }

            set _corners_created {}
            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                set _corner_name "$_v(corner)_$_v(lib_set_ref)"
                if {$_corner_name ni $_corners_created} {
                    create_corner $_corner_name
                    lappend _corners_created $_corner_name
                }
                array unset _v
            }

            foreach scenario [array names analysis_views] {
                array set _v $analysis_views($scenario)
                create_scenario -name $scenario \
                    -mode $_v(mode) \
                    -corner "$_v(corner)_$_v(lib_set_ref)"
                array unset _v
            }

            handle_info "MCMM: [llength $_modes_created] modes, [llength $_corners_created] corners, [array size analysis_views] scenarios"
        } else {
            handle_info "No MCMM analysis_views — single corner mode"
        }
    }

    # Remove propagated clocks for synthesis
    set cur_mode [current_mode]
    foreach_in_collection mode [all_modes] {
        current_mode $mode
        catch { remove_propagated_clocks [all_clocks] }
        catch { remove_propagated_clocks [get_ports] }
    }
    current_mode $cur_mode

    handle_info "MCMM setup completed"
}

# ==============================================================================
# flow_proc: setup_lib_cell_purpose
# FC-RM: set_lib_cell_purpose, dont_use cells
# ==============================================================================
flow_proc setup_lib_cell_purpose {
    handle_info "Setting library cell restrictions..."
    global synth tech

    if {[info exists synth(common,lib_cell_purpose_file)] && [file exists $synth(common,lib_cell_purpose_file)]} {
        source $synth(common,lib_cell_purpose_file)
    } elseif {[info exists tech(lib_cell_purpose_file)] && [file exists $tech(lib_cell_purpose_file)]} {
        source $tech(lib_cell_purpose_file)
    }

    if {[info exists tech(dont_use_cells)] && $tech(dont_use_cells) ne ""} {
        foreach cell $tech(dont_use_cells) {
            set_lib_cell_purpose -exclude optimization [get_lib_cells $cell]
        }
        handle_info "Dont-use: [llength $tech(dont_use_cells)] cells"
    }

    handle_info "Cell restrictions applied"
}

# ==============================================================================
# flow_proc: setup_timing_variations
# FC-RM: POCV / AOCV setup
# ==============================================================================
flow_proc setup_timing_variations {
    handle_info "Setting up timing variations..."
    global synth tech

    if {[info exists synth(common,pocv_setup_file)] && [file exists $synth(common,pocv_setup_file)]} {
        source $synth(common,pocv_setup_file)
        set_app_options -name time.pocvm_enable_analysis -value true
        handle_info "POCV enabled"
    } elseif {[info exists synth(common,aocv_setup_file)] && [file exists $synth(common,aocv_setup_file)]} {
        source $synth(common,aocv_setup_file)
        handle_info "AOCV enabled"
    } elseif {[info exists tech(ocv,derate_file)] && [file exists $tech(ocv,derate_file)]} {
        source $tech(ocv,derate_file)
    }

    handle_info "Timing variation setup completed"
}

# ==============================================================================
# flow_proc: set_qor_strategy
# FC-RM: set_qor_strategy for synthesis
# ==============================================================================
flow_proc set_qor_strategy {
    handle_info "Setting QoR strategy..."
    global synth

    set _metric [expr {[info exists synth(compile,qor_metric)] && $synth(compile,qor_metric) ne "" ? $synth(compile,qor_metric) : "timing"}]
    set _mode [expr {[info exists synth(compile,qor_mode)] && $synth(compile,qor_mode) ne "" ? $synth(compile,qor_mode) : "balanced"}]

    set _cmd "set_qor_strategy -stage synthesis -metric $_metric -mode $_mode"
    if {[info exists synth(compile,high_effort_timing)] && $synth(compile,high_effort_timing) ne "" && [string is true -strict $synth(compile,high_effort_timing)]} {
        append _cmd " -high_effort_timing"
    }

    handle_info "QoR: $_cmd"
    eval $_cmd
}

# ==============================================================================
# flow_proc: configure_compile
# FC-RM: app_options for compile_fusion
# ==============================================================================
flow_proc configure_compile {
    handle_info "Configuring compile options..."
    global synth

    set_app_options -name opt.common.user_instance_name_prefix -value compile_
    set_app_options -name cts.common.user_instance_name_prefix -value compile_cts_
    set_app_options -name hdlin.naming.upf_compatible -value true

    if {[info exists synth(compile,enable_spg)] && $synth(compile,enable_spg) ne "" && [string is true -strict $synth(compile,enable_spg)]} {
        set_app_options -name compile.flow.enable_spg -value true
        handle_info "SPG enabled"
    }

    if {[info exists synth(route,max_layer)] && $synth(route,max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $synth(route,max_layer)
    }
    if {[info exists synth(route,min_layer)] && $synth(route,min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $synth(route,min_layer)
    }

    if {[info exists synth(synthesis,timing_driven)]} {
        set_app_options -name compile.flow.enable_timing_driven -value $synth(synthesis,timing_driven)
    }
    if {[info exists synth(synthesis,clock_gating)] && $synth(synthesis,clock_gating) ne "" && [string is true -strict $synth(synthesis,clock_gating)]} {
        set_app_options -name compile.flow.clock_gate_insertion -value true
    }
    if {[info exists synth(synthesis,boundary_opt)] && $synth(synthesis,boundary_opt) ne ""} {
        set_app_options -name compile.flow.boundary_optimization -value $synth(synthesis,boundary_opt)
    }
    if {[info exists synth(synthesis,max_fanout)] && $synth(synthesis,max_fanout) ne ""} {
        set_max_fanout $synth(synthesis,max_fanout) [current_design]
    }
    if {[info exists synth(synthesis,max_transition)] && $synth(synthesis,max_transition) ne ""} {
        set_max_transition $synth(synthesis,max_transition) [current_design]
    }

    handle_info "Compile options configured"
}

# ==============================================================================
# flow_proc: run_compile_fusion
# FC-RM: compile_fusion — unified FC synthesis command
# ==============================================================================
flow_proc run_compile_fusion {
    handle_info "Running compile_fusion..."
    global synth

    # MV cells for UPF
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        create_mv_cells -verbose
    }

    # Pre-compile check
    redirect -file $::REPORTS_DIR/compile_fusion.check_only { compile_fusion -check_only }

    # Primary compile
    compile_fusion

    handle_info "compile_fusion completed"
}

# ==============================================================================
# flow_proc: run_incremental_compile
# FC-RM: compile_fusion -incremental true
# ==============================================================================
flow_proc run_incremental_compile {
    handle_info "Running incremental compile_fusion..."

    compile_fusion -incremental true

    handle_info "Incremental compile completed"
}

# ==============================================================================
# flow_proc: connect_pg
# FC-RM: connect_pg_net -automatic
# ==============================================================================
flow_proc connect_pg {
    handle_info "Connecting PG nets..."
    global synth

    if {[info exists synth(common,connect_pg_net_script)] && [file exists $synth(common,connect_pg_net_script)]} {
        source $synth(common,connect_pg_net_script)
    } else {
        connect_pg_net -automatic
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_area, report_power
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating synthesis reports..."
    global synth

    file mkdir "$::REPORTS_DIR"

    set _max_paths 100
    if {[info exists synth(analysis,max_paths)] && $synth(analysis,max_paths) ne ""} {
        set _max_paths $synth(analysis,max_paths)
    }

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_qor_summary.rpt { report_qor -summary }
    redirect -file $::REPORTS_DIR/report_timing.rpt { report_timing -max_paths $_max_paths }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt { report_timing -max_paths $_max_paths -delay_type min }
    redirect -file $::REPORTS_DIR/report_area.rpt { report_area }
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_app_options.rpt { report_app_options -non_default * }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block, write_verilog, write_sdc, saif_map
# ==============================================================================
flow_proc save_design {
    handle_info "Saving synthesis outputs..."
    global synth flow

    file mkdir "$::OUTPUTS_DIR"

    set _design $flow(design_name)

    # Change names for netlist write-out
    change_names -rules verilog -hierarchy -skip_physical_only_cells

    # ── Verilog netlist ──
    if {![info exists synth(output,save_verilog)] || $synth(output,save_verilog) ne "false"} {
        write_verilog -compress gzip \
            -exclude {scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells diode_cells} \
            -hierarchy all \
            $::OUTPUTS_DIR/${_design}.v
        handle_info "Netlist: $::OUTPUTS_DIR/${_design}.v"
    }

    # ── SDC ──
    if {![info exists synth(output,save_sdc)] || $synth(output,save_sdc) ne "false"} {
        write_sdc $::OUTPUTS_DIR/${_design}.sdc
        handle_info "SDC: $::OUTPUTS_DIR/${_design}.sdc"
    }

    # ── SAIF maps ──
    catch { saif_map -type ptpx -write_map $::OUTPUTS_DIR/${_design}.saif.ptpx.map }
    catch { saif_map -write_map $::OUTPUTS_DIR/${_design}.saif.fc.map }

    # ── UPF ──
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        catch { save_upf $::OUTPUTS_DIR/${_design}.upf }
    }

    # ── SVF off ──
    set_svf -off

    # ── Save block ──
    save_lib -all
    save_block
    if {[info exists synth(output,block_labeling)] && $synth(output,block_labeling) ne "" && [string is true -strict $synth(output,block_labeling)]} {
        save_block -as ${_design}/synthesis
        handle_info "Block saved: ${_design}/synthesis"
    }

    handle_info "Synthesis outputs saved"
}

# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Synthesis completed -- exiting fc_shell"
exit
