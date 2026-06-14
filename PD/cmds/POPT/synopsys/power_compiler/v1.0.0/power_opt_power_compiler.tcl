#!/usr/bin/env tclsh
# CBFlow POPT power_opt - Synopsys Power Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "POPT"
set STAGE_NAME "power_opt"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc analyze_power {
    handle_info "Running baseline power analysis with Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::OUTPUTS_DIR/popt"

    # Set switching activity
    if {[info exists ::popt(SAIF_FILE)]} {
        read_saif $::popt(SAIF_FILE)
        handle_info "Loaded SAIF for accurate switching"
    } else {
        set_switching_activity -static_probability 0.5 -toggle_rate 0.1
        handle_info "Using default switching activity"
    }

    # Hierarchical power breakdown
    report_power -hierarchy -levels 4 > "$::REPORTS_DIR/pre_opt_power_hier.rpt"

    # Cell-level power
    report_power -cell > "$::REPORTS_DIR/pre_opt_power_cell.rpt"

    # Net-level power
    report_power -net > "$::REPORTS_DIR/pre_opt_power_net.rpt"

    # Leakage power
    report_power -leakage > "$::REPORTS_DIR/pre_opt_leakage.rpt"

    # Overall summary
    report_power > "$::REPORTS_DIR/pre_opt_power_summary.rpt"

    handle_info "Baseline power analysis completed"
}

# ---------------------------------------------------------------------------
# flow_proc: insert_clock_gating
# Insert clock gating cells for dynamic power reduction
# ---------------------------------------------------------------------------
flow_proc insert_clock_gating {
    handle_info "Inserting clock gating with Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Configure clock gating style
    if {[info exists ::popt(CG_MIN_BITWIDTH)]} {
        set_clock_gating_style -minimum_bitwidth $::popt(CG_MIN_BITWIDTH)
    } else {
        set_clock_gating_style -minimum_bitwidth 4
    }

    # Set clock gating cell preference
    if {[info exists ::popt(CG_CELL)]} {
        set_clock_gating_style -positive_edge_logic $::popt(CG_CELL)
    }

    # Insert clock gating
    insert_clock_gating -global
    handle_info "Clock gating cells inserted"

    # Propagate clock gating
    propagate_constraints -gate_clock

    # Report clock gating coverage
    report_clock_gating > "$::REPORTS_DIR/$1"
    report_clock_gating -summary > "$::REPORTS_DIR/$1"

    # Post-CG power
    report_power > "$::REPORTS_DIR/$1"

    handle_info "Clock gating insertion completed"
}

# ---------------------------------------------------------------------------
# flow_proc: optimize_leakage
# Optimize leakage through multi-Vt swapping
# ---------------------------------------------------------------------------
flow_proc optimize_leakage {
    handle_info "Optimizing leakage power with Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Set leakage target
    if {[info exists ::popt(MAX_LEAKAGE_POWER)]} {
        set_max_leakage_power $::popt(MAX_LEAKAGE_POWER)
    } else {
        set_max_leakage_power 0
    }

    # Multi-Vt optimization
    handle_info "Running multi-Vt cell swapping..."
    set_multi_vth_constraint -lvth_percentage 0.0
    compile_ultra -gate_clock -retime

    # Report leakage after opt
    report_power -leakage > "$::REPORTS_DIR/$1"
    report_threshold_voltage_group > "$::REPORTS_DIR/$1"

    handle_info "Leakage optimization completed"
}

# ---------------------------------------------------------------------------
# flow_proc: optimize_dynamic
# Optimize dynamic power through operand isolation and switching reduction
# ---------------------------------------------------------------------------
flow_proc optimize_dynamic {
    handle_info "Optimizing dynamic power with Power Compiler..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"

    # Enable operand isolation
    set_operand_isolation_style -logic or
    set_operand_isolation_cell [get_lib_cells */ISO*] -valid

    # Insert operand isolation
    insert_operand_isolation
    handle_info "Operand isolation inserted"

    # Optimize switching activity
    set_dynamic_optimization true
    compile_ultra -incremental

    # Report dynamic power
    report_power -cell > "$::REPORTS_DIR/$1"
    report_power -net  > "$::REPORTS_DIR/$1"
    report_power > "$::REPORTS_DIR/$1"

    handle_info "Dynamic power optimization completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_report
# Generate final power optimization summary reports
# ---------------------------------------------------------------------------
flow_proc generate_report {
    handle_info "Generating Power Compiler optimization reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/popt"

    # Final power analysis
    report_power -hierarchy -levels 3 > "$::REPORTS_DIR/$1"
    report_power > "$::REPORTS_DIR/$1"

    # Timing check
    report_timing -delay max -max_paths [expr {[info exists popt(analysis,max_paths)] ? $popt(analysis,max_paths) : 100}] > "$::REPORTS_DIR/$1"

    # QoR
    report_qor > "$::REPORTS_DIR/$1"

    # Summary
    set fp [open "$res_dir/pc_power_opt.rpt" w]
    puts $fp "================================================================"
    puts $fp "Power Compiler Optimization Summary"
    puts $fp "Date: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Optimization stages:"
    puts $fp "  1. Baseline power analysis"
    puts $fp "  2. Clock gating insertion"
    puts $fp "  3. Leakage optimization (multi-Vt)"
    puts $fp "  4. Dynamic power optimization"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/$1"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Power Compiler optimization reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all power_opt flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc power_opt_flow {
    handle_info "Executing Power Compiler power_opt flow..."
    flow_exec analyze_power
    flow_exec insert_clock_gating
    flow_exec optimize_leakage
    flow_exec optimize_dynamic
    flow_exec generate_report
    handle_info "Power Compiler power_opt completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec power_opt_flow } else { puts " POPT Power Compiler power_opt procedures loaded" }

# Exit tool after stage completion
exit
