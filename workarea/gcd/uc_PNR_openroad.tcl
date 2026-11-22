#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — PNR with the open-source stack (OpenROAD + KLayout)
# Consumes the SYNTH release by tag; publishes P0_PNR_v<n> (GDS, abstract
# LEF, timing models, DEF, netlists, SPEF) for PV / STA / the parent block.
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "PNR"
set flow(design_name)          "gcd"
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"

set pnr(tool,name)             "openroad"             ;# selects PNR_openroad_config.tcl

# Netlist + SDC + UPF from the SYNTH release (Pattern A — one knob)
set pnr(input,release_tag)     "P0_SYNTH_v1"
set pnr(input,def_file_release_tag) "P0_FP_v1"   ;# floorplan DEF from the FP release

set project(release,tag)       "P0_PNR_v1"

# ── Placement density (per block; overrides PNR_openroad_config.tcl) ────────
set pnr(oss,place,density)      0.20
