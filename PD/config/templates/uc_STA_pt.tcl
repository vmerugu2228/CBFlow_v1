#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow User Config Template — STA / PrimeTime (Synopsys)
# ═══════════════════════════════════════════════════════════════════════════════
# Copy this file to your workarea and update paths before creating a run:
#   cp $FLOW_DIR/config/templates/uc_STA_pt.tcl <workarea>/uc_STA.tcl
#   cbflow workspace create --config uc_STA.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ── Project ──────────────────────────────────────────────────────────────────
set project(name)              "<project_name>"       ;# Project name (must match config/project/<name>)

# ── Flow ─────────────────────────────────────────────────────────────────────
set flow(type)                 "STA"                  ;# Flow type (static timing analysis)
set flow(design_name)          "<design_name>"        ;# Design/block name
set flow(run_name)             "<run_name>"           ;# Run identifier (unique per design)
set flow(run_type)             "hier"                 ;# Run type: hier or flat
set flow(test_mode)            "false"                ;# Set "true" for dry run without EDA tools

# ── Tool ─────────────────────────────────────────────────────────────────────
# PT (PrimeTime) is the default tool for STA — no tool,name needed.

# ── MMMC Scenarios (optional) ────────────────────────────────────────────────
# Uncomment to override auto-generated MMMC scenarios:
# set sta(mmmc,scenario_set)      "custom"                                  ;# Use custom scenario selection
# set sta(mmmc,setup_scenarios)   "func_ss_0p76v_rcmax_150c"               ;# Setup analysis scenarios
# set sta(mmmc,hold_scenarios)    "func_ff_0p84v_rcmin_m40c"               ;# Hold analysis scenarios

# ── Execution ──
set flow(use_lsf)       "false"              ;# Set "true" to submit via LSF (bsub)
set flow(use_xterm)     "false"              ;# Set "true" to launch in xterm

# ── Inputs ───────────────────────────────────────────────────────────────────
set sta(input,netlist)           "<PROJECT_ROOT>/netlist.v"                  ;# Gate-level netlist
set sta(input,def_file)          "<PROJECT_ROOT>/design.def"                ;# DEF floorplan/placement
set sta(input,sdc,func)          "<PROJECT_ROOT>/func.sdc"                  ;# Functional mode SDC constraints
set sta(input,sdc,test)          "<PROJECT_ROOT>/test.sdc"                  ;# Test mode SDC constraints (optional)

# ── Alternative: Input from prior run ────────────────────────────────────────
# Instead of individual paths, point to a completed SYNTH_PNR run:
# set sta(input,from_run)        "<PROJECT_ROOT>/workarea/<design>/P0_run_SYNTH_PNR_<name>"
