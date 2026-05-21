#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FCFP — Cadence Innovus Tool Configuration
# Sourced from FCFP_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ────────────────────────────────────────────────────┐
array set fcfp {
    tool,vendor   "cadence"
    tool,name     "innovus"
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

# ┌─ Innovus Commit Blocks Control ────────────────────────────────────────────┐
array set fcfp {
    sub_block_refs          {}
    sub_block_libraries     {}
}

# ┌─ Innovus Init Compile Control ─────────────────────────────────────────────┐
array set fcfp {
    compile,effort          "medium"
    compile,timing_driven   true
    compile,leakage_opt     false
}

# ┌─ Innovus Shaping Control ──────────────────────────────────────────────────┐
array set fcfp {
    shaping,style               "auto"
    shaping,min_channel_width   ""
    shaping,target_utilization  ""
}

# ┌─ Innovus Placement Control ────────────────────────────────────────────────┐
array set fcfp {
    placement,congestion_driven true
    placement,timing_driven     true
    placement,max_density       0.70
}

# ┌─ Innovus Create Power Control ─────────────────────────────────────────────┐
array set fcfp {
    powerplan,pns_file          ""
    powerplan,stdcell_placement true
    powerplan,add_stripes       true
}

# ┌─ Innovus Top Compile Control ──────────────────────────────────────────────┐
array set fcfp {
    top_compile,effort          "medium"
    top_compile,timing_driven   true
}

# ┌─ Innovus Timing Budget Control ────────────────────────────────────────────┐
array set fcfp {
    timing_budget,estimate_timing  true
    timing_budget,distribute       true
}

# ┌─ Innovus Required Inputs (enc handoff between stages) ────────────────────┐
set fcfp(required_inputs,init_design1)      "work/FCFP/netlist1/netlist work/FCFP/sdc1/sdc work/FCFP/def1/def work/FCFP/upf1/upf work/FCFP/library1/library"
set fcfp(required_inputs,commit_blocks1)    "work/FCFP/init_design1/run/init_design1.enc"
set fcfp(required_inputs,init_compile1)     "work/FCFP/commit_blocks1/run/commit_blocks1.enc"
set fcfp(required_inputs,create_floorplan1) "work/FCFP/init_compile1/run/init_compile1.enc"
set fcfp(required_inputs,shaping1)          "work/FCFP/create_floorplan1/run/create_floorplan1.enc"
set fcfp(required_inputs,placement1)        "work/FCFP/shaping1/run/shaping1.enc"
set fcfp(required_inputs,create_power1)     "work/FCFP/placement1/run/placement1.enc"
set fcfp(required_inputs,place_pins1)       "work/FCFP/create_power1/run/create_power1.enc"
set fcfp(required_inputs,top_compile1)      "work/FCFP/place_pins1/run/place_pins1.enc"
set fcfp(required_inputs,timing_budget1)    "work/FCFP/top_compile1/run/top_compile1.enc"
set fcfp(required_inputs,export_data1)      "work/FCFP/timing_budget1/run/timing_budget1.enc"

# ── Innovus-RM App Variables ──────────────────────────────────────────────
# --- COMMON (3 vars) ---
array set fcfp {
    common,design_name                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

# --- EXPORT (3 vars) ---
array set fcfp {
    export,floorplan_only_def                            ""
    export,skip_netlist                                  ""
    export,skip_sdc                                      ""
}

# --- FLOORPLAN (20 vars) ---
array set fcfp {
    floorplan,aspect_ratio                               ""
    floorplan,blockage_margin                            ""
    floorplan,core_margin_bottom                         ""
    floorplan,core_margin_left                           ""
    floorplan,core_margin_right                          ""
    floorplan,core_margin_top                            ""
    floorplan,create_macro_blockage                      ""
    floorplan,die_height                                 ""
    floorplan,die_width                                  ""
    floorplan,io_constraint_file                         ""
    floorplan,io_filler_cells                            ""
    floorplan,io_pin_layer                               ""
    floorplan,macro_halo_x                               ""
    floorplan,macro_halo_y                               ""
    floorplan,macro_placement_file                       ""
    floorplan,partition_constraints_file                 ""
    floorplan,partition_list                             ""
    floorplan,partition_pin_mode                         ""
    floorplan,site_name                                  ""
    floorplan,utilization                                ""
}

# --- POST_FLOORPLAN (3 vars) ---
array set fcfp {
    post_floorplan,congestion_threshold                  ""
    post_floorplan,max_timing_paths                      ""
    post_floorplan,trial_route_effort                    ""
}

# --- POWER (19 vars) ---
array set fcfp {
    power,block_ring_width                               ""
    power,create_block_rings                             ""
    power,fine_strap_layer                               ""
    power,fine_strap_pitch                               ""
    power,fine_strap_width                               ""
    power,ring_layer_h                                   ""
    power,ring_layer_v                                   ""
    power,ring_offset                                    ""
    power,ring_spacing                                   ""
    power,ring_width                                     ""
    power,strap_layer_h                                  ""
    power,strap_layer_v                                  ""
    power,strap_pitch                                    ""
    power,strap_spacing                                  ""
    power,strap_width                                    ""
    power,tie_high_net                                   ""
    power,tie_low_net                                    ""
    power,vdd_net                                        ""
    power,vss_net                                        ""
}
