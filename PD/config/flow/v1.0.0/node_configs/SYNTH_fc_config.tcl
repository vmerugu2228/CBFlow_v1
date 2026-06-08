#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from SYNTH_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ──────────────────────────────────────────────────────────┐
array set synth {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ Synthesis App Settings (moved from common SYNTH_config.tcl) ──────────────┐
array set synth {
    synthesis,timing_driven   true
    synthesis,area_recovery   true
    synthesis,clock_gating    true
    synthesis,scan_insertion  false
    synthesis,boundary_opt    true
    synthesis,max_fanout      32
    synthesis,max_transition  "0.5"
    synthesis,max_capacitance "0.5"
    synthesis,max_cores       4
    optimization,boundary     "false"
}

# ┌─ FC-RM Compile/Synthesis Control (values aligned with FC-RM Y-2026.03) ──┐
array set synth {
    compile,unified_flow          true
    compile,qor_metric            "timing"
    compile,qor_mode              "balanced"
    compile,qor_version           ""
    compile,congestion_effort     "medium"
    compile,enable_spg            false
    compile,high_effort_timing    true
    compile,reduced_effort        false
    compile,enable_irdp           false
    dft_insert_enable             false
    upf_mode                      "none"
}

# ┌─ FC Output Format Controls ─────────────────────────────────────────────────┐
array set synth {
    output,save_ddc           "true"
    output,save_verilog       "true"
    output,save_sdf           "false"
    output,save_constraints   "true"
    output,save_svf           "false"
    output,save_spef          "false"
    output,save_sdc           "true"
    output,netlist_format     "verilog"
}

# ┌─ FC Required Inputs (nlib handoff between stages) ──────────────────────────┐
set synth(required_inputs,synthesis1)    "work/SYNTH/rtl1/rtl work/SYNTH/sdc1/sdc"
set synth(required_inputs,export_data1)  "work/SYNTH/synthesis1/outputs/synthesis.nlib"

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (2 vars) ---
array set synth {
    analysis,max_paths                                   ""
    analysis,significant_digits                          ""
}

# --- COMMON (28 vars) ---
array set synth {
    common,additional_floorplan_file                     ""
    common,aocv_setup_file                               ""
    common,chip_type                                     ""
    common,connect_pg_net_script                         ""
    common,constraints_setup_file                        ""
    common,cts_ndr_file                                  ""
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,dft_ports_file                                ""
    common,floorplan_rule_script                         ""
    common,include_dirs                                  ""
    common,input_sdc                                     ""
    common,input_upf                                     ""
    common,lib_cell_purpose_file                         ""
    common,mcmm_setup_file                               ""
    common,ndm_libs                                      ""
    common,placement_constraint_files                    ""
    common,pocv_setup_file                               ""
    common,release_phase                                 ""
    common,rtl_files                                     ""
    common,saif_file                                     ""
    common,saif_power_scenario                           ""
    common,saif_source_instance                          ""
    common,saif_target_instance                          ""
    common,spare_cells_file                              ""
    common,switch_connectivity_file                      ""
    common,top_module                                    ""
    common,upf_mode                                      ""
}

# --- COMPILE (4 vars) ---
array set synth {
    compile,enable_spg                                   ""
    compile,high_effort_timing                           ""
    compile,qor_metric                                   ""
    compile,qor_mode                                     ""
}

# --- DESIGN (1 vars) ---
array set synth {
    design,top_module                                    ""
}

# --- FP (4 vars) ---
array set synth {
    fp,aspect_ratio                                      ""
    fp,core_offset                                       ""
    fp,core_utilization                                  ""
    fp,tap_cell_distance                                 ""
}

# --- INIT_DESIGN (1 vars) ---
array set synth {
    init_design,active_scenarios                         ""
}

# --- OUTPUT (1 vars) ---
array set synth {
    output,block_labeling                                ""
}

# --- ROUTE (2 vars) ---
array set synth {
    route,max_layer                                      ""
    route,min_layer                                      ""
}

# --- SYNTHESIS (5 vars) ---
array set synth {
    synthesis,boundary_opt                               ""
    synthesis,clock_gating                               ""
    synthesis,max_fanout                                 ""
    synthesis,max_transition                             ""
    synthesis,timing_driven                              ""
}
