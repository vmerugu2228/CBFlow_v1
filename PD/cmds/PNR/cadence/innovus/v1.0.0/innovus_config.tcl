#!/usr/bin/env tclsh
# =============================================================================
# INNOVUS Tool Configuration - PNR Flow
# =============================================================================
# Convention: innovus(common,var) shared, innovus(<node>,var) node-specific
# Override: set innovus(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set innovus {
    analysis,max_paths                                   ""
}

# --- CHIP_FINISH (22 vars) ---
array set innovus {
    chip_finish,antenna_check                            ""
    chip_finish,antenna_fix                              ""
    chip_finish,cleanup                                  ""
    chip_finish,cleanup_level                            ""
    chip_finish,eco_check                                ""
    chip_finish,eco_timing                               ""
    chip_finish,fill_density                             ""
    chip_finish,fill_layers                              ""
    chip_finish,fill_spacing                             ""
    chip_finish,filler_cells                             ""
    chip_finish,filler_prefix                            ""
    chip_finish,filler_types                             ""
    chip_finish,ir_drop_target                           ""
    chip_finish,keep_checkpoints                         ""
    chip_finish,lvs_netlist                              ""
    chip_finish,lvs_prep                                 ""
    chip_finish,metal_fill                               ""
    chip_finish,power_opt                                ""
    chip_finish,rail_analysis                            ""
    chip_finish,spare_cells                              ""
    chip_finish,spare_ratio                              ""
    chip_finish,spare_types                              ""
}

# --- COMMON (7 vars) ---
array set innovus {
    common,design_name                                   ""
    common,ground_net                                    ""
    common,input_netlist                                 ""
    common,lib_cell_purpose_file                         ""
    common,mmmc_setup_file                               ""
    common,power_net                                     ""
    common,release_phase                                 ""
}

# --- CTS (6 vars) ---
array set innovus {
    cts,buffer_cells                                     ""
    cts,inverter_cells                                   ""
    cts,max_cap                                          ""
    cts,max_trans                                        ""
    cts,opt_effort                                       ""
    cts,target_skew                                      ""
}

# --- CTS_OPT (4 vars) ---
array set innovus {
    cts_opt,balance_effort                               ""
    cts_opt,effort                                       ""
    cts_opt,fix_hold                                     ""
    cts_opt,refine_iterations                            ""
}

# --- EXPORT (19 vars) ---
array set innovus {
    export,abstract                                      ""
    export,antenna                                       ""
    export,def                                           ""
    export,drc                                           ""
    export,floorplan                                     ""
    export,gds                                           ""
    export,lef                                           ""
    export,lvs                                           ""
    export,oasis                                         ""
    export,placement                                     ""
    export,power_reports                                 ""
    export,rail_analysis                                 ""
    export,routing                                       ""
    export,sdc                                           ""
    export,sdf                                           ""
    export,spef                                          ""
    export,spice                                         ""
    export,upf                                           ""
    export,verilog                                       ""
}

# --- EXTRACT (3 vars) ---
array set innovus {
    extract,effort                                       ""
    extract,mode                                         ""
    extract,rc_corner                                    ""
}

# --- FLOORPLAN (12 vars) ---
array set innovus {
    floorplan,aspect_ratio                               ""
    floorplan,core_margins                               ""
    floorplan,core_util                                  ""
    floorplan,io_pin_depth                               ""
    floorplan,io_pin_spacing                             ""
    floorplan,io_pin_width                               ""
    floorplan,io_placement_file                          ""
    floorplan,io_placement_mode                          ""
    floorplan,mode                                       ""
    floorplan,power_domains                              ""
    floorplan,site_name                                  ""
    floorplan,upf_file                                   ""
}

# --- OPT (3 vars) ---
array set innovus {
    opt,hold_margin                                      ""
    opt,insert_metal_fill                                ""
    opt,setup_margin                                     ""
}

# --- OUTPUT (1 vars) ---
array set innovus {
    output,gds                                           ""
}

# --- PLACE (5 vars) ---
array set innovus {
    place,congestion_effort                              ""
    place,density                                        ""
    place,effort                                         ""
    place,opt_effort                                     ""
    place,timing_driven                                  ""
}

# --- POWERPLAN (13 vars) ---
array set innovus {
    powerplan,ring_layers                                ""
    powerplan,ring_nets                                  ""
    powerplan,ring_offset                                ""
    powerplan,ring_spacing                               ""
    powerplan,ring_width                                 ""
    powerplan,stripe_direction                           ""
    powerplan,stripe_layers                              ""
    powerplan,stripe_nets                                ""
    powerplan,stripe_spacing                             ""
    powerplan,stripe_width                               ""
    powerplan,well_tie_cells                             ""
    powerplan,well_tie_rule                              ""
    powerplan,well_tie_spacing                           ""
}

# --- ROUTE (7 vars) ---
array set innovus {
    route,effort                                         ""
    route,fix_antenna                                    ""
    route,layers                                         ""
    route,post_opt_effort                                ""
    route,si_aware                                       ""
    route,timing_driven                                  ""
    route,via_opt                                        ""
}

# --- SIGNOFF (1 vars) ---
array set innovus {
    signoff,extract_effort                               ""
}

