#!/usr/bin/env tclsh
# =============================================================================
# GENUS Tool Configuration - SYNTH Flow
# =============================================================================
# Convention: genus(common,var) shared, genus(<node>,var) node-specific
# Override: set genus(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set genus {
    analysis,max_paths                                   ""
}

# --- AREA (1 vars) ---
array set genus {
    area,recover_design_area                             ""
}

# --- COMMON (12 vars) ---
array set genus {
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
array set genus {
    compile,dynamic_power_effort                         ""
    compile,effort                                       ""
    compile,leakage_power_effort                         ""
}

# --- CONSTRAINTS (2 vars) ---
array set genus {
    constraints,max_fanout                               ""
    constraints,max_transition                           ""
}

# --- EFFORT (3 vars) ---
array set genus {
    effort,area                                          ""
    effort,mapping                                       ""
    effort,timing                                        ""
}

# --- OPTIMIZATION (3 vars) ---
array set genus {
    optimization,boundary                                ""
    optimization,hold_fix                                ""
    optimization,multi_vt                                ""
}

# --- OUTPUT (5 vars) ---
array set genus {
    output,save_constraints                              ""
    output,save_ddc                                      ""
    output,save_sdf                                      ""
    output,save_svf                                      ""
    output,save_verilog                                  ""
}

# --- POWER (1 vars) ---
array set genus {
    power,effort                                         ""
}

