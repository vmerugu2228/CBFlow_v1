#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - POPT
# Generated: project=my_project  flow=POPT
# Phase is taken from project(current_phase) in the my_project config —
# override there, not here.
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "my_project"
set flow(type)           "POPT"
set flow(design_name)    "my_design"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# POPT Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
set popt(input,netlist)       ""           ;# Input netlist
set popt(input,sdc_func_file) ""           ;# Functional mode SDC
