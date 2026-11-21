#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — PV with the open-source stack (Magic DRC + Netgen LVS)
# Consumes the PNR release by tag (GDS + power-aware LVS netlist);
# publishes P0_PV_v<n> (DRC / LVS reports + verification summary).
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "PV"
set flow(design_name)          "gcd"
set flow(run_name)             "oss_r2"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set pv(tool,name)              "magic"                ;# selects PV_magic_config.tcl
set pv(input,release_tag)      "P0_PNR_v1"       ;# gds + netlist from the PNR release

set project(release,tag)       "P0_PV_v1"
