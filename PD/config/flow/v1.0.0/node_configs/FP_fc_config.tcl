#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FP — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from FP_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ──────────────────────────────────────────────────────────┐
array set fp {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ FP App Settings (moved from common FP_config.tcl) ────────────────────────┐
array set fp {
    endcap,prefix               "ENDCAP"
    welltap,interval            ""
    welltap,prefix              "WELLTAP"

    power,ring_width            "2.0"
    power,ring_spacing          "1.0"
}

# ┌─ FC-RM Init Design DP Control ─────────────────────────────────────────────┐
array set fp {
    output,block_labeling       true
}

# ┌─ FC-RM Compile DP Control ─────────────────────────────────────────────────┐
array set fp {
    compile_dp,qor_metric       "timing"
    compile_dp,qor_mode         "balanced"
    compile_dp,reduced_effort   true
    compile_dp,stage            "compile_initial"
}

# ┌─ FC-RM Create Power Control ───────────────────────────────────────────────┐
array set fp {
    powerplan,compile_pg_file   ""
}

# ┌─ FC Required Inputs (nlib handoff between stages) ─────────────────────────┐
set fp(required_inputs,init_design1)      "work/FP/netlist1/netlist work/FP/sdc1/sdc work/FP/def1/def work/FP/upf1/upf work/FP/library1/library"
set fp(required_inputs,floorplan1)        "work/FP/init_design1/outputs/init_design.nlib"
set fp(required_inputs,powerplan1)        "work/FP/floorplan1/outputs/floorplan.nlib"
set fp(required_inputs,export_data1)      "work/FP/powerplan1/outputs/powerplan.nlib"

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- COMMON (33 vars) ---
array set fp {
    common,boundary_cell                                 ""
    common,chip_type                                     ""
    common,connect_pg_net_script                         ""
    common,core_area                                     ""
    common,core_offset                                   ""
    common,corner_cell                                   ""
    common,design_lib_name                               ""
    common,die_area                                      ""
    common,fp_tcl                                        ""
    common,input_def                                     ""
    common,input_upf                                     ""
    common,macro_constraints_file                        ""
    common,macro_keepout                                 ""
    common,macro_orientations                            ""
    common,max_congestion_threshold                      ""
    common,ndm_libs                                      ""
    common,pg_strap_config                               ""
    common,pin_metal_layer                               ""
    common,pin_placement_file                            ""
    common,power_domains                                 ""
    common,ring_horizontal_layer                         ""
    common,ring_spacing                                  ""
    common,ring_vertical_layer                           ""
    common,ring_width                                    ""
    common,tap_cell                                      ""
    common,tap_distance                                  ""
    common,technology_node                               ""
}

# --- COMPILE (1 vars) ---
array set fp {
    compile,qor_metric                                   ""
}

# --- COMPILE_DP (2 vars) ---
array set fp {
    compile_dp,app_options                               ""
    compile_dp,options                                   ""
}

# --- OUTPUT (1 vars) ---
array set fp {
    output,block_labeling                                ""
}


# ──────────────────────────────────────────────────────────────────────────────
# LOW-POWER INSERTION — FP/powerplan stage (POWER SWITCHES / PG CELLS)
# ──────────────────────────────────────────────────────────────────────────────
# Architecture split per user direction (2026-06-29):
#   - Power switches (PG cells) → inserted HERE in FP/powerplan
#   - Isolation cells, level shifters, AON buffers → inserted in PNR/place
#
# Master knob: `set fp(common,lowpower_enable) "true"` in user_config.
# Per-stage:   `set fp(powerplan,lowpower_enable) "true"`.
# Default OFF — existing runs unchanged.
#
# Prerequisite: UPF MUST already be loaded by FP/init_design's
# load_constraints step. The `insert_power_switches` flow_proc in
# FP/powerplan_fc.tcl enables FC's UPF implementation engine, applies
# PSW lib cells, commits UPF, and runs check_mv_design + reports.
# ──────────────────────────────────────────────────────────────────────────────
array set fp {
    common,lowpower_enable                               "false"
    powerplan,lowpower_enable                            "false"

    common,lowpower,power_switches                       "true"
    common,lowpower,power_switch_lib_cells               ""
}
