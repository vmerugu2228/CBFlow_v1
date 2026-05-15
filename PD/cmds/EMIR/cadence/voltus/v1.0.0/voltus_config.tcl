#!/usr/bin/env tclsh
# =============================================================================
# VOLTUS Tool Configuration - EMIR Flow
# =============================================================================
# Convention: voltus(common,var) shared, voltus(<node>,var) node-specific
# Override: set voltus(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (2 vars) ---
array set voltus {
    common,design_name                                   ""
    common,release_phase                                 ""
}

# --- EM (2 vars) ---
array set voltus {
    em,skip                                              ""
    em,threshold                                         ""
}

# --- IR_DROP (6 vars) ---
array set voltus {
    ir_drop,analysis_mode                                ""
    ir_drop,max_violations                               ""
    ir_drop,mesh_density                                 ""
    ir_drop,pad_location_file                            ""
    ir_drop,run_dynamic                                  ""
    ir_drop,threshold                                    ""
}

# --- POWER (10 vars) ---
array set voltus {
    power,analysis_mode                                  ""
    power,default_static_probability                     ""
    power,default_toggle_rate                            ""
    power,map_resolution                                 ""
    power,multi_voltage                                  ""
    power,per_layer_map                                  ""
    power,precision                                      ""
    power,supply_voltage                                 ""
    power,vdd_net                                        ""
    power,vss_net                                        ""
}

# --- THERMAL (12 vars) ---
array set voltus {
    thermal,ambient_temperature                          ""
    thermal,analysis_type                                ""
    thermal,conductivity_model                           ""
    thermal,gradient_threshold                           ""
    thermal,heat_sink_coefficient                        ""
    thermal,heat_sink_enabled                            ""
    thermal,hotspot_threshold                            ""
    thermal,max_hotspots                                 ""
    thermal,mesh_resolution                              ""
    thermal,per_layer_report                             ""
    thermal,power_thermal_loop                           ""
    thermal,theta_ja                                     ""
}

