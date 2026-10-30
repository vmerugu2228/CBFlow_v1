#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - ECO
# Generated: project=my_project  flow=ECO
# Phase is taken from project(current_phase) in the my_project config —
# override there, not here.
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "my_project"
set flow(type)           "ECO"
set flow(design_name)    "my_design"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# ECO Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
set eco(eco,type)              "timing"     ;# timing | functional
set eco(input,from_block)      "chip_finish" ;# Block to ECO from

# For functional ECO
# set eco(input,eco_verilog)   ""           ;# Modified netlist

# For manual ECO changes
# set eco(input,change_file)   ""           ;# Manual ECO change script
