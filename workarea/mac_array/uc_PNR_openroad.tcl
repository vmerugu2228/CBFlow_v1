#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — PNR with the open-source stack (OpenROAD + KLayout)
# Consumes the SYNTH release by tag; publishes P0_PNR_v<n> (GDS, abstract
# LEF, timing models, DEF, netlists, SPEF) for PV / STA / the parent block.
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "PNR"
set flow(design_name)          "mac_array"
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set pnr(tool,name)             "openroad"             ;# selects PNR_openroad_config.tcl

# Netlist + SDC + UPF from the SYNTH release (Pattern A — one knob)
set pnr(input,release_tag)     "P0_SYNTH_v1"

set project(release,tag)       "P0_PNR_v1"

# Blocks that integrate hard macros: floorplan (um) and optional fixed spots
#   set pnr(oss,fp,die_area)       {0 0 2400 2400}
#   set pnr(oss,macro,placement)   {u_child 100 100 R0}
