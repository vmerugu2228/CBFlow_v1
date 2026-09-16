#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — CLP / Conformal LP (Cadence)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_CLP_conformal_lp.tcl <workarea>/uc_CLP_conformal_lp.tcl
#   cbflow workspace create --config uc_CLP_conformal_lp.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "CLP"                  ;# Flow type (clock low power verification)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
set clp(tool,name)             "conformal_lp"         ;# Cadence Conformal LP (vendor auto-resolves)

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set clp(input,netlist)           "<PROJECT_ROOT>/netlist.v"          ;# Gate-level netlist
set clp(input,upf_file)          "<PROJECT_ROOT>/power.upf"         ;# UPF power intent specification
