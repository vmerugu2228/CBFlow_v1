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
# power,analysis_mode: static | vectorless | dynamic | dynamic_vectorless —
# required by power_analysis_voltus.tcl. "static" is the value the script used
# before (the "vectorless" set here was overridden by an empty RM-block entry,
# which made the script fall back to its built-in "static"; that duplicate
# entry is removed below).
array set emir {
    power,analysis_mode        "static"
}

# ┌─ Voltus Default Switching Activity / IR Report Settings ──────────────────┐
# Previously hard-coded in power_analysis_voltus.tcl / ir_drop_voltus.tcl.
# power,default_toggle_rate      -> set_default_switching_activity -input_activity
# power,default_activity_period  -> set_default_switching_activity -period
#                                   (the script used to read this from the
#                                   unrelated power,default_static_probability key)
# ir_drop,max_violations         -> report_power_rail -worst_instances
array set emir {
    power,default_toggle_rate      "0.2"
    power,default_activity_period  "2.0"
    ir_drop,max_violations         100
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
    ir_drop,mesh_density                                 ""
    ir_drop,pad_location_file                            ""
    ir_drop,run_dynamic                                  ""
    ir_drop,threshold                                    ""
}

array set emir {
    power,default_static_probability                     ""
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
