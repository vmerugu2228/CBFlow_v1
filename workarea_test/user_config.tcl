#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - SYNTH_PNR
# Generated template — edit all values before running
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "ravendrive"     ;# Your project name (must match config/project/<name>)
set project(phase)       "P0"                 ;# Design phase (P0, P1, etc.)
set flow(type)           "SYNTH_PNR"
set flow(design_name)    "cpu_core"      ;# Your design/block name
set flow(run_name)       "run0"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

# ─────────────────────────────────────────────────────────────────────────────────
# SYNTH_PNR Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# RTL Input
set synth_pnr(input,rtl_filelist)   "/Users/vmerugu/projects/CBflow_clone/rtl.list"              ;# RTL filelist (.f)

# Timing Constraints
set synth_pnr(input,sdc_func_file)  "/Users/vmerugu/projects/CBflow_clone/func.sdc"              ;# Functional mode SDC

# Floorplan (optional)
# set synth_pnr(input,def_file)       ""            ;# Floorplan DEF

# UPF (optional)
# set synth_pnr(input,upf_file)      ""             ;# Power intent UPF
