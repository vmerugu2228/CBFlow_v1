#!/usr/bin/env tclsh
# CBFlow SYNTH synthesis1 - Synopsys Fusion Compiler | SYNTH synthesis1
# Ported from FC-RM Y-2026.03 compile.tcl

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "synthesis"
set NODE_NAME "synthesis1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
# flow_proc: setup_libraries
# Set up libraries and MMMC multi-corner configuration
# ---------------------------------------------------------------------------
flow_proc setup_libraries {
    handle_info "Setting up libraries..."
    file mkdir $::REPORTS_DIR
    puts "Reading Liberty/NDM files for Fusion Compiler..."
    puts " Libraries setup completed"

    # MMMC: Load multi-corner libraries for synthesis
    if {[info proc is_mmmc_enabled] ne "" && [is_mmmc_enabled]} {
        set synth_scenarios [get_node_scenarios "synthesis" "all"]
        handle_info "MMMC: Multi-corner synthesis with [llength $synth_scenarios] scenarios"

        # Load all corner libraries for multi-corner compile
        set all_target_libs {}
        foreach scenario $synth_scenarios {
            array set view [get_analysis_view $scenario]
            set lib_set_name $view(lib_set_ref)
            if {[info exists library_sets($lib_set_name)]} {
                array set lib_info $library_sets($lib_set_name)
                foreach lib $lib_info(timing_libraries) {
                    if {$lib ni $all_target_libs} {
                        lappend all_target_libs $lib
                    }
                }
                array unset lib_info
            }
            handle_info "  Corner: $scenario (lib_set=$lib_set_name, corner=$view(corner), voltage=$view(voltage)V, temp=$view(temperature)C)"
            array unset view
        }

        # Set multi-corner target libraries
        if {[llength $all_target_libs] > 0} {
            handle_info "MMMC: Loading [llength $all_target_libs] corner libraries"
            set_app_var target_library $all_target_libs
        }
    }
}

