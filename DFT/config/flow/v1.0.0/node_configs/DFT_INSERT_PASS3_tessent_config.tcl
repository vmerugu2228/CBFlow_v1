#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DFT_INSERT_PASS3 — Mentor Tessent Tool Configuration
# Pass 3: EDT compression + OCC at-speed clocking.
# Scaffold — real handlers land in a Pass3 follow-on.
# ═══════════════════════════════════════════════════════════════════════════════

array set dft_insert_pass3 {
    tool,vendor   "mentor"
    tool,name     "tessent"
    tool,version  "v1.0.0"
    tool,args     "-shell -logfile tessent.log"
    tool,context  "patterns -scan"
}

# ┌─ EDT compression knobs ───────────────────────────────────────────────────┐
array set dft_insert_pass3 {
    edt,enable                 true
    edt,compression_ratio      100
    edt,input_channels         8
    edt,output_channels        8
    edt,xpress                 true
    edt,ssn_enable             true
}

# ┌─ OCC at-speed clocking knobs ─────────────────────────────────────────────┐
array set dft_insert_pass3 {
    occ,enable                 true
    occ,clock_domains          "auto"
    occ,scan_enable_pin        "scan_en"
    occ,test_clock_pin         "test_clk"
    occ,at_speed               true
    occ,cycles                 2
}

# ┌─ Control-point insertion ─────────────────────────────────────────────────┐
array set dft_insert_pass3 {
    ctrl_points,enabled        true
    ctrl_points,mode           "auto"
}

# ┌─ DRC + optimization ──────────────────────────────────────────────────────┐
array set dft_insert_pass3 {
    drc,level                  "strict"
    drc,optimize_enabled       true
    drc,new_violation_threshold 0
}

# ┌─ Pattern generation ──────────────────────────────────────────────────────┐
array set dft_insert_pass3 {
    vgen,enabled               true
    vgen,at_speed              true
    vgen,fault_models          {stuck_at transition_delay}
}
