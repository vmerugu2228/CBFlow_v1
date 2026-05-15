#!/usr/bin/env tclsh
# =============================================================================
# Fusion Compiler Tool Configuration - SYNTH_PNR Flow
# =============================================================================
#
# All FC tool-specific variables in the fc() array.
# Convention:
#   fc(common,var)  - Used by multiple nodes
#   fc(<node>,var)  - Used by a specific node only
#
# Users override in user_config.tcl or override_config.tcl:
#   set fc(place,effort) "medium"
# =============================================================================

# --- COMMON - Shared across multiple nodes (54 vars) ---
array set fc {
    common,additional_floorplan_file                     ""
    common,analysis,max_paths                            ""
    common,aocv_setup_file                               ""
    common,block_abstract_for_compile                    ""
    common,block_abstract_for_cts                        ""
    common,block_abstract_for_cts_opt                    ""
    common,block_abstract_for_place_opt                  ""
    common,block_abstract_for_route                      ""
    common,block_abstract_for_signoff                    ""
    common,chip_type                                     ""
    common,compile,congestion_effort                     ""
    common,compile,qor_metric                            ""
    common,compile,qor_mode                              ""
    common,compile,qor_version                           ""
    common,compile,reduced_effort                        ""
    common,connect_pg_net_script                         ""
    common,constraints_setup_file                        ""
    common,cts_primary_corner                            ""
    common,define_name_rules_options                     ""
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,enable_fusa                                   ""
    common,floorplan_rule_script                         ""
    common,irdccd_config_file                            ""
    common,irdp_config_file                              ""
    common,lib_cell_purpose_file                         ""
    common,mcmm_adjustment_file                          ""
    common,mcmm_setup_file                               ""
    common,multi_vt_constraint_file                      ""
    common,non_persistent_script                         ""
    common,optimization_freeze_port_list                 ""
    common,output,block_labeling                         ""
    common,physical_hierarchy_level                      ""
    common,pocv_setup_file                               ""
    common,promote_abstract_clock_data_file              ""
    common,promote_clock_balance_points                  ""
    common,route,focused_scenario                        ""
    common,route_auto,active_scenarios                   ""
    common,route_max_layer                               ""
    common,route_min_layer                               ""
    common,route_opt,enable_advanced_vmf                 ""
    common,route_opt,starrc_config                       ""
    common,route_opt,starrc_options                      ""
    common,route_opt,vmf_parameter_file                  ""
    common,saif_file                                     ""
    common,saif_power_scenario                           ""
    common,saif_source_instance                          ""
    common,saif_target_instance                          ""
    common,spare_cell_post_script                        ""
    common,spare_cell_pre_script                         ""
    common,spare_cells_file                              ""
    common,switch_connectivity_file                      ""
    common,tech_node                                     ""
    common,upf_mode                                      ""
}

# --- INIT_DESIGN - Library creation, floorplan (3 vars) ---
array set fc {
    init_design,active_scenarios                         ""
    init_design,design_lib_scale_factor                  ""
    init_design,fp_tap_cell_distance                     ""
}

# --- FLOORPLAN - Floorplan parameters (3 vars) ---
array set fc {
    fp,aspect_ratio                                      ""
    fp,core_offset                                       ""
    fp,core_utilization                                  ""
}

# --- SYNTHESIS - Logic synthesis (11 vars) ---
array set fc {
    synthesis,compile,active_scenarios                   ""
    synthesis,compile,enable_irdp                        ""
    synthesis,compile,enable_spg                         ""
    synthesis,compile,high_effort_timing                 ""
    synthesis,compile,unified_flow                       ""
    synthesis,compile_post_script                        ""
    synthesis,compile_pre_script                         ""
    synthesis,dft_insert_enable                          ""
    synthesis,dft_ports_file                             ""
    synthesis,dft_pre_compile_setup_file                 ""
    synthesis,dft_setup_file                             ""
}

# --- PLACE - Placement optimization (6 vars) ---
array set fc {
    place,opt_active_scenarios                           ""
    place,place_opt,high_utilization_flow                ""
    place,place_opt_incremental_post_script              ""
    place,place_opt_post_script                          ""
    place,place_opt_pre_script                           ""
    place,placement_constraint_files                     ""
}

# --- CTS - Clock tree synthesis (11 vars) ---
array set fc {
    cts,clock_opt_cts,active_scenarios                   ""
    cts,clock_opt_cts,enable_aocv                        ""
    cts,cts,enable_shields                               ""
    cts,cts,shields_ground_net                           ""
    cts,cts,shields_options                              ""
    cts,cts_ndr_file                                     ""
    cts,cts_post_script                                  ""
    cts,cts_pre_script                                   ""
    cts,cts_sidefile                                     ""
    cts,mscts_mesh_routing_script                        ""
    cts,redundant_via                                    ""
}

# --- CTS_OPT - Post-CTS optimization (4 vars) ---
array set fc {
    cts_opt,active_scenarios                             ""
    cts_opt,cts_opt_post_script                          ""
    cts_opt,cts_opt_pre_script                           ""
    cts_opt,cts_opt_sidefile                             ""
}

# --- ROUTE - Detailed routing (4 vars) ---
array set fc {
    route,route_auto,enable_redundant_via                ""
    route,route_post_script                              ""
    route,route_pre_script                               ""
    route,route_sidefile                                 ""
}

# --- PRO - Post-route optimization (21 vars) ---
array set fc {
    pro,block_abstract                                   ""
    pro,chip_finish_post_script                          ""
    pro,chip_finish_pre_script                           ""
    pro,ctl_for_abstract_blocks                          ""
    pro,endpoint_opt,auto_metric                         ""
    pro,endpoint_opt,loop_count                          ""
    pro,endpoint_opt,max_paths                           ""
    pro,endpoint_opt,path_group_filter                   ""
    pro,endpoint_opt,slack_threshold                     ""
    pro,endpoint_opt,target_scenarios                    ""
    pro,opt_active_scenarios                             ""
    pro,route_opt,enable_endpoint_opt                    ""
    pro,route_opt,enable_hyper                           ""
    pro,route_opt,enable_irdccd                          ""
    pro,route_opt,extraction_mode                        ""
    pro,route_opt,pba_mode                               ""
    pro,route_opt,post_redundant_via                     ""
    pro,route_opt,redundant_via                          ""
    pro,route_opt_post_script                            ""
    pro,route_opt_pre_script                             ""
    pro,route_opt_sidefile                               ""
}

# --- SIGNOFF - Timing/power signoff (14 vars) ---
array set fc {
    signoff,active_scenarios                             ""
    signoff,drc_runset                                   ""
    signoff,drc_select_rules                             ""
    signoff,em_fixing                                    ""
    signoff,em_saif                                      ""
    signoff,em_scenario                                  ""
    signoff,fix_drc                                      ""
    signoff,insert_decap                                 ""
    signoff,insert_diodes                                ""
    signoff,insert_filler                                ""
    signoff,metal_fill                                   ""
    signoff,metal_fill_parameter_file                    ""
    signoff,metal_fill_timing_threshold                  ""
    signoff,metal_fill_track_based                       ""
}

# --- EXPORT_DATA - Output data (GDS, DEF, netlist) (7 vars) ---
array set fc {
    export_data,block_labeling                           ""
    export_data,def_convert_sites                        ""
    export_data,name_rules                               ""
    export_data,post_script                              ""
    export_data,pre_script                               ""
    export_data,write_gds                                ""
    export_data,write_oasis                              ""
}

# --- RELEASE_DATA - Release packaging (1 vars) ---
array set fc {
    release_data,release_phase                           ""
}

