#!/usr/bin/env tclsh
# =============================================================================
# REDHAWK Tool Configuration - EMIR Flow
# =============================================================================
# Convention: redhawk(common,var) shared, redhawk(<node>,var) node-specific
# Override: set redhawk(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (3 vars) ---
array set redhawk {
    common,design_name                                   ""
    common,release_phase                                 ""
    common,top_cell                                      ""
}

# --- EM (1 vars) ---
array set redhawk {
    em,enable                                            ""
}

# --- IR (4 vars) ---
array set redhawk {
    ir,em_threshold                                      ""
    ir,mode                                              ""
    ir,vdd_threshold                                     ""
    ir,vss_threshold                                     ""
}

# --- IR_DROP (3 vars) ---
array set redhawk {
    ir_drop,fix_missing_vias                             ""
    ir_drop,missing_via_threshold                        ""
    ir_drop,threshold                                    ""
}

# --- OUTPUT (2 vars) ---
array set redhawk {
    output,em_report                                     ""
    output,report_file                                   ""
}

# --- POWER (8 vars) ---
array set redhawk {
    power,analysis_mode                                  ""
    power,analysis_nets                                  ""
    power,frequency                                      ""
    power,scenario                                       ""
    power,switching_activity_file                        ""
    power,use_fc_power                                   ""
    power,vdd_voltage                                    ""
    power,voltage                                        ""
}

# --- THERMAL (8 vars) ---
array set redhawk {
    thermal,ambient_temp                                 ""
    thermal,boundary                                     ""
    thermal,enable                                       ""
    thermal,grid_resolution                              ""
    thermal,substrate_k                                  ""
    thermal,temperature                                  ""
    thermal,theta_ja                                     ""
    thermal,threshold                                    ""
}

