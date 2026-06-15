#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DFT_INSERT — Mentor Tessent Tool Configuration
# Sourced from DFT_INSERT_config.tcl when tool=tessent
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tessent Tool Settings ────────────────────────────────────────────────────┐
array set dft_insert {
    tool,vendor   "mentor"
    tool,name     "tessent"
    tool,version  "v1.0.0"
    tool,args     "-shell -logfile tessent.log"
}

# ┌─ MBIST insertion knobs ───────────────────────────────────────────────────┐
array set dft_insert {
    mbist,controller_type      "smart_serial"
    mbist,wrap_memories        true
    mbist,bist_clock_domain    "tessent_clk"
    mbist,test_modes           {prod_test diag_test}
}

# ┌─ OCC insertion knobs ─────────────────────────────────────────────────────┐
array set dft_insert {
    occ,clock_domains          "auto"
    occ,scan_enable_pin        "scan_en"
    occ,test_clock_pin         "test_clk"
    occ,at_speed               true
}

# ┌─ EDT / SSN insertion knobs ───────────────────────────────────────────────┐
array set dft_insert {
    edt,enable                 true
    edt,compression_ratio      100
    edt,input_channels         8
    edt,output_channels        8
    edt,ssn,enable             true
}

# ┌─ DFT Verify knobs ────────────────────────────────────────────────────────┐
array set dft_insert {
    verify,drc_level           "strict"
    verify,coverage_threshold  98.0
}
