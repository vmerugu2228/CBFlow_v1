#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - SYNTH_PNR
# Generated template — edit all values before running
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "my_project"     ;# Your project name (must match config/project/<name>)
set project(phase)       "LC1"                 ;# Design phase (P0, P1, etc.)
set flow(type)           "SYNTH_PNR"
set flow(design_name)    "my_design"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# SYNTH_PNR Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# RTL Input
set synth_pnr(input,rtl_filelist)   ""              ;# RTL filelist (.f)
set synth_pnr(input,rtl_format)     "sverilog"      ;# sverilog | verilog | vhdl

# Timing Constraints
set synth_pnr(input,sdc_func_file)  ""              ;# Functional mode SDC

# UPF Power Intent
set synth_pnr(input,upf_file)      ""              ;# Power intent UPF (required)

# Floorplan (optional)
# set synth_pnr(input,def_file)       ""            ;# Floorplan DEF

