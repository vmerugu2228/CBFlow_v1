#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# LEC — Synopsys Formality Tool Configuration
# Sourced from LEC_config.tcl when tool=formality
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Formality Tool Settings ─────────────────────────────────────────────────┐
array set lec {
    tool,vendor   "synopsys"
    tool,name     "formality"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ Formality Comparison Settings ──────────────────────────────────────────┐
array set lec {
    compare,effort             "high"
    compare,flatten_design     true
    compare,datapath_verify    true
    compare,uniquify_names     true
    compare,unresolved_modules "error"
    output,report_dir          "reports/lec"
    output,results_dir         "results/lec"
    output,work_dir            "work/LEC"
}

# ── Formality-RM App Variables ──────────────────────────────────────────────
# --- COMMON (3 vars) ---
array set lec {
    common,design_name                                   ""
    common,effort                                        ""
    common,release_phase                                 ""
}

# --- MATCHING (1 vars) ---
array set lec {
    matching,multibit                                    ""
}

# --- VERIFICATION (1 vars) ---
array set lec {
    verification,mode                                    ""
}
