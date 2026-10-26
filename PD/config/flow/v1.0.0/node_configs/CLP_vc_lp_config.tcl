#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CLP — Synopsys VC_LP Tool Configuration
# Sourced from CLP_config.tcl when tool=vc_lp
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ VC_LP Tool Settings ─────────────────────────────────────────────────────┐
array set clp {
    tool,vendor   "synopsys"
    tool,name     "vc_lp"
    tool,version  "v1.0.0"
    tool,args     "-batch -no_gui"
}

# ┌─ CLP App Settings (moved from common CLP_config.tcl) ──────────────────────┐
array set clp {
    check,isolation            true
    check,retention            true
    check,level_shifter        true
    check,power_domain         true
    check,always_on            true
    check,voltage_area         true
}

# ┌─ FC-RM VC LP App Var Control ─────────────────────────────────────────────┐
array set clp {
    check,continue_on_error    true
    check,hanging_crossover    true
    check,multi_driver         true
    check,verdi_debug          true
    upf_mode                   "prime"
}
