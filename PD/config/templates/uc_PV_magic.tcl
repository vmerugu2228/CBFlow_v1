#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — PV with the open-source stack (Magic DRC + Netgen LVS)
# Consumes the PNR release by tag (GDS + power-aware LVS netlist);
# publishes <phase>_PV_v<n> (DRC / LVS reports + verification summary).
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "<project_name>"
set flow(type)                 "PV"
set flow(design_name)          "<design_name>"
set flow(run_name)             "<run_name>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set pv(tool,name)              "magic"                ;# selects PV_magic_config.tcl
set pv(input,release_tag)      "<phase>_PNR_v1"       ;# gds + netlist from the PNR release

set project(release,tag)       "<phase>_PV_v1"
