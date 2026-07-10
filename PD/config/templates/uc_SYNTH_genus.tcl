#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — SYNTH / Genus (Cadence)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_SYNTH_genus.tcl <workarea>/uc_SYNTH_genus.tcl
#   cbflow workspace create --config uc_SYNTH_genus.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "SYNTH"                ;# Flow type (synthesis only)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
set synth(tool,name)           "genus"                ;# Cadence Genus (vendor auto-resolves)

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set synth(input,rtl_filelist)    "<PROJECT_ROOT>/rtl.list"       ;# RTL file list (one file per line)
set synth(input,rtl_format)      "sverilog"                      ;# RTL format: verilog, sverilog, vhdl
set synth(input,sdc_func_file)   "<PROJECT_ROOT>/func.sdc"      ;# Functional mode SDC constraints
set synth(input,upf_file)        "<PROJECT_ROOT>/power.upf"     ;# UPF power intent (optional, comment out if unused)
