#!/usr/bin/env tclsh
# =============================================================================
# VC_LP Tool Configuration - CLP Flow
# =============================================================================
# Convention: vc_lp(common,var) shared, vc_lp(<node>,var) node-specific
# Override: set vc_lp(<key>) "value" in user_config.tcl
# =============================================================================

# --- CHECK (4 vars) ---
array set vc_lp {
    check,continue_on_error                              ""
    check,hanging_crossover                              ""
    check,multi_driver                                   ""
    check,verdi_debug                                    ""
}

# --- COMMON (3 vars) ---
array set vc_lp {
    common,design_name                                   ""
    common,release_phase                                 ""
    common,upf_mode                                      ""
}

