#!/usr/bin/env tclsh
# SYNTH synthesis - Cadence Genus

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
# flow_proc: load_design
# Genus-RM: read_db -- Restore design from init_design checkpoint
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design from init_design checkpoint..."
    global synth flow

    set _init_db "$run_dir/work/SYNTH/init_design1/outputs/init_design_genus.db"

    if {![file exists $_init_db]} {
        handle_error "init_design DB not found: $_init_db"
        exit 1
    }

    read_db $_init_db
    handle_info "Design loaded: $_init_db"

    # Verify design loaded
    if {[get_db current_design] eq ""} {
        handle_error "Failed to load design from DB"
        exit 1
    }

    handle_info "Current design: [get_db current_design]"
}

# ==============================================================================
# flow_proc: setup_synthesis_options
# Genus-RM: set_db -- Configure synthesis effort, timing, area, power
# ==============================================================================
flow_proc setup_synthesis_options {
    handle_info "Configuring synthesis options..."
    global synth

    # ── Effort level ──
    if {[info exists synth(compile,effort)] && $synth(compile,effort) ne ""} {
        set_db syn_global_effort $synth(compile,effort)
        handle_info "Global effort: $synth(compile,effort)"
    }

    # ── Timing-driven synthesis ──
    if {[info exists synth(synthesis,timing_driven)] && $synth(synthesis,timing_driven) ne ""} {
        set_db syn_opt_effort $synth(synthesis,timing_driven)
    }

    # ── Max fanout ──
    if {[info exists synth(synthesis,max_fanout)] && $synth(synthesis,max_fanout) ne ""} {
        set_db design_max_fanout $synth(synthesis,max_fanout)
        handle_info "Max fanout: $synth(synthesis,max_fanout)"
    }

    # ── Max transition ──
    if {[info exists synth(synthesis,max_transition)] && $synth(synthesis,max_transition) ne ""} {
        set_db design_max_transition $synth(synthesis,max_transition)
        handle_info "Max transition: $synth(synthesis,max_transition)"
    }

    # ── Max capacitance ──
    if {[info exists synth(synthesis,max_capacitance)] && $synth(synthesis,max_capacitance) ne ""} {
        set_db design_max_capacitance $synth(synthesis,max_capacitance)
        handle_info "Max capacitance: $synth(synthesis,max_capacitance)"
    }

    # ── Multi-CPU ──
    if {[info exists synth(synthesis,max_cores)] && $synth(synthesis,max_cores) ne ""} {
        set_db max_cpus_per_server $synth(synthesis,max_cores)
        handle_info "Max cores: $synth(synthesis,max_cores)"
    }

    # ── Leakage power optimization ──
    if {[info exists synth(compile,leakage_power_effort)] && $synth(compile,leakage_power_effort) ne ""} {
        set_db / .leakage_power_effort $synth(compile,leakage_power_effort)
        handle_info "Leakage power effort: $synth(compile,leakage_power_effort)"
    }

    # ── Dynamic power optimization ──
    if {[info exists synth(compile,dynamic_power_effort)] && $synth(compile,dynamic_power_effort) ne ""} {
        set_db / .dynamic_power_effort $synth(compile,dynamic_power_effort)
        handle_info "Dynamic power effort: $synth(compile,dynamic_power_effort)"
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

    handle_info "Synthesis options configured"
}

# ==============================================================================
# flow_proc: syn_generic_step
# Genus-RM: syn_generic -- Technology-independent optimization
# ==============================================================================
flow_proc syn_generic_step {
    handle_info "Running syn_generic (technology-independent optimization)..."

    syn_generic

    handle_info "syn_generic completed"
}

# ==============================================================================
# flow_proc: syn_map_step
# Genus-RM: syn_map -- Technology mapping to target library cells
# ==============================================================================
flow_proc syn_map_step {
    handle_info "Running syn_map (technology mapping)..."
    global synth

    # ── Mapping effort ──
    if {[info exists synth(effort,mapping)] && $synth(effort,mapping) ne ""} {
        set_db syn_map_effort $synth(effort,mapping)
        handle_info "Mapping effort: $synth(effort,mapping)"
    }

    syn_map

    handle_info "syn_map completed"
}

# ==============================================================================
# flow_proc: syn_opt_step
# Genus-RM: syn_opt -- Post-mapping optimization (timing/area/power)
# ==============================================================================
flow_proc syn_opt_step {
    handle_info "Running syn_opt (post-mapping optimization)..."
    global synth

    # ── Area recovery ──
    if {[info exists synth(synthesis,area_recovery)] && $synth(synthesis,area_recovery) eq "true"} {
        set_db syn_opt_area_recovery true
        handle_info "Area recovery: enabled"
    }

    # ── Hold fixing ──
    if {[info exists synth(optimization,hold_fix)] && $synth(optimization,hold_fix) eq "true"} {
        set_db syn_opt_fix_hold_all_clocks true
        handle_info "Hold fixing: enabled"
    }

    # ── Multi-Vt optimization ──
    if {[info exists synth(optimization,multi_vt)] && $synth(optimization,multi_vt) eq "true"} {
        set_db syn_opt_multiple_vt_optimization true
        handle_info "Multi-Vt optimization: enabled"
    }

    # ── Power effort ──
    if {[info exists synth(power,effort)] && $synth(power,effort) ne ""} {
        set_db syn_opt_power_effort $synth(power,effort)
        handle_info "Power effort: $synth(power,effort)"
    }

    # ── Timing effort ──
    if {[info exists synth(effort,timing)] && $synth(effort,timing) ne ""} {
        set_db syn_opt_timing_effort $synth(effort,timing)
        handle_info "Timing effort: $synth(effort,timing)"
    }

    # ── Area effort ──
    if {[info exists synth(effort,area)] && $synth(effort,area) ne ""} {
        set_db syn_opt_area_effort $synth(effort,area)
        handle_info "Area effort: $synth(effort,area)"
    }

    syn_opt

    handle_info "syn_opt completed"
}

# ==============================================================================
# flow_proc: generate_reports
# Genus-RM: report_timing, report_area, report_power, report_qor
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating synthesis reports..."
    global synth flow

    file mkdir "$::REPORTS_DIR"

    set _max_paths 100
    if {[info exists synth(analysis,max_paths)] && $synth(analysis,max_paths) ne ""} {
        set _max_paths $synth(analysis,max_paths)
    }

    # Timing
    catch { report_timing -max_paths $_max_paths > $::REPORTS_DIR/report_timing.rpt }

    # Timing summary
    catch { report_timing -summary > $::REPORTS_DIR/report_timing_summary.rpt }

    # Area
    catch { report_area > $::REPORTS_DIR/report_area.rpt }

    # Gates
    catch { report_gates > $::REPORTS_DIR/report_gates.rpt }

    # Power
    catch { report_power > $::REPORTS_DIR/report_power.rpt }

    # QoR
    catch { report_qor > $::REPORTS_DIR/report_qor.rpt }

    # Constraints
    catch { report_constraints > $::REPORTS_DIR/report_constraints.rpt }

    # Design summary
    catch { report_summary > $::REPORTS_DIR/report_summary.rpt }

    # Messages
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

    # ── Design snapshot ──
    catch {
        write_snapshot -outdir $::REPORTS_DIR -tag synthesis
        handle_info "Design snapshot saved"
    }

    handle_info "Synthesis outputs saved"
}

# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/SYNTH/synthesis1/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source $_override_file
}
set _stage_override "$run_dir/setup/override_setup.synthesis.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source $_stage_override
}

# ==============================================================================
# Execute all flow_procs in definition order
# ==============================================================================
flow_exec_all

handle_info "Synthesis completed -- exiting Genus"
exit
