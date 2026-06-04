#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — EMIR / RedHawk (Synopsys)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_EMIR_redhawk.tcl <workarea>/uc_EMIR.tcl
#   cbflow workspace create --config uc_EMIR.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)
set project(phase)             "P0"                   ;# Design phase: P0, P1, P2, P3

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "EMIR"                 ;# Flow type (electromigration & IR drop analysis)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
# RedHawk is the default tool for EMIR — no tool,name needed.

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set emir(input,netlist)          "<PROJECT_ROOT>/netlist.v"          ;# Gate-level netlist
set emir(input,def_file)         "<PROJECT_ROOT>/design.def"        ;# DEF floorplan/placement
set emir(input,spef)             "<PROJECT_ROOT>/design.spef"       ;# SPEF parasitic data
