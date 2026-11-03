#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DFT_INSERT_PASS2 — Mentor Tessent Tool Configuration
# Pass 2: Top-level DFT insertion (TDR + DFT Signals + SRI).
# Scaffold — real handlers land in a Pass2 follow-on.
# ═══════════════════════════════════════════════════════════════════════════════

array set dft_insert_pass2 {
    tool,vendor   "mentor"
    tool,name     "tessent"
    tool,version  "v1.0.0"
    tool,args     "-shell -logfile tessent.log"
    tool,context  "patterns -scan"
}

array set dft_insert_pass2 {
    tdr,enabled                true
    tdr,data_width             32
    tdr,shift_clock_pin        "TCK"

    dft_signals,enabled        true
    dft_signals,test_mode_pin  "test_mode"
    dft_signals,scan_enable_pin "scan_en"

    sri,enabled                true
    sri,resource_count         "auto"
}

array set dft_insert_pass2 {
    vgen,enabled               false
    sim,enabled                false

    drc,level                  "strict"
    drc,waiver_file            ""
}
