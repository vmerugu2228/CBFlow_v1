#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# POPT — Synopsys PrimeTime (PT) Tool Configuration
# Sourced from POPT_config.tcl when tool=pt
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ PT Tool Settings ────────────────────────────────────────────────────────┐
array set popt {
    tool,vendor   "synopsys"
    tool,name     "pt"
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

# ┌─ PT Power Analysis Settings ──────────────────────────────────────────────┐
array set popt {
    pt,power_analysis_mode     "averaged"
    pt,enable_clock_gating     true
    pt,leakage_analysis        true
    pt,report_switching_power  true
    pt,pba_mode                "exhaustive"
}

# ── PT-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (2 vars) ---
array set popt {
    analysis,max_paths                                   ""
    analysis,significant_digits                          ""
}

# --- COMMON (2 vars) ---
array set popt {
    common,design_name                                   ""
    common,release_phase                                 ""
}
