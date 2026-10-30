#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - FP
# Generated: project=my_project  flow=FP
# Phase is taken from project(current_phase) in the my_project config —
# override there, not here.
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "my_project"
set flow(type)           "FP"
set flow(design_name)    "my_design"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# FP Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist
set fp(input,netlist)          ""           ;# Gate-level netlist (.v)

# Timing Constraints
set fp(input,sdc_func_file)    ""           ;# Functional mode SDC

# UPF (optional)
# set fp(input,upf_file)        ""          ;# Power intent UPF
