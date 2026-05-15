#!/usr/bin/env tclsh
# =============================================================================
# TEMPUS Tool Configuration - STA Flow
# =============================================================================
# Convention: tempus(common,var) shared, tempus(<node>,var) node-specific
# Override: set tempus(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (2 vars) ---
array set tempus {
    analysis,max_paths                                   ""
    analysis,report_power                                ""
}

# --- COMMON (3 vars) ---
array set tempus {
    common,design_name                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

# --- EXTRACTION (2 vars) ---
array set tempus {
    extraction,effort                                    ""
    extraction,mode                                      ""
}

# --- TIMING (3 vars) ---
array set tempus {
    timing,mode                                          ""
    timing,ocv_mode                                      ""
    timing,si_aware                                      ""
}

