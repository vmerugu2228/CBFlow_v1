#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# POPT — Cadence Joules Tool Configuration
# Sourced from POPT_config.tcl when tool=joules
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Joules Tool Settings ────────────────────────────────────────────────────┐
array set popt {
    tool,vendor   "cadence"
    tool,name     "joules"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ POPT App Settings (moved from common POPT_config.tcl) ────────────────────┐
array set popt {
    power,target_total         ""
    power,leakage_budget       ""
    power,dynamic_budget       ""
    optimization,clock_gating_min_bitwidth 4
    optimization,operand_isolation true
    optimization,multi_vt      true
    optimization,effort        "high"
}

# ┌─ Joules Power Analysis Settings ──────────────────────────────────────────┐
array set popt {
    joules,power_analysis_mode  "averaged"
    joules,enable_clock_gating  true
    joules,leakage_analysis     true
    joules,rtl_power_estimation true
    joules,accuracy_mode        "signoff"
}
