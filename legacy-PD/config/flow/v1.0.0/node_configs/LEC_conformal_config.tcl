#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# LEC — Cadence Conformal Tool Configuration
# Sourced from LEC_config.tcl when tool=conformal
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Conformal Tool Settings ─────────────────────────────────────────────────┐
array set lec {
    tool,vendor   "cadence"
    tool,name     "conformal"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ Conformal Comparison Settings ──────────────────────────────────────────┐
array set lec {
    compare,effort             "high"
    compare,flatten_design     true
    compare,datapath_verify    true
    compare,uniquify_names     true
    compare,abort_on_error     false
    compare,renaming_rules     ""
    output,report_dir          "reports/lec"
    output,results_dir         "results/lec"
    output,work_dir            "work/LEC"
}
