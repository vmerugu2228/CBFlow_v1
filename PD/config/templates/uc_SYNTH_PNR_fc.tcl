#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — SYNTH_PNR / Fusion Compiler (Synopsys)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_SYNTH_PNR_fc.tcl <workarea>/uc_SYNTH_PNR.tcl
#   cbflow workspace create --config uc_SYNTH_PNR.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "SYNTH_PNR"            ;# Flow type (synthesis + place & route)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(run_type)             "hier"                 ;# Run type: hier or flat
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
# FC (Fusion Compiler) is the default tool for SYNTH_PNR — no tool,name needed.

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set synth_pnr(input,rtl_filelist)    "<PROJECT_ROOT>/rtl.list"       ;# RTL file list (one file per line)
set synth_pnr(input,rtl_format)      "sverilog"                      ;# RTL format: verilog, sverilog, vhdl
set synth_pnr(input,sdc_func_file)   "<PROJECT_ROOT>/func.sdc"      ;# Functional mode SDC constraints
set synth_pnr(input,upf_file)        "<PROJECT_ROOT>/power.upf"     ;# UPF power intent (optional, comment out if unused)
