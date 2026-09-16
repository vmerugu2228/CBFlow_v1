#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# EMIR — Cadence Voltus Tool Configuration
# Sourced from EMIR_config.tcl when tool=voltus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Voltus Tool Settings ────────────────────────────────────────────────────┐
array set emir {
    tool,vendor   "cadence"
    tool,name     "voltus"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ EMIR App Settings (moved from common EMIR_config.tcl) ────────────────────┐
array set emir {
    power,analysis_mode        "vectorless"
}

# ┌─ Voltus Power Analysis Settings ──────────────────────────────────────────┐
array set emir {
    voltus,power_model         "vectorless"
    voltus,switching_activity  ""
    voltus,num_cpus            8
    voltus,accuracy_mode       "signoff"
}

# ┌─ Voltus IR Drop Settings ─────────────────────────────────────────────────┐
array set emir {
    voltus,static_ir           true
    voltus,dynamic_ir          true
    voltus,em_analysis         true
    voltus,pg_mesh_density     "auto"
}

# ┌─ Voltus Thermal Settings ─────────────────────────────────────────────────┐
array set emir {
    voltus,thermal_model       "compact"
    voltus,ambient_temp        "25"
    voltus,junction_temp       "125"
}

# ── Voltus-RM App Variables (user overrides via user_config) ──
array set emir {
    common,design_name                                   ""
    common,release_phase                                 ""
}

array set emir {
    em,skip                                              ""
    em,threshold                                         ""
}

array set emir {
    ir_drop,analysis_mode                                ""
    ir_drop,max_violations                               ""
    ir_drop,mesh_density                                 ""
    ir_drop,pad_location_file                            ""
    ir_drop,run_dynamic                                  ""
    ir_drop,threshold                                    ""
}

array set emir {
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

array set emir {
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
