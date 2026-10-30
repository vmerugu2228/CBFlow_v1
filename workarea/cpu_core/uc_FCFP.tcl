#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - FCFP
# Generated: project=my_project  flow=FCFP
# Phase is taken from project(current_phase) in the my_project config —
# override there, not here.
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "my_project"
set flow(type)           "FCFP"
set flow(design_name)    "my_design"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# FCFP Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist
set fcfp(input,netlist)        ""           ;# Gate-level netlist or RTL filelist

# Timing Constraints
set fcfp(input,sdc_func_file)  ""           ;# Functional mode SDC
