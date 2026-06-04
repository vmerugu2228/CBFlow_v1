#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — PNR / Innovus (Cadence)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_PNR_innovus.tcl <workarea>/uc_PNR_innovus.tcl
#   cbflow workspace create --config uc_PNR_innovus.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)
set project(phase)             "P0"                   ;# Design phase: P0, P1, P2, P3

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "PNR"                  ;# Flow type (place & route only)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(run_type)             "flat"                 ;# Run type: hier or flat
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
set pnr(tool,name)             "innovus"              ;# Cadence Innovus (vendor auto-resolves)

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set pnr(input,netlist)           "<PROJECT_ROOT>/netlist.v"      ;# Gate-level netlist from synthesis
set pnr(input,sdc_func_file)    "<PROJECT_ROOT>/func.sdc"       ;# Functional mode SDC constraints
set pnr(input,def_file)         "<PROJECT_ROOT>/design.def"     ;# DEF floorplan
set pnr(input,upf_file)         "<PROJECT_ROOT>/power.upf"      ;# UPF power intent (optional, comment out if unused)
