#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# STA — Cadence Tempus Tool Configuration
# Sourced from STA_config.tcl when tool=tempus
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tempus Tool Settings ────────────────────────────────────────────────────┐
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(tool,vendor) "cadence"
    set sta(tool,name) "tempus"
    set sta(tool,version) "v1.0.0"
    set sta(tool,args) "-batch -no_gui"

# ┌─ STA App Settings (moved from common STA_config.tcl) ──────────────────────┐
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(analysis,setup_margin) "0.0"
    set sta(analysis,hold_margin) "0.0"
    set sta(analysis,max_paths) 100
    set sta(analysis,significant_digits) 4
    set sta(analysis,ocv_mode) "aocv"
    set sta(analysis,si_aware) true
    set sta(analysis,derating_file) ""

# ┌─ Tempus Analysis Variables ──────────────────────────────────────────────┐
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(analysis,nworst) 1
    set sta(analysis,report_power) "true"
    set sta(analysis,pba_mode) "path"
    set sta(analysis,cppr_mode) "both"
    set sta(analysis,enable_aocvm) true
    set sta(extract_etm) "false"

# ── Tempus-RM App Variables (user overrides via user_config) ──
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(analysis,max_paths) ""
    set sta(analysis,report_power) ""

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(common,design_name) ""
    set sta(common,release_dir) ""
    set sta(common,release_phase) ""

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(extraction,effort) ""
    set sta(extraction,mode) "qrc"
    set sta(extraction,quantus_binary) "quantus"
    set sta(extraction,coupling) "YES"
    set sta(extraction,format) "spef"

# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set sta(timing,mode) ""
    set sta(timing,ocv_mode) ""
    set sta(timing,si_aware) ""

# ┌─ Tempus RAK Additions ─────────────────────────────────────────────────────┐
# array set sta { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    # Tempus threading
    set sta(tool,cpu_count) "8"

    # SI / Crosstalk
    set sta(timing,si_aware) "true"
    set sta(timing,si_glitch_report) "true"
    set sta(timing,si_glitch_propagation) "true"

    # PBA / EPBA
    set sta(timing,pba_nworst) "2"
    set sta(timing,pba_max_paths) "1000"
    set sta(timing,epba_max_paths) "10000"
    set sta(timing,epba_max_slack) "0.200"

    # Analysis
    set sta(analysis,max_paths) "100"
    set sta(analysis,report_power) "true"
    set sta(analysis,ocv_mode) "aocv"
