#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — FP (floorplan) with the open-source stack (OpenROAD)
# Consumes the SYNTH release by tag; builds die / rows / tracks, places child
# hard macros, IO pins, well taps, power intent + power grid; publishes
# P0_FP_v<n> (DEF, db, netlist, SDC, UPF) for PNR (milestone FP_EXIT).
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "FP"
set flow(design_name)          "ai_subsys"
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set fp(tool,name)              "openroad"             ;# selects FP_openroad_config.tcl

# Netlist + SDC + UPF from the SYNTH release (Pattern A — one knob)
set fp(input,release_tag)      "P0_SYNTH_v1"

set project(release,tag)       "P0_FP_v1"

# Floorplan (um) and fixed hard-macro spots
# set fp(oss,fp,die_area)      {x0 y0 x1 y1}   ;# fixed size instead of utilization
# Floorplan: mac_array abutting the core bottom edge (the lowest a macro may sit;
# the 10.88 um margin below holds no rows) at the left core edge,
# filling the core width; hard placement blockages left / right / bottom of it
# (fp(oss,macro,blockage_sides)) so standard cells sit only in the logic band
# above it; IO pins on the top edge. Die (set by chain_ai_p1.sh from the
# released mac_array abstract):
#   x1 = 10.12 margin + W + 10.12 margin;  y1 = 10.88 + H + 500 logic band + 10.88
set fp(oss,fp,die_area)         {0 0 3622.5 4124}
set fp(oss,macro,placement)     {u_mac_array 10.12 10.88 R0}
set fp(oss,macro,blockage_sides) {left right bottom}
set fp(oss,pins,region)         top:*

# ── Floorplan sizing (per block; overrides FP_openroad_config.tcl) ──────────
# core_utilization = standard-cell utilization %; with child macros the core is
# macro area + std-cell area / util. Set fp(oss,fp,die_area) to fix the size.
set fp(oss,fp,core_utilization) 10
