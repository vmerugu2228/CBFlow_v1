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

# ┌─ VT Swap Configuration ────────────────────────────────────────────────────┐
array set popt {
    vt_swap,enabled             "true"
    vt_swap,rockbottom          "true"
    vt_swap,target_vt           "hvt"
    vt_swap,available_vts       "lvt svt hvt"
    vt_swap,vt_suffixes         "LVT SVT HVT"
    vt_swap,exclude_clock_cells  "true"
    vt_swap,exclude_dont_touch   "true"
    vt_swap,exclude_always_on    "true"
    vt_swap,exclude_power_cells  "true"
    vt_swap,exclude_cell_patterns ""
    vt_swap,exclude_inst_patterns ""
    vt_swap,exclude_ref_patterns  ""
    vt_swap,critical_instances    ""
}

# ┌─ Iteration Control ────────────────────────────────────────────────────────┐
array set popt {
    vt_swap,max_iterations      "20"
    vt_swap,paths_per_iteration "500"
    vt_swap,convergence_threshold "0.005"
    vt_swap,setup_target        "0.0"
    vt_swap,hold_target         "0.0"
}

# ┌─ Budget Constraints ───────────────────────────────────────────────────────┐
array set popt {
    vt_swap,leakage_budget      ""
    vt_swap,max_lvt_percentage  "15.0"
    vt_swap,max_svt_percentage  "60.0"
}

# ┌─ DMSA Configuration ───────────────────────────────────────────────────────┐
array set popt {
    dmsa,enabled                "true"
    dmsa,scenarios              ""
    dmsa,workers                "4"
    dmsa,host_list              ""
    dmsa,launch_method          "local"
}

# ┌─ Reporting ─────────────────────────────────────────────────────────────────┐
array set popt {
    report,per_iteration        "true"
    report,vt_distribution      "true"
    report,power_breakdown      "true"
}