# ---------------------------------------------------------------------------
# flow_proc: read_rtl
# Read RTL source files and elaborate top module
# ---------------------------------------------------------------------------
flow_proc read_rtl {
    handle_info "Reading RTL..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rtl_files [glob -nocomplain "$run_dir/work/SYNTH/inputs/rtl/*"]
    puts "Found [llength $rtl_files] RTL files"
    foreach f $rtl_files { puts "  Reading: [file tail $f]"; analyze -format sverilog $f }
    if {[info exists project(top_module)]} { elaborate $project(top_module) }
    puts " RTL loaded"
}

# ---------------------------------------------------------------------------
# flow_proc: set_stage_qor_strategy
# FC-RM: set_qor_strategy for synthesis stage (from compile.tcl)
# ---------------------------------------------------------------------------
flow_proc set_stage_qor_strategy {
    handle_info "Setting QoR strategy for synthesis stage..."
    global synth

    set metric "timing"
    if {[info exists synth(compile,qor_metric)]} { set metric $synth(compile,qor_metric) }

    set mode "balanced"
    if {[info exists synth(compile,qor_mode)]} { set mode $synth(compile,qor_mode) }

    set qor_cmd "set_qor_strategy -stage synthesis -metric \"$metric\" -mode \"$mode\""

    # FC-RM: Enable high effort timing if configured
    if {[info exists synth(compile,high_effort_timing)] && $synth(compile,high_effort_timing)} {
        lappend qor_cmd -high_effort_timing
    }

    puts "CBflow-info: Running $qor_cmd"
    eval $qor_cmd

    handle_info "QoR strategy set: metric=$metric, mode=$mode"
}

# ---------------------------------------------------------------------------
# flow_proc: configure_compile
# FC-RM: Apply app_options for synthesis from $synth() configuration
# ---------------------------------------------------------------------------
flow_proc configure_compile {
    handle_info "Configuring compile app options..."
    global synth

    # FC-RM: Instance name prefix for compile-inserted cells
    set_app_options -name opt.common.user_instance_name_prefix -value compile_
    set_app_options -name cts.common.user_instance_name_prefix -value compile_cts_

    # FC-RM: UPF-compatible naming
    set_app_options -name hdlin.naming.upf_compatible -value true

    # FC-RM: Enable SPG (Synopsys Physical Guidance) if configured
    if {[info exists synth(compile,enable_spg)] && $synth(compile,enable_spg)} {
        set_app_options -name compile.flow.enable_spg -value true
        handle_info "SPG (Synopsys Physical Guidance) enabled"
    }

    # FC-RM: Routing layer constraints
    if {[info exists synth(route,max_layer)] && $synth(route,max_layer) ne ""} {
        set_ignored_layers -max_routing_layer $synth(route,max_layer)
    }
    if {[info exists synth(route,min_layer)] && $synth(route,min_layer) ne ""} {
        set_ignored_layers -min_routing_layer $synth(route,min_layer)
    }

    # FC-RM: Timing-driven synthesis settings
    if {[info exists synth(synthesis,timing_driven)]} {
        set_app_options -name compile.flow.enable_timing_driven -value $synth(synthesis,timing_driven)
    }

    # FC-RM: Clock gating
    if {[info exists synth(synthesis,clock_gating)] && $synth(synthesis,clock_gating)} {
        set_app_options -name compile.flow.clock_gate_insertion -value true
    }

    # FC-RM: Boundary optimization
    if {[info exists synth(synthesis,boundary_opt)]} {
        set_app_options -name compile.flow.boundary_optimization -value $synth(synthesis,boundary_opt)
    }

    # FC-RM: Max fanout constraint
    if {[info exists synth(synthesis,max_fanout)] && $synth(synthesis,max_fanout) ne ""} {
        set_max_fanout $synth(synthesis,max_fanout) [current_design]
    }

    # FC-RM: Max transition constraint
    if {[info exists synth(synthesis,max_transition)] && $synth(synthesis,max_transition) ne ""} {
        set_max_transition $synth(synthesis,max_transition) [current_design]
    }

    handle_info "Compile app options configured"
}

# ---------------------------------------------------------------------------
# flow_proc: run_compile_fusion
# FC-RM: Primary synthesis command - compile_fusion
# ---------------------------------------------------------------------------
flow_proc run_compile_fusion {
    handle_info "Running compile_fusion (FC-RM primary synthesis)..."
    global synth

    # FC-RM: MMMC multi-corner awareness
    if {[info exists synth(mmmc,multi_corner_compile)] && $synth(mmmc,multi_corner_compile)} {
        handle_info "MMMC: Compiling with multi-corner awareness"
    }

    # FC-RM: Create MV cells if UPF is present
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        puts "CBflow-info: Running create_mv_cells"
        create_mv_cells -verbose
    }

    # FC-RM: Pre-compile check
    puts "CBflow-info: Running compile_fusion -check_only"
    redirect -file $::REPORTS_DIR/compile_fusion.check_only {compile_fusion -check_only}

    # FC-RM: compile_fusion - the unified FC synthesis command
    puts "CBflow-info: Running compile_fusion"
    compile_fusion

    handle_info "compile_fusion completed"
}

# ---------------------------------------------------------------------------
# flow_proc: run_incremental_compile
# FC-RM: Incremental compile_fusion pass for further optimization
# ---------------------------------------------------------------------------
flow_proc run_incremental_compile {
    handle_info "Running incremental compile_fusion..."

    # FC-RM: Incremental optimization pass
    puts "CBflow-info: Running compile_fusion -incremental true"
    compile_fusion -incremental true

    handle_info "Incremental compile_fusion completed"
}

# ---------------------------------------------------------------------------
# flow_proc: connect_pg
# FC-RM: Connect power/ground nets automatically
# ---------------------------------------------------------------------------
flow_proc connect_pg {
    handle_info "Connecting PG nets..."

    # FC-RM: Automatic PG connection (from compile.tcl post-compile)
    connect_pg_net -automatic

    handle_info "PG nets connected"
}

# ---------------------------------------------------------------------------
# flow_proc: save_design_block
# FC-RM: Save design block with label for block-based flow
# ---------------------------------------------------------------------------
flow_proc save_design_block {
    handle_info "Saving design block..."
    global synth

    # FC-RM: Save block with label if block_labeling is enabled
    if {[info exists synth(output,block_labeling)] && $synth(output,block_labeling)} {
        if {[info exists synth(design,top_module)] && $synth(design,top_module) ne ""} {
            set design_name $synth(design,top_module)
        } elseif {[info exists project(top_module)] && $project(top_module) ne ""} {
            set design_name $project(top_module)
        } else {
            set design_name [get_object_name [current_design]]
        }
        puts "CBflow-info: Saving block as ${design_name}/synthesis"
        save_block -as ${design_name}/synthesis
    } else {
        save_block
    }

    handle_info "Design block saved"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_reports
# FC-RM: Generate synthesis QoR reports
# ---------------------------------------------------------------------------
flow_proc generate_reports {
    handle_info "Generating reports..."
    global synth
    file mkdir $::REPORTS_DIR

    # Determine max_paths for timing report
    set max_paths 100
    if {[info exists synth(analysis,max_paths)]} { set max_paths $synth(analysis,max_paths) }

    # FC-RM: Timing report with configurable max_paths
    redirect -file $::REPORTS_DIR/synth_timing.rpt {
        report_timing -max_paths $max_paths
    }

    # FC-RM: QoR summary
    redirect -file $::REPORTS_DIR/synth_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/synth_qor_summary.rpt { report_qor -summary }

    # FC-RM: Area report
    redirect -file $::REPORTS_DIR/synth_area.rpt { report_area }

    # FC-RM: Power report
    redirect -file $::REPORTS_DIR/synth_power.rpt { report_power }

    # FC-RM: App options snapshot
    redirect -file $::REPORTS_DIR/report_app_options.rpt {report_app_options -non_default *}

    # MMMC: Generate per-corner timing reports
    if {[info proc is_mmmc_enabled] ne "" && [is_mmmc_enabled]} {
        set synth_scenarios [get_node_scenarios "synthesis" "all"]
        foreach scenario $synth_scenarios {
            array set view [get_analysis_view $scenario]
            handle_info "MMMC: Generating report for scenario: $scenario"
            redirect -file $::REPORTS_DIR/timing_${scenario}.rpt {
                report_timing -scenarios $scenario -max_paths $max_paths
            }
            array unset view
        }
        handle_info "MMMC: Per-corner reports generated for [llength $synth_scenarios] scenarios"
    }

    puts " Reports generated"
}

# ---------------------------------------------------------------------------
# flow_proc: save_outputs
# FC-RM: Write out synthesis deliverables (netlist, SDC, name changes)
# ---------------------------------------------------------------------------
flow_proc save_outputs {
    handle_info "Saving outputs..."
    file mkdir $::OUTPUTS_DIR/netlist ; file mkdir $::OUTPUTS_DIR/sdc

    # FC-RM: Apply Verilog naming rules before write-out (from compile.tcl)
    change_names -rules verilog -hierarchy -skip_physical_only_cells

    # FC-RM: Write gate-level netlist
    write_verilog -compress gzip \
        -exclude {scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells diode_cells} \
        -hierarchy all \
        $::OUTPUTS_DIR/netlist/synth.v

    # FC-RM: Write synthesis constraints
    write_sdc $::OUTPUTS_DIR/sdc/synth.sdc

    # FC-RM: Write SAIF mapping files for power analysis hand-off
    saif_map -type ptpx -write_map $::OUTPUTS_DIR/synth.saif.ptpx.map
    saif_map -write_map $::OUTPUTS_DIR/synth.saif.fc.map

    # FC-RM: Final block save
    save_block

    puts " Outputs saved"
}

# ---------------------------------------------------------------------------
# flow_proc: synthesis1_flow
# Execute full SYNTH synthesis1 flow with FC-RM compile stages
# ---------------------------------------------------------------------------
flow_proc synthesis1_flow {
    handle_info "Executing SYNTH synthesis1 flow..."
    flow_exec setup_libraries
    flow_exec read_rtl
    flow_exec set_stage_qor_strategy
    flow_exec configure_compile
    flow_exec run_compile_fusion
    flow_exec run_incremental_compile
    flow_exec connect_pg
    flow_exec save_design_block
    flow_exec generate_reports
    flow_exec save_outputs
    handle_info "SYNTH synthesis1 completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec synthesis1_flow } else { puts " SYNTH synthesis1 procedures loaded" }

# Exit tool after stage completion
exit
