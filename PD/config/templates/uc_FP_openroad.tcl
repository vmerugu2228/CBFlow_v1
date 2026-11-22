#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — FP (floorplan) with the open-source stack (OpenROAD)
# Consumes the SYNTH release by tag; builds die / rows / tracks, places child
# hard macros, IO pins, well taps, power intent + power grid; publishes
# FP_EXIT (DEF, db, netlist, SDC, UPF) for PNR — release tag = exit name.
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "<project_name>"
set flow(type)                 "FP"
set flow(design_name)          "<design_name>"
set flow(run_name)             "<run_name>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set fp(tool,name)              "openroad"             ;# selects FP_openroad_config.tcl

# Netlist + SDC + UPF from the SYNTH release (Pattern A — one knob)
set fp(input,release_tag)      "<phase>_SYNTH_v1"

# Release tag defaults to the exit name (FP_EXIT); set it only to override:
# set project(release,tag)     "<custom_tag>"

# Blocks that integrate hard macros: floorplan (um) and optional fixed spots
#   set fp(oss,fp,die_area)        {0 0 2400 2400}
#   set fp(oss,macro,placement)    {u_child 100 100 R0}

# Floorplan sizing — per block (defaults in FP_openroad_config.tcl):
#   core_utilization = standard-cell utilization %; with child macros the core
#   is macro area + std-cell area / util. die_area fixes the size instead.
# set fp(oss,fp,core_utilization) 10
# set fp(oss,fp,die_area)         {0 0 <x1> <y1>}
# set fp(oss,macro,placement)     {<inst> <x> <y> R0}
