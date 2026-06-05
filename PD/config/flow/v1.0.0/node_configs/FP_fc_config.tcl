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
    floorplan,die_width         ""
    floorplan,die_height        ""
    floorplan,core_utilization  0.70
    floorplan,core_aspect_ratio 1.0
    floorplan,core_offset       "5.0 5.0 5.0 5.0"
    floorplan,macro_placement   true
    floorplan,macro_spacing     "2.0"
    floorplan,macro_channel     "5.0"
    floorplan,boundary_cells    true
    floorplan,tap_cells         true
    power,net_names             "VDD VSS"
    power,ring_width            "2.0"
    power,ring_spacing          "1.0"
    power,strap_width           "0.8"
    power,strap_pitch           "20.0"
    power,mesh_layers           "M8 M9"
}

# ┌─ FC-RM Init Design DP Control ─────────────────────────────────────────────┐
array set fp {
    init_design,input_type      "RTL"
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
    powerplan,pns_file          ""
    powerplan,compile_pg_file   ""
    powerplan,stdcell_placement true
    powerplan,stdcell_effort    "low"
}

# ┌─ FC Required Inputs (nlib handoff between stages) ─────────────────────────┐
set fp(required_inputs,init_design1)      "work/FP/netlist1/netlist work/FP/sdc1/sdc work/FP/def1/def work/FP/upf1/upf work/FP/library1/library"
set fp(required_inputs,floorplan1)        "work/FP/init_design1/outputs/init_design.nlib"
set fp(required_inputs,powerplan1)        "work/FP/floorplan1/outputs/floorplan.nlib"
set fp(required_inputs,export_data1)      "work/FP/powerplan1/outputs/powerplan.nlib"

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set fp {
    analysis,max_paths                                   ""
}

# --- COMMON (33 vars) ---
array set fp {
    common,boundary_cell                                 ""
    common,chip_type                                     ""
    common,connect_pg_net_script                         ""
    common,core_area                                     ""
    common,core_offset                                   ""
    common,core_utilization                              ""
    common,corner_cell                                   ""
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,die_area                                      ""
    common,fp_tcl                                        ""
    common,input_def                                     ""
    common,input_netlist                                 ""
    common,input_sdc                                     ""
    common,input_upf                                     ""
    common,input_upf_supplemental                        ""
    common,macro_constraints_file                        ""
    common,macro_keepout                                 ""
    common,macro_orientations                            ""
    common,max_congestion_threshold                      ""
    common,ndm_libs                                      ""
    common,pg_strap_config                               ""
    common,pin_metal_layer                               ""
    common,pin_placement_file                            ""
    common,power_domains                                 ""
    common,release_phase                                 ""
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

