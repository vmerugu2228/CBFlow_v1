#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CLP — Cadence Conformal LP Tool Configuration
# Sourced from CLP_config.tcl when tool=conformal_lp
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Conformal LP Tool Settings ──────────────────────────────────────────────┐
array set clp {
    tool,vendor   "cadence"
    tool,name     "conformal_lp"
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

# ┌─ Conformal LP Check Settings ─────────────────────────────────────────────┐
array set clp {
    check,continue_on_error    true
    check,hierarchical         true
    check,multi_driver         true
    upf_mode                   "1801"
}

# ── Conformal_LP-RM App Variables (user overrides via user_config) ──
array set clp {
    common,design_name                                   ""
    common,release_phase                                 ""
}
