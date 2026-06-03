#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — PV / ICV (Synopsys)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_PV_icv.tcl <workarea>/uc_PV.tcl
#   cbflow workspace create --config uc_PV.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)
set project(phase)             "P0"                   ;# Design phase: P0, P1, P2, P3

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "PV"                   ;# Flow type (physical verification)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
# ICV is the default tool for PV — no tool,name needed.

# ── Inputs ───────────────────────────────────────────────────────────────────
set pv(input,gds)                "<PROJECT_ROOT>/layout.gds"        ;# GDS layout data
set pv(input,netlist)            "<PROJECT_ROOT>/netlist.v"         ;# Gate-level netlist (for LVS)
set pv(input,def_file)           "<PROJECT_ROOT>/floorplan.def"    ;# DEF floorplan
