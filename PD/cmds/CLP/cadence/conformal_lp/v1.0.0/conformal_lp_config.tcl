#!/usr/bin/env tclsh
# =============================================================================
# CONFORMAL_LP Tool Configuration - CLP Flow
# =============================================================================
# Convention: conformal_lp(common,var) shared, conformal_lp(<node>,var) node-specific
# Override: set conformal_lp(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (2 vars) ---
array set conformal_lp {
    common,design_name                                   ""
    common,release_phase                                 ""
}

