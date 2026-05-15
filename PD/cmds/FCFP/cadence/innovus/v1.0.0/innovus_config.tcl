#!/usr/bin/env tclsh
# =============================================================================
# INNOVUS Tool Configuration - FCFP Flow
# =============================================================================
# Convention: innovus(common,var) shared, innovus(<node>,var) node-specific
# Override: set innovus(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (3 vars) ---
array set innovus {
    common,design_name                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

# --- EXPORT (3 vars) ---
array set innovus {
    export,floorplan_only_def                            ""
    export,skip_netlist                                  ""
    export,skip_sdc                                      ""
}

# --- FLOORPLAN (20 vars) ---
array set innovus {
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
array set innovus {
    post_floorplan,congestion_threshold                  ""
    post_floorplan,max_timing_paths                      ""
    post_floorplan,trial_route_effort                    ""
}

# --- POWER (19 vars) ---
array set innovus {
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

