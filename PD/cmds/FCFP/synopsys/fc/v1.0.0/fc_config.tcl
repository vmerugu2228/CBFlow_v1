#!/usr/bin/env tclsh
# =============================================================================
# FC Tool Configuration - FCFP Flow
# =============================================================================
# Convention: fc(common,var) shared, fc(<node>,var) node-specific
# Override: set fc(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set fc {
    analysis,max_paths                                   ""
}

# --- COMMON (24 vars) ---
array set fc {
    common,DESIGN_LIB                                    ""
    common,PARTITION_NETLISTS                            ""
    common,SCENARIO_SETUP                                ""
    common,SDC_FILES                                     ""
    common,TOP_MODULE                                    ""
    common,TOP_NETLIST                                   ""
    common,UPF_FILE                                      ""
    common,check_design                                  ""
    common,chip_type                                     ""
    common,commit_block_list                             ""
    common,connect_pg_net_script                         ""
    common,design_lib_name                               ""
    common,design_name                                   ""
    common,fix_port_placement                            ""
    common,input_netlist                                 ""
    common,input_sdc                                     ""
    common,input_upf_supplemental                        ""
    common,open_lib                                      ""
    common,power_domain_map_script                       ""
    common,release_phase                                 ""
    common,split_constraints_script                      ""
    common,sub_blocks                                    ""
    common,svf_file                                      ""
    common,technology_node                               ""
}

# --- COMPILE (4 vars) ---
array set fc {
    compile,active_scenarios                             ""
    compile,early_stage                                  ""
    compile,qor_metric                                   ""
    compile,reduced_effort                               ""
}

# --- COPY_BLOCK (1 vars) ---
array set fc {
    copy_block,from                                      ""
}

# --- CREATE_ABSTRACT (1 vars) ---
array set fc {
    create_abstract,enable                               ""
}

# --- CREATE_FLOORPLAN (1 vars) ---
array set fc {
    create_floorplan,from_label                          ""
}

# --- CREATE_POWER (1 vars) ---
array set fc {
    create_power,from_label                              ""
}

# --- EXPORT_DATA (1 vars) ---
array set fc {
    export_data,from_label                               ""
}

# --- FLOORPLAN (13 vars) ---
array set fc {
    floorplan,boundary_cell_script                       ""
    floorplan,congestion_driven                          ""
    floorplan,core_area                                  ""
    floorplan,core_aspect_ratio                          ""
    floorplan,core_offset                                ""
    floorplan,core_utilization                           ""
    floorplan,die_area                                   ""
    floorplan,macro_constraints                          ""
    floorplan,physical_constraints                       ""
    floorplan,place_pins                                 ""
    floorplan,tap_cell_script                            ""
    floorplan,timing_driven                              ""
    floorplan,track_file                                 ""
}

# --- INIT_COMPILE (1 vars) ---
array set fc {
    init_compile,from_label                              ""
}

# --- OUTPUT (1 vars) ---
array set fc {
    output,block_labeling                                ""
}

# --- PLACE_PINS (1 vars) ---
array set fc {
    place_pins,from_label                                ""
}

# --- PLACEMENT (8 vars) ---
array set fc {
    placement,abstract_timing                            ""
    placement,congestion_effort                          ""
    placement,constraint_script                          ""
    placement,effort                                     ""
    placement,from_label                                 ""
    placement,push_down_blockages                        ""
    placement,push_down_pg                               ""
    placement,push_down_site_rows                        ""
}

# --- POWER (17 vars) ---
array set fc {
    power,mesh_config                                    ""
    power,mesh_h_layer                                   ""
    power,mesh_pitch                                     ""
    power,mesh_v_layer                                   ""
    power,mesh_width                                     ""
    power,place_stdcells                                 ""
    power,pns_script                                     ""
    power,ring_config                                    ""
    power,ring_layers                                    ""
    power,ring_offset                                    ""
    power,ring_spacing                                   ""
    power,ring_width                                     ""
    power,special_pg_nets                                ""
    power,std_cell_rail_layer                            ""
    power,strap_config                                   ""
    power,vdd_net                                        ""
    power,vss_net                                        ""
}

# --- SHAPING (6 vars) ---
array set fc {
    shaping,constraint_script                            ""
    shaping,from_label                                   ""
    shaping,min_height                                   ""
    shaping,min_width                                    ""
    shaping,style                                        ""
    shaping,target_utilization                           ""
}

# --- TIMING_BUDGET (4 vars) ---
array set fc {
    timing_budget,active_scenarios                       ""
    timing_budget,constraint_script                      ""
    timing_budget,from_label                             ""
    timing_budget,mode                                   ""
}

# --- TOP_COMPILE (5 vars) ---
array set fc {
    top_compile,active_scenarios                         ""
    top_compile,from_label                               ""
    top_compile,from_stage                               ""
    top_compile,qor_metric                               ""
    top_compile,to_stage                                 ""
}

