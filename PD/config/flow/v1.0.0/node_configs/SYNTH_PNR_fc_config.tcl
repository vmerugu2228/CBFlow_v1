#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH_PNR — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from SYNTH_PNR_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ──────────────────────────────────────────────────────────┐
array set synth_pnr {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ FC Place/CTS/Route/Analysis Settings ──────────────────────────────────────┐
array set synth_pnr {
    place,effort               "high"
    place,congestion_aware     true
    place,timing_driven        true
    place,max_density          0.85
    place,high_utilization_flow false

    cts,target_skew            "50"
    cts,max_transition         "100"
    cts,buffer_cells           ""
    cts,inverter_cells         ""

    route,min_layer            "M2"
    route,max_layer            "M8"
    route,antenna_fix          true
    route,metal_fill           true
    route,si_aware             true

    analysis,max_paths         100
    analysis,significant_digits 4
}

# ┌─ FC-RM Compile/Synthesis Control ──────────────────────────────────────────┐
array set synth_pnr {
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

# ┌─ FC-RM CTS Control ────────────────────────────────────────────────────────┐
array set synth_pnr {
    cts,style                     "standard"
    cts_primary_corner            ""
    clock_opt_cts,redundant_via   false
    clock_opt_cts,enable_aocv     true
}

# ┌─ FC-RM Route Control ──────────────────────────────────────────────────────┐
array set synth_pnr {
    route_auto,enable_redundant_via  true
    route_auto,enable_shields        false
}

# ┌─ FC-RM Route Optimization Control ─────────────────────────────────────────┐
array set synth_pnr {
    route_opt,enable_hyper          false
    route_opt,extraction_mode       "fusion_adv"
    route_opt,pba_mode              "path"
    route_opt,redundant_via         true
    route_opt,incr_route_detail_mode "auto"
    route_opt,enable_irdccd         false
}

# ┌─ FC-RM Endpoint Optimization ──────────────────────────────────────────────┐
array set synth_pnr {
    route_opt,enable_endpoint_opt   false
    endpoint_opt,auto_metric        "timing"
    endpoint_opt,max_paths          10000
    endpoint_opt,slack_threshold    -0.001
    endpoint_opt,target_scenarios   ""
    endpoint_opt,path_group_filter  ""
    endpoint_opt,loop_count         1
}

# ┌─ FC-RM Signoff/Chip Finish ────────────────────────────────────────────────┐
array set synth_pnr {
    signoff,insert_filler     true
    signoff,insert_decap      true
    signoff,drc_check             true
    signoff,fix_drc               true
    signoff,metal_fill            true
    signoff,metal_fill_track_based "off"
}

# ┌─ FC Required Inputs (nlib handoff between stages) ─────────────────────────┐
set synth_pnr(required_inputs,init_design1)  "work/SYNTH_PNR/rtl1/rtl work/SYNTH_PNR/sdc1/sdc work/SYNTH_PNR/upf1/upf"
set synth_pnr(required_inputs,synthesis1)    "work/SYNTH_PNR/init_design1/run/init_design1.nlib"
set synth_pnr(required_inputs,place1)        "work/SYNTH_PNR/synthesis1/run/synthesis1.nlib"
set synth_pnr(required_inputs,cts1)          "work/SYNTH_PNR/place1/run/place1.nlib"
set synth_pnr(required_inputs,cts_opt1)      "work/SYNTH_PNR/cts1/run/cts1.nlib"
set synth_pnr(required_inputs,route1)        "work/SYNTH_PNR/cts_opt1/run/cts_opt1.nlib"
set synth_pnr(required_inputs,pro1)          "work/SYNTH_PNR/route1/run/route1.nlib"
set synth_pnr(required_inputs,signoff1)      "work/SYNTH_PNR/pro1/run/pro1.nlib"
set synth_pnr(required_inputs,export_data1)  "work/SYNTH_PNR/signoff1/run/signoff1.nlib"

# ── FC-RM App Variables (user overrides via user_config) ──

# --- COMMON - Shared across multiple nodes (52 vars) ---
array set synth_pnr {
    common,additional_floorplan_file                     ""
    common,analysis,max_paths                            ""
    common,aocv_setup_file                               ""
    common,block_abstract_for_compile                    ""
    common,block_abstract_for_cts                        ""
    common,block_abstract_for_cts_opt                    ""
    common,block_abstract_for_place_opt                  ""
    common,block_abstract_for_route                      ""
    common,block_abstract_for_signoff                    ""
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

# --- INIT_DESIGN - Library creation, floorplan (2 vars) ---
array set synth_pnr {
    init_design,design_lib_scale_factor                  ""
    init_design,fp_tap_cell_distance                     ""
}

# --- FLOORPLAN - Floorplan parameters (3 vars) ---
array set synth_pnr {
    fp,aspect_ratio                                      ""
    fp,core_offset                                       ""
    fp,core_utilization                                  ""
}

# --- SYNTHESIS - Logic synthesis (11 vars) ---
array set synth_pnr {
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
array set synth_pnr {
    place,opt_active_scenarios                           ""
    place,place_opt,high_utilization_flow                ""
    place,place_opt_incremental_post_script              ""
    place,place_opt_post_script                          ""
    place,place_opt_pre_script                           ""
    place,placement_constraint_files                     ""
}

# --- CTS - Clock tree synthesis (11 vars) ---
array set synth_pnr {
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
array set synth_pnr {
    cts_opt,active_scenarios                             ""
    cts_opt,cts_opt_post_script                          ""
    cts_opt,cts_opt_pre_script                           ""
    cts_opt,cts_opt_sidefile                             ""
}

# --- ROUTE - Detailed routing (4 vars) ---
array set synth_pnr {
    route,route_auto,enable_redundant_via                ""
    route,route_post_script                              ""
    route,route_pre_script                               ""
    route,route_sidefile                                 ""
}

# --- PRO - Post-route optimization (21 vars) ---
array set synth_pnr {
    pro,block_abstract                                   ""
    pro,signoff_post_script                              ""
    pro,signoff_pre_script                               ""
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
array set synth_pnr {
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
array set synth_pnr {
    export_data,block_labeling                           ""
    export_data,def_convert_sites                        ""
    export_data,name_rules                               ""
    export_data,post_script                              ""
    export_data,pre_script                               ""
    export_data,write_gds                                ""
    export_data,write_oasis                              ""
}

# --- RELEASE_DATA - Release packaging (1 vars) ---
array set synth_pnr {
    release_data,release_phase                           ""
}
