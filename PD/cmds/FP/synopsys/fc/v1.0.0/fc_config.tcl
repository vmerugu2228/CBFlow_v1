#!/usr/bin/env tclsh
# =============================================================================
# FC Tool Configuration - FP Flow
# =============================================================================
# Convention: fc(common,var) shared, fc(<node>,var) node-specific
# Override: set fc(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set fc {
    analysis,max_paths                                   ""
}

# --- COMMON (33 vars) ---
array set fc {
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
array set fc {
    compile,qor_metric                                   ""
}

# --- COMPILE_DP (2 vars) ---
array set fc {
    compile_dp,app_options                               ""
    compile_dp,options                                   ""
}

# --- OUTPUT (1 vars) ---
array set fc {
    output,block_labeling                                ""
}

# --- PLACE_PINS (3 vars) ---
array set fc {
    place_pins,constraint_file                           ""
    place_pins,fix_ports                                 ""
    place_pins,legalize                                  ""
}

