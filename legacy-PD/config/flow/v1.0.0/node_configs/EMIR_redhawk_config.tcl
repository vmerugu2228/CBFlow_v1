#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# EMIR — Synopsys Redhawk Tool Configuration
# Sourced from EMIR_config.tcl when tool=redhawk
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Redhawk Tool Settings ───────────────────────────────────────────────────┐
array set emir {
    tool,vendor   "synopsys"
    tool,name     "redhawk"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ EMIR App Settings (moved from common EMIR_config.tcl) ────────────────────┐
array set emir {
    power,analysis_mode        "vectorless"
}

# ┌─ Redhawk Power Analysis Settings ─────────────────────────────────────────┐
array set emir {
    redhawk,power_model        "vectorless"
    redhawk,switching_activity ""
    redhawk,num_cpus           8
    redhawk,mesh_density       "auto"
}

# ┌─ Redhawk IR Drop Settings ────────────────────────────────────────────────┐
array set emir {
    redhawk,static_ir          true
    redhawk,dynamic_ir         true
    redhawk,em_analysis        true
    redhawk,voltage_droop      true
}

# ┌─ Redhawk Thermal Settings ────────────────────────────────────────────────┐
array set emir {
    redhawk,thermal_model      "compact"
    redhawk,ambient_temp       "25"
    redhawk,junction_temp      "125"
}

# ── Redhawk-RM App Variables ──────────────────────────────────────────────
# --- COMMON (3 vars) ---
array set emir {
    common,design_name                                   ""
    common,release_phase                                 ""
    common,top_cell                                      ""
}

# --- EM (1 vars) ---
array set emir {
    em,enable                                            ""
}

# --- IR (4 vars) ---
array set emir {
    ir,em_threshold                                      ""
    ir,mode                                              ""
    ir,vdd_threshold                                     ""
    ir,vss_threshold                                     ""
}

# --- IR_DROP (3 vars) ---
array set emir {
    ir_drop,fix_missing_vias                             ""
    ir_drop,missing_via_threshold                        ""
    ir_drop,threshold                                    ""
}

# --- OUTPUT (2 vars) ---
array set emir {
    output,em_report                                     ""
    output,report_file                                   ""
}

# --- POWER (8 vars) ---
array set emir {
    power,analysis_mode                                  ""
    power,analysis_nets                                  ""
    power,frequency                                      ""
    power,scenario                                       ""
    power,switching_activity_file                         ""
    power,use_fc_power                                   ""
    power,vdd_voltage                                    ""
    power,voltage                                        ""
}

# --- THERMAL (8 vars) ---
array set emir {
    thermal,ambient_temp                                 ""
    thermal,boundary                                     ""
    thermal,enable                                       ""
    thermal,grid_resolution                              ""
    thermal,substrate_k                                  ""
    thermal,temperature                                  ""
    thermal,theta_ja                                     ""
    thermal,threshold                                    ""
}
