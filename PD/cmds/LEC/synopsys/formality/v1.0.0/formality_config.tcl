#!/usr/bin/env tclsh
# =============================================================================
# FORMALITY Tool Configuration - LEC Flow
# =============================================================================
# Convention: formality(common,var) shared, formality(<node>,var) node-specific
# Override: set formality(<key>) "value" in user_config.tcl
# =============================================================================

# --- COMMON (3 vars) ---
array set formality {
    common,design_name                                   ""
    common,effort                                        ""
    common,release_phase                                 ""
}

# --- MATCHING (1 vars) ---
array set formality {
    matching,multibit                                    ""
}

# --- VERIFICATION (1 vars) ---
array set formality {
    verification,mode                                    ""
}

