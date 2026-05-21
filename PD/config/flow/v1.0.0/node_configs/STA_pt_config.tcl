#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# STA — Synopsys PrimeTime (PT) Tool Configuration
# Sourced from STA_config.tcl when tool=pt
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ PT Tool Settings ────────────────────────────────────────────────────────┐
array set sta {
    tool,vendor   "synopsys"
    tool,name     "pt"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ STA App Settings (moved from common STA_config.tcl) ──────────────────────┐
array set sta {
    analysis,setup_margin      "0.0"
    analysis,hold_margin       "0.0"
    analysis,max_paths         100
    analysis,significant_digits 4
    analysis,ocv_mode          "aocv"
    analysis,si_aware          true
    analysis,derating_file     ""
}

# ┌─ PT-RM W-2024.09 Analysis Variables ─────────────────────────────────────┐
array set sta {
    analysis,nworst            1
    analysis,report_power      "true"
    analysis,pba_mode          "exhaustive"
    extract_etm                "false"
}

# ── PT-RM App Variables ──────────────────────────────────────────────
# --- ANALYSIS (5 vars) ---
array set sta {
    analysis,max_paths                                   ""
    analysis,ocv_mode                                    ""
    analysis,report_power                                ""
    analysis,si_aware                                    ""
    analysis,significant_digits                          ""
}

# --- COMMON (4 vars) ---
array set sta {
    common,design_name                                   ""
    common,extract_etm                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}
