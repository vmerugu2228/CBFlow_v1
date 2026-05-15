#!/usr/bin/env tclsh
# =============================================================================
# INNOVUS Tool Configuration - FP Flow
# =============================================================================
# Convention: innovus(common,var) shared, innovus(<node>,var) node-specific
# Override: set innovus(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set innovus {
    analysis,max_paths                                   ""
}

# --- COMMON (21 vars) ---
array set innovus {
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
array set innovus {
    core_margin,bottom                                   ""
    core_margin,left                                     ""
    core_margin,right                                    ""
    core_margin,top                                      ""
}

# --- DIE (2 vars) ---
array set innovus {
    die,height                                           ""
    die,width                                            ""
}

# --- MACRO_HALO (2 vars) ---
array set innovus {
    macro_halo,x                                         ""
    macro_halo,y                                         ""
}

# --- POWER (21 vars) ---
array set innovus {
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

