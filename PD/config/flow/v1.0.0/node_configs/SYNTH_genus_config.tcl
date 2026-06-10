#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH — Cadence Genus Tool Configuration
# Sourced from SYNTH_config.tcl when tool=genus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Genus Tool Settings ──────────────────────────────────────────────────────┐
array set synth {
    tool,vendor   "cadence"
    tool,name     "genus"
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

# ┌─ Genus Compile/Synthesis Control ──────────────────────────────────────────┐
array set synth {
    compile,effort                "high"
    compile,enable_cpf            false
    compile,leakage_optimization  true
    compile,dft_insert_enable     false
    compile,spatial_opt           false
    compile,auto_ungroup          true
    compile,syn_opt_mode          "logical"
    upf_mode                      "none"
}

# ┌─ Genus Output Format Controls ─────────────────────────────────────────────┐
array set synth {
    output,save_verilog       "true"
    output,save_sdf           "false"
    output,save_constraints   "true"
    output,save_sdc           "true"
    output,save_spef          "false"
    output,save_db            "true"
    output,netlist_format     "verilog"
}

# ┌─ Genus Required Inputs (enc handoff between stages) ────────────────────────┐
set synth(required_inputs,synthesis1)    "work/SYNTH/rtl1/rtl work/SYNTH/sdc1/sdc"
set synth(required_inputs,export_data1)  "work/SYNTH/synthesis1/outputs/synthesis_genus.db"

# ── Genus-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set synth {
    analysis,max_paths                                   ""
}

# --- AREA (1 vars) ---
array set synth {
    area,recover_design_area                             ""
}

# --- COMMON (12 vars) ---
array set synth {
    common,design_name                                   ""
    common,dft_ports_file                                ""
    common,dft_setup_file                                ""
    common,effort                                        ""
    common,genus_options_file                            ""
    common,lib_cell_purpose_file                         ""
    common,mcmm_setup_file                               ""
    common,release_phase                                 ""
    common,route_max_layer                               ""
    common,route_min_layer                               ""
    common,strategy                                      ""
    common,timing_mode                                   ""
}

# --- COMPILE (3 vars) ---
array set synth {
    compile,dynamic_power_effort                         ""
    compile,effort                                       ""
    compile,leakage_power_effort                         ""
}

# --- CONSTRAINTS (2 vars) ---
array set synth {
    constraints,max_fanout                               ""
    constraints,max_transition                           ""
}

# --- EFFORT (3 vars) ---
array set synth {
    effort,area                                          ""
    effort,mapping                                       ""
    effort,timing                                        ""
}

# --- OPTIMIZATION (3 vars) ---
array set synth {
    optimization,boundary                                ""
    optimization,hold_fix                                ""
    optimization,multi_vt                                ""
}

# --- OUTPUT (5 vars) ---
array set synth {
    output,save_constraints                              ""
    output,save_ddc                                      ""
    output,save_sdf                                      ""
    output,save_svf                                      ""
    output,save_verilog                                  ""
}

# --- POWER (1 vars) ---
array set synth {
    power,effort                                         ""
}
