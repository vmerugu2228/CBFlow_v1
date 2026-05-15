#!/usr/bin/env tclsh
# =============================================================================
# POWER_COMPILER Tool Configuration - POPT Flow
# =============================================================================
# Convention: power_compiler(common,var) shared, power_compiler(<node>,var) node-specific
# Override: set power_compiler(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set power_compiler {
    analysis,max_paths                                   ""
}

# --- COMMON (2 vars) ---
array set power_compiler {
    common,design_name                                   ""
    common,release_phase                                 ""
}

