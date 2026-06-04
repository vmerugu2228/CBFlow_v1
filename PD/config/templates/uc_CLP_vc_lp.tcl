#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — CLP / VC LP (Synopsys)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_CLP_vc_lp.tcl <workarea>/uc_CLP.tcl
#   cbflow workspace create --config uc_CLP.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)
set project(phase)             "P0"                   ;# Design phase: P0, P1, P2, P3

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "CLP"                  ;# Flow type (clock low power verification)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(run_type)             "hier"                 ;# Run type: hier or flat
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
# VC LP is the default tool for CLP — no tool,name needed.

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set clp(input,netlist)           "<PROJECT_ROOT>/netlist.v"          ;# Gate-level netlist
set clp(input,upf_file)          "<PROJECT_ROOT>/power.upf"         ;# UPF power intent specification
set clp(input,power_spec)        "<PROJECT_ROOT>/power_spec.upf"    ;# Power specification (optional)
set clp(input,reference_netlist) "<PROJECT_ROOT>/netlist_ref.v"     ;# Reference netlist for comparison (optional)
