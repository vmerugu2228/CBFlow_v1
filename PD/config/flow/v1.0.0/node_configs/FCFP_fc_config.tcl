#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FCFP — Synopsys Fusion Compiler (FC) Tool Configuration
# Sourced from FCFP_config.tcl when tool=fc
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ FC Tool Settings ──────────────────────────────────────────────────────────┐
array set fcfp {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ FCFP App Settings (moved from common FCFP_config.tcl) ────────────────────┐
array set fcfp {
    design_style            "hier"
    physical_hierarchy_level "top"

    floorplan,die_width         ""
    floorplan,die_height        ""
    floorplan,core_utilization  0.65
    floorplan,core_aspect_ratio 1.0
    floorplan,macro_placement   true
    floorplan,macro_spacing     "5.0"
    floorplan,boundary_cells    true
    floorplan,tap_cells         true
    floorplan,place_pins        true

    power,net_names             "VDD VSS"
    power,ring_width            "3.0"
    power,ring_spacing          "1.0"
    power,strap_width           "1.0"
    power,strap_pitch           "20.0"
    power,mesh_layers           "M8 M9 M10"

    place_pins,legalize         true
    place_pins,constraint_file  ""
    place_pins,fix_ports        true
}

# ┌─ FC-RM Init DP Control ────────────────────────────────────────────────────┐
array set fcfp {
    output,block_labeling   true
}

# ┌─ FC-RM Commit Blocks Control ──────────────────────────────────────────────┐
array set fcfp {
    sub_block_refs          {}
    sub_block_libraries     {}
}

# ┌─ FC-RM Init Compile Control ───────────────────────────────────────────────┐
array set fcfp {
    compile,qor_metric      "timing"
    compile,qor_mode        "balanced"
    compile,reduced_effort  true
    compile,stage           "logic_opto"
}

# ┌─ FC-RM Shaping Control ────────────────────────────────────────────────────┐
array set fcfp {
    shaping,style               "channel"
    shaping,min_channel_width   ""
    shaping,target_utilization  ""
}

# ┌─ FC-RM Placement Control ──────────────────────────────────────────────────┐
array set fcfp {
    placement,congestion_driven true
    placement,timing_driven     true
    placement,push_down_rows    true
}

# ┌─ FC-RM Create Power Control ───────────────────────────────────────────────┐
array set fcfp {
    powerplan,pns_file          ""
    powerplan,stdcell_placement true
}

# ┌─ FC-RM Top Compile Control ────────────────────────────────────────────────┐
array set fcfp {
    top_compile,from_stage      "logic_opto"
    top_compile,to_stage        "logic_opto"
}

# ┌─ FC-RM Timing Budget Control ──────────────────────────────────────────────┐
array set fcfp {
    timing_budget,estimate_timing  true
    timing_budget,distribute       true
}

# ┌─ FC Required Inputs (nlib handoff between stages) ─────────────────────────┐
set fcfp(required_inputs,init_design1)      "work/FCFP/netlist1/netlist work/FCFP/sdc1/sdc work/FCFP/def1/def work/FCFP/upf1/upf work/FCFP/library1/library"
set fcfp(required_inputs,commit_blocks1)    "work/FCFP/init_design1/run/init_design1.nlib"
set fcfp(required_inputs,init_compile1)     "work/FCFP/commit_blocks1/run/commit_blocks1.nlib"
set fcfp(required_inputs,create_floorplan1) "work/FCFP/init_compile1/run/init_compile1.nlib"
set fcfp(required_inputs,shaping1)          "work/FCFP/create_floorplan1/run/create_floorplan1.nlib"
set fcfp(required_inputs,placement1)        "work/FCFP/shaping1/run/shaping1.nlib"
set fcfp(required_inputs,create_power1)     "work/FCFP/placement1/run/placement1.nlib"
set fcfp(required_inputs,place_pins1)       "work/FCFP/create_power1/run/create_power1.nlib"
set fcfp(required_inputs,top_compile1)      "work/FCFP/place_pins1/run/place_pins1.nlib"
set fcfp(required_inputs,timing_budget1)    "work/FCFP/top_compile1/run/top_compile1.nlib"
set fcfp(required_inputs,export_data1)      "work/FCFP/timing_budget1/run/timing_budget1.nlib"

# ── FC-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set fcfp {
    analysis,max_paths                                   ""
}

# --- COMMON (24 vars) ---
array set fcfp {
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
array set fcfp {
    compile,active_scenarios                             ""
    compile,early_stage                                  ""
    compile,qor_metric                                   ""
    compile,reduced_effort                               ""
}

# --- COPY_BLOCK (1 vars) ---
array set fcfp {
    copy_block,from                                      ""
}

# --- CREATE_ABSTRACT (1 vars) ---
array set fcfp {
    create_abstract,enable                               ""
}

# --- CREATE_FLOORPLAN (1 vars) ---
array set fcfp {
    create_floorplan,from_label                          ""
}

# --- CREATE_POWER (1 vars) ---
array set fcfp {
    create_power,from_label                              ""
}

# --- EXPORT_DATA (1 vars) ---
array set fcfp {
    export_data,from_label                               ""
}

# --- FLOORPLAN (13 vars) ---
array set fcfp {
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
array set fcfp {
    init_compile,from_label                              ""
}

# --- OUTPUT (1 vars) ---
array set fcfp {
    output,block_labeling                                ""
}

# --- PLACE_PINS (1 vars) ---
array set fcfp {
    place_pins,from_label                                ""
}

# --- PLACEMENT (8 vars) ---
array set fcfp {
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
array set fcfp {
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
array set fcfp {
    shaping,constraint_script                            ""
    shaping,from_label                                   ""
    shaping,min_height                                   ""
    shaping,min_width                                    ""
    shaping,style                                        ""
    shaping,target_utilization                           ""
}

# --- TIMING_BUDGET (4 vars) ---
array set fcfp {
    timing_budget,active_scenarios                       ""
    timing_budget,constraint_script                      ""
    timing_budget,from_label                             ""
    timing_budget,mode                                   ""
}

# --- TOP_COMPILE (5 vars) ---
array set fcfp {
    top_compile,active_scenarios                         ""
    top_compile,from_label                               ""
    top_compile,from_stage                               ""
    top_compile,qor_metric                               ""
    top_compile,to_stage                                 ""
}
