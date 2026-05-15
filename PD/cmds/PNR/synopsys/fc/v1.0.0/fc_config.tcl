#!/usr/bin/env tclsh
# =============================================================================
# FC Tool Configuration - PNR Flow
# =============================================================================
# Convention: fc(common,var) shared, fc(<node>,var) node-specific
# Override: set fc(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set fc {
    analysis,max_paths                                   ""
}

# --- COMMON (35 vars) ---
array set fc {
    common,additional_floorplan_file                     ""
    common,aocv_setup_file                               ""
    common,chip_type                                     ""
    common,connect_pg_net_script                         ""
    common,constraints_setup_file                        ""
    common,cts_ndr_file                                  ""
    common,design_lib_name                               ""
    common,design_lib_scale_factor                       ""
    common,design_name                                   ""
    common,dft_ports_file                                ""
    common,early_data_check_policy                       ""
    common,floorplan_rule_script                         ""
    common,fp_tcl                                        ""
    common,input_def                                     ""
    common,input_netlist                                 ""
    common,input_sdc                                     ""
    common,input_upf                                     ""
    common,input_upf_supplemental                        ""
    common,lib_cell_purpose_file                         ""
    common,mcmm_setup_file                               ""
    common,ndm_libs                                      ""
    common,placement_constraint_files                    ""
    common,pocv_setup_file                               ""
    common,release_phase                                 ""
    common,route_max_layer                               ""
    common,route_min_layer                               ""
    common,saif_file                                     ""
    common,saif_power_scenario                           ""
    common,saif_source_instance                          ""
    common,saif_target_instance                          ""
    common,spare_cells_file                              ""
    common,sub_block_libs                                ""
    common,switch_connectivity_file                      ""
    common,technology_node                               ""
    common,upf_mode                                      ""
}

# --- COMPILE (9 vars) ---
array set fc {
    compile,active_scenarios                             ""
    compile,congestion_effort                            ""
    compile,enable_spg                                   ""
    compile,high_effort_timing                           ""
    compile,qor_metric                                   ""
    compile,qor_mode                                     ""
    compile,qor_version                                  ""
    compile,reduced_effort                               ""
    compile,unified_flow                                 ""
}

# --- CTS (5 vars) ---
array set fc {
    cts,active_scenarios                                 ""
    cts,exclude_cells                                    ""
    cts,ndr_rule                                         ""
    cts,primary_corner                                   ""
    cts,ref_cells                                        ""
}

# --- CTS_OPT (1 vars) ---
array set fc {
    cts_opt,active_scenarios                             ""
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

# --- OUTPUT (6 vars) ---
array set fc {
    output,block_labeling                                ""
    output,def_convert_sites                             ""
    output,name_rules_options                            ""
    output,write_gds                                     ""
    output,write_oasis                                   ""
    output,write_upf                                     ""
}

# --- PLACE (1 vars) ---
array set fc {
    place,high_utilization_flow                          ""
}

# --- PRO (15 vars) ---
array set fc {
    pro,active_scenarios                                 ""
    pro,enable_endpoint_opt                              ""
    pro,endpoint_opt_auto                                ""
    pro,endpoint_opt_loop                                ""
    pro,endpoint_opt_max_paths                           ""
    pro,endpoint_opt_path_group_filter                   ""
    pro,endpoint_opt_scenarios                           ""
    pro,endpoint_opt_slack_threshold                     ""
    pro,extraction_mode                                  ""
    pro,pba_mode                                         ""
    pro,redundant_via                                    ""
    pro,redundant_via_post                               ""
    pro,starrc_config                                    ""
    pro,starrc_options                                   ""
    pro,vmf_parameter_file                               ""
}

# --- ROUTE (6 vars) ---
array set fc {
    route,active_scenarios                               ""
    route,enable_shields                                 ""
    route,focused_scenario                               ""
    route,redundant_via                                  ""
    route,shields_ground_net                             ""
    route,shields_options                                ""
}

# --- SIGNOFF (10 vars) ---
array set fc {
    signoff,drc_runset                                   ""
    signoff,drc_select_rules                             ""
    signoff,fix_drc                                      ""
    signoff,insert_decap                                 ""
    signoff,insert_filler                                ""
    signoff,metal_fill                                   ""
    signoff,metal_fill_runset                            ""
    signoff,metal_fill_timing_threshold                  ""
    signoff,metal_fill_track_based                       ""
    signoff,stream_files_for_merge                       ""
}

