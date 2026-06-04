#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — LEC / Conformal (Cadence)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_LEC_conformal.tcl <workarea>/uc_LEC_conformal.tcl
#   cbflow workspace create --config uc_LEC_conformal.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)
set project(phase)             "P0"                   ;# Design phase: P0, P1, P2, P3

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "LEC"                  ;# Flow type (logic equivalence checking)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(run_type)             "hier"                 ;# Run type: hier or flat
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
set lec(tool,name)             "conformal"            ;# Cadence Conformal (vendor auto-resolves)

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set lec(input,netlist_golden)    "<PROJECT_ROOT>/netlist_golden.v"   ;# Golden reference netlist (pre-change)
set lec(input,netlist_revised)   "<PROJECT_ROOT>/netlist_revised.v"  ;# Revised netlist (post-change)
set lec(input,sdc_file)          "<PROJECT_ROOT>/func.sdc"           ;# SDC constraints for comparison
