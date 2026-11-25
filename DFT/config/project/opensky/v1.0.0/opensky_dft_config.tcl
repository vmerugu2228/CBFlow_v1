#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — opensky
# DFT layer (discipline overlay, sourced after the global identity file)
#
# Open-source DFT (vendor opensource): SYNTH inserts the scan chains
# (project(dft,enable|max_chain_length|clock_mixing|scan_enable_pattern) in
# the global opensky_config.tcl); SCAN_INSERT signs the scan structure off,
# ATPG (Fault cut + Atalanta) generates stuck-at patterns, GLS_FUNC /
# GLS_SCAN_MBIST simulate the gate-level netlist (iverilog).
# Project-wide keys (workarea_path, lib_root, release,path, lib tag) come from
# the PD overlay opensky_pd_config.tcl.
# =============================================================================

# ── Scan ports (globs on the top-level port names) ──────────────────────────
# The scan inserter (OpenROAD DFT) adds scan_in_<n> / scan_enable_<n>; a chain
# ends on scan_out_<n> or, when a flop already drives an output port, on that
# functional output (the tracer finds it).
set project(dft,scan_in_pattern)   scan_in_*
set project(dft,scan_out_pattern)  scan_out_*

# ── ATPG sign-off targets (stuck-at) ─────────────────────────────────────────
# test coverage = detected / (all faults - ATPG-proven redundant);
# fault coverage = detected / all faults (collapsed, Atalanta).
set project(dft,atpg,test_coverage_min)   95.0
set project(dft,atpg,fault_coverage_min)  90.0
