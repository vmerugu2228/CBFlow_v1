#!/usr/bin/env tclsh
# =============================================================================
# PT Tool Configuration - POPT Flow
# =============================================================================
# Convention: pt(common,var) shared, pt(<node>,var) node-specific
# Override: set pt(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (2 vars) ---
array set pt {
    analysis,max_paths                                   ""
    analysis,significant_digits                          ""
}

# --- COMMON (2 vars) ---
array set pt {
    common,design_name                                   ""
    common,release_phase                                 ""
}

