#!/usr/bin/env tclsh
# =============================================================================
# ICC2 Tool Configuration - ECO Flow
# =============================================================================
# Convention: icc2(common,var) shared, icc2(<node>,var) node-specific
# Override: set icc2(<key>) "value" in user_config.tcl
# =============================================================================

# --- ANALYSIS (1 vars) ---
array set icc2 {
    analysis,max_paths                                   ""
}

# --- COMMON (1 vars) ---
array set icc2 {
    common,top_cell                                      ""
}

# --- EXPORT (2 vars) ---
array set icc2 {
    export,incremental_def                               ""
    export,pg_netlist                                    ""
}

# --- TIMING_ECO (3 vars) ---
array set icc2 {
    timing_eco,enable                                    ""
    timing_eco,hold_margin                               ""
    timing_eco,setup_margin                              ""
}

