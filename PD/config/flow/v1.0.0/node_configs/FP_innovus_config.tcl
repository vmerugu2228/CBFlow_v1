#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# FP — Cadence Innovus Tool Configuration
# Sourced from FP_config.tcl when tool=innovus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Innovus Tool Settings ────────────────────────────────────────────────────┐
array set fp {
    tool,vendor   "cadence"
    tool,name     "innovus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ FP App Settings (moved from common FP_config.tcl) ────────────────────────┐
array set fp {
    floorplan,die_width         ""
    floorplan,die_height        ""
    floorplan,core_utilization  0.70
    floorplan,core_aspect_ratio 1.0
    floorplan,core_offset       "5.0 5.0 5.0 5.0"
    floorplan,macro_placement   true
    floorplan,macro_spacing     "2.0"
    floorplan,macro_channel     "5.0"
    floorplan,boundary_cells    true
    floorplan,tap_cells         true
    power,net_names             "VDD VSS"
    power,ring_width            "2.0"
    power,ring_spacing          "1.0"
    power,strap_width           "0.8"
    power,strap_pitch           "20.0"
    power,mesh_layers           "M8 M9"
}

# ┌─ Innovus Init Design Control ──────────────────────────────────────────────┐
array set fp {
    init_design,input_type      "netlist"
    init_design,lef_files       ""
}

# ┌─ Innovus Compile/Import Control ───────────────────────────────────────────┐
array set fp {
    import,effort               "medium"
    import,timing_driven        true
}

# ┌─ Innovus Create Power Control ─────────────────────────────────────────────┐
array set fp {
    powerplan,pns_file          ""
    powerplan,stdcell_placement true
    powerplan,stdcell_effort    "low"
    powerplan,add_stripes       true
}

# ┌─ Innovus Required Inputs (enc handoff between stages) ────────────────────┐
set fp(required_inputs,init_design1)      "work/FP/netlist1/netlist work/FP/sdc1/sdc work/FP/def1/def work/FP/upf1/upf work/FP/library1/library"
set fp(required_inputs,floorplan1)        "work/FP/init_design1/outputs/init_design.enc.dat"
set fp(required_inputs,powerplan1)        "work/FP/floorplan1/outputs/floorplan.enc.dat"
set fp(required_inputs,export_data1)      "work/FP/powerplan1/outputs/powerplan.enc.dat"

# ── Innovus-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (1 vars) ---
array set fp {
    analysis,max_paths                                   ""
}

# --- COMMON (21 vars) ---
array set fp {
    common,aspect_ratio                                  ""
    common,core_utilization                              ""
    common,design_name                                   ""
    common,ground_net                                    ""
    common,import_mode                                   ""
    common,input_netlist                                 ""
    common,input_sdc                                     ""
    common,input_upf_supplemental                        ""
    common,io_filler_cells                               ""
    common,io_pads                                       ""
    common,macros                                        ""
    common,mmmc_setup_file                               ""
    common,power_net                                     ""
    common,release_phase                                 ""
    common,row_spacing                                   ""
    common,rows                                          ""
    common,sdc_mode                                      ""
    common,site_name                                     ""
    common,snap_to_grid                                  ""
    common,tool_mode                                     ""
    common,tracks                                        ""
}

# --- CORE_MARGIN (4 vars) ---
array set fp {
    core_margin,bottom                                   ""
    core_margin,left                                     ""
    core_margin,right                                    ""
    core_margin,top                                      ""
}

# --- DIE (2 vars) ---
array set fp {
    die,height                                           ""
    die,width                                            ""
}

# --- MACRO_HALO (2 vars) ---
array set fp {
    macro_halo,x                                         ""
    macro_halo,y                                         ""
}

# --- POWER (21 vars) ---
array set fp {
    power,analyze_ir                                     ""
    power,macro_ring_spacing                             ""
    power,macro_ring_width                               ""
    power,macro_rings                                    ""
    power,ring_layer_h                                   ""
    power,ring_layer_v                                   ""
    power,ring_offset                                    ""
    power,ring_spacing                                   ""
    power,ring_width                                     ""
    power,sroute_bottom_layer                            ""
    power,sroute_top_layer                               ""
    power,strap_layer                                    ""
    power,strap_pitch                                    ""
    power,strap_width                                    ""
    power,straps                                         ""
    power,tie_high_pin                                   ""
    power,tie_low_pin                                    ""
    power,vdd_net                                        ""
    power,vdd_pin                                        ""
    power,vss_net                                        ""
    power,vss_pin                                        ""
}
