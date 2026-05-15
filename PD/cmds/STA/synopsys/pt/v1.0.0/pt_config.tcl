#!/usr/bin/env tclsh
# =============================================================================
# PT Tool Configuration - STA Flow
# =============================================================================
# Convention: pt(common,var) shared, pt(<node>,var) node-specific
# Override: set pt(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (5 vars) ---
array set pt {
    analysis,max_paths                                   ""
    analysis,ocv_mode                                    ""
    analysis,report_power                                ""
    analysis,si_aware                                    ""
    analysis,significant_digits                          ""
}

# --- COMMON (4 vars) ---
array set pt {
    common,design_name                                   ""
    common,extract_etm                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

