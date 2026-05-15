#!/usr/bin/env tclsh
# =============================================================================
# FC Tool Configuration - SYNTH Flow
# =============================================================================
# Convention: fc(common,var) shared, fc(<node>,var) node-specific
# Override: set fc(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (2 vars) ---
array set fc {
    analysis,max_paths                                   ""
    analysis,significant_digits                          ""
}

# --- COMMON (28 vars) ---
array set fc {
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
array set fc {
    compile,enable_spg                                   ""
    compile,high_effort_timing                           ""
    compile,qor_metric                                   ""
    compile,qor_mode                                     ""
}

# --- DESIGN (1 vars) ---
array set fc {
    design,top_module                                    ""
}

# --- FP (4 vars) ---
array set fc {
    fp,aspect_ratio                                      ""
    fp,core_offset                                       ""
    fp,core_utilization                                  ""
    fp,tap_cell_distance                                 ""
}

# --- INIT_DESIGN (1 vars) ---
array set fc {
    init_design,active_scenarios                         ""
}

# --- OUTPUT (1 vars) ---
array set fc {
    output,block_labeling                                ""
}

# --- ROUTE (2 vars) ---
array set fc {
    route,max_layer                                      ""
    route,min_layer                                      ""
}

# --- SYNTHESIS (5 vars) ---
array set fc {
    synthesis,boundary_opt                               ""
    synthesis,clock_gating                               ""
    synthesis,max_fanout                                 ""
    synthesis,max_transition                             ""
    synthesis,timing_driven                              ""
}

