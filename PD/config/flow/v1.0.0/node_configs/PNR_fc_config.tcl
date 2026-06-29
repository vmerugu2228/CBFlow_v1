#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PNR — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from PNR_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ──────────────────────────────────────────────────────────┐
array set pnr {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ PNR App Settings (moved from common PNR_config.tcl) ──────────────────────┐
array set pnr {
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

# ┌─ FC-RM Compile Control (values aligned with FC-RM Y-2026.03) ──────────────┐
array set pnr {
    compile,unified_flow          true
    compile,qor_metric            "timing"
    compile,qor_mode              "balanced"
    compile,qor_version           ""
    compile,congestion_effort     "medium"
    compile,high_effort_timing    true
    compile,reduced_effort        false
    compile,enable_spg            false
    compile,enable_irdp           false
}

# ┌─ FC-RM CTS Control ────────────────────────────────────────────────────────┐
array set pnr {
    cts,style                     "standard"
    cts_primary_corner            ""
    clock_opt_cts,redundant_via   false
    clock_opt_cts,enable_aocv     true
}

# ┌─ Multi-Source CTS / Multipoint CTS (FC-RM MSCTS) ──────────────────────────┐
# Knob to enable: `set pnr(cts,mpcts) "true"` in user_config. Default off.
# Per-block specs (clock, root, lib cells, layers) live alongside as
# pnr(cts,mpcts,<key>). The cts1 stage's `construct_mscts` flow_proc reads
# these, stages them into FC-RM-canonical MSCTS_* globals, and sources
# mscts_fc.tcl. See PD/docs/03-reference/mscts-mpcts-reference.md for the
# full input list and sample user_config block.
array set pnr {
    cts,mpcts                              "false"
    cts,mpcts,clock                        ""
    cts,mpcts,source                       ""
    cts,mpcts,topology                     "htree"
    cts,mpcts,pitch                        "100"
    cts,mpcts,tap_driver_lib_cells         ""
    cts,mpcts,net                          ""
    cts,mpcts,tap_driver_max_displacement  ""
    cts,mpcts,tap_boundary                 ""
    cts,mpcts,macro_keepout                "false"
    cts,mpcts,htree_lib_cells              ""
    cts,mpcts,htree_ndr_rule_name          ""
    cts,mpcts,htree_min_routing_layer      ""
    cts,mpcts,htree_max_routing_layer      ""
    cts,mpcts,mesh_net                     ""
    cts,mpcts,mesh_net_port                ""
    cts,mpcts,mesh_net_port_transition     ""
    cts,mpcts,mesh_net_port_delay          ""
    cts,mpcts,input_transition             ""
    cts,mpcts,net_delay                    ""
    cts,mpcts,user_mesh_annotation_script  ""
}

# ┌─ FC-RM Route Optimization Control ─────────────────────────────────────────┐
array set pnr {
    route_opt,enable_hyper          false
    route_opt,extraction_mode       "fusion_adv"
    route_opt,pba_mode              "path"
    route_opt,redundant_via         true
    route_opt,incr_route_detail_mode "auto"
    route_opt,enable_irdccd         false
}

# ┌─ FC-RM Endpoint Optimization ──────────────────────────────────────────────┐
array set pnr {
    route_opt,enable_endpoint_opt   false
    endpoint_opt,auto_metric        "timing"
    endpoint_opt,max_paths          10000
    endpoint_opt,slack_threshold    -0.001
    endpoint_opt,target_scenarios   ""
    endpoint_opt,path_group_filter  ""
    endpoint_opt,loop_count         1
}

# ┌─ FC-RM Signoff/Chip Finish ────────────────────────────────────────────────┐
array set pnr {
    signoff,insert_filler          true
    signoff,insert_decap           true
    signoff,drc_check              true
    signoff,fix_drc                true
    signoff,metal_fill             true
    signoff,metal_fill_track_based "off"
}

# ┌─ FC Required Inputs (nlib handoff between stages) ─────────────────────────┐
set pnr(required_inputs,init_design1)  "work/PNR/netlist1/netlist work/PNR/sdc1/sdc work/PNR/def1/def work/PNR/upf1/upf"
set pnr(required_inputs,place1)        "work/PNR/init_design1/outputs/init_design.nlib"
set pnr(required_inputs,cts1)          "work/PNR/place1/outputs/place.nlib"
set pnr(required_inputs,cts_opt1)      "work/PNR/cts1/outputs/cts.nlib"
set pnr(required_inputs,route1)        "work/PNR/cts_opt1/outputs/cts_opt.nlib"
set pnr(required_inputs,pro1)          "work/PNR/route1/outputs/route.nlib"
set pnr(required_inputs,signoff1)      "work/PNR/pro1/outputs/pro.nlib"
set pnr(required_inputs,export_data1)  "work/PNR/signoff1/outputs/signoff.nlib"

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set pnr {
    analysis,max_paths                                   ""
}

# --- COMMON (35 vars) ---
array set pnr {
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
array set pnr {
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
array set pnr {
    cts,active_scenarios                                 ""
    cts,exclude_cells                                    ""
    cts,ndr_rule                                         ""
    cts,primary_corner                                   ""
    cts,ref_cells                                        ""
}

# --- CTS_OPT (1 vars) ---
array set pnr {
    cts_opt,active_scenarios                             ""
}

# --- FP (4 vars) ---
array set pnr {
    fp,aspect_ratio                                      ""
    fp,core_offset                                       ""
    fp,core_utilization                                  ""
    fp,tap_cell_distance                                 ""
}

# --- INIT_DESIGN (1 vars) ---
array set pnr {
    init_design,active_scenarios                         ""
}

# --- OUTPUT (6 vars) ---
array set pnr {
    output,block_labeling                                ""
    output,def_convert_sites                             ""
    output,name_rules_options                            ""
    output,write_gds                                     ""
    output,write_oasis                                   ""
    output,write_upf                                     ""
}

# --- PLACE (1 vars) ---
array set pnr {
    place,high_utilization_flow                          ""
}

# --- PRO (15 vars) ---
array set pnr {
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
array set pnr {
    route,active_scenarios                               ""
    route,enable_shields                                 ""
    route,focused_scenario                               ""
    route,redundant_via                                  ""
    route,shields_ground_net                             ""
    route,shields_options                                ""
}

# --- SIGNOFF (10 vars) ---
array set pnr {
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

# ──────────────────────────────────────────────────────────────────────────────
# REDHAWK-SC RAIL ANALYSIS (Synopsys ↔ Ansys RedHawk-SC integration)
# ──────────────────────────────────────────────────────────────────────────────
# Master knob to enable: `set pnr(common,redhawk_enable) "true"` in user_config
# (or per-stage: `pnr(cts_opt,redhawk_enable)` / `pnr(pro,redhawk_enable)`
# / `pnr(signoff,redhawk_enable)`). Default OFF — existing runs unchanged.
#
# When enabled, the `redhawk_rail_analysis` flow_proc in cts_opt / pro / signoff
# sources cmds/PNR/synopsys/fc/<ver>/redhawk_fc.tcl. Required inputs marked (*).
# See PD/docs/03-reference/redhawk-integration.md for full description.
# ──────────────────────────────────────────────────────────────────────────────
array set pnr {
    common,redhawk_enable                                "false"
    cts_opt,redhawk_enable                               "false"
    pro,redhawk_enable                                   "false"
    signoff,redhawk_enable                               "false"

    common,redhawk,gad_file                              ""
    common,redhawk,tech_file                             ""
    common,redhawk,power_net                             ""
    common,redhawk,ground_net                            ""
    common,redhawk,scenario                              ""
    common,redhawk,ir_threshold                          "0.05"
    common,redhawk,switching_activity                    ""
    common,redhawk,static_ir                             "true"
    common,redhawk,dynamic_ir                            "true"
    common,redhawk,em_analysis                           "false"
    common,redhawk,fix_violators                         "true"
    common,redhawk,num_cpus                              "8"
}

# ──────────────────────────────────────────────────────────────────────────────
# LOW-POWER INSERTION (UPF-driven: power switches, isolation, level shifters)
# ──────────────────────────────────────────────────────────────────────────────
# Master knob to enable: `set pnr(common,lowpower_enable) "true"` in
# user_config (or per-stage: `pnr(place,lowpower_enable)`).
# Default OFF — existing runs unchanged.
#
# Prerequisite: the UPF file MUST already be loaded by init_design's
# load_constraints step. This flow_proc enables FC's UPF implementation
# engine and runs check_mv_design + reports — it does NOT re-load UPF.
#
# When enabled, the `insert_low_power_cells` flow_proc in place_fc.tcl
# sources cmds/PNR/synopsys/fc/<ver>/lowpower_fc.tcl. See
# PD/docs/03-reference/lowpower-integration.md for full description.
# ──────────────────────────────────────────────────────────────────────────────
array set pnr {
    common,lowpower_enable                               "false"
    place,lowpower_enable                                "false"

    common,lowpower,power_switches                       "true"
    common,lowpower,isolation_cells                      "true"
    common,lowpower,level_shifters                       "true"
    common,lowpower,always_on_buffers                    "true"
    common,lowpower,power_switch_lib_cells               ""
}
