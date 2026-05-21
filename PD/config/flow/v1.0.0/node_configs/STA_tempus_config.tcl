#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# STA — Cadence Tempus Tool Configuration
# Sourced from STA_config.tcl when tool=tempus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tempus Tool Settings ────────────────────────────────────────────────────┐
array set sta {
    tool,vendor   "cadence"
    tool,name     "tempus"
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

# ┌─ Tempus Analysis Variables ──────────────────────────────────────────────┐
array set sta {
    analysis,nworst            1
    analysis,report_power      "true"
    analysis,pba_mode          "path"
    analysis,cppr_mode         "both"
    analysis,enable_aocvm      true
    extract_etm                "false"
}

# ── Tempus-RM App Variables (user overrides via user_config) ──
array set sta {
    analysis,max_paths                                   ""
    analysis,report_power                                ""
}

array set sta {
    common,design_name                                   ""
    common,release_dir                                   ""
    common,release_phase                                 ""
}

array set sta {
    extraction,effort                                    ""
    extraction,mode                                      ""
}

array set sta {
    timing,mode                                          ""
    timing,ocv_mode                                      ""
    timing,si_aware                                      ""
}
