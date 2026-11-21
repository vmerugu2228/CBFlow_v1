#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — PNR with the open-source stack (OpenROAD + KLayout)
# Consumes the SYNTH release (netlist / SDC / UPF) and the FP release
# (floorplan DEF) by tag; publishes <phase>_PNR_v<n> (GDS, abstract
# LEF, timing models, DEF, netlists, SPEF) for PV / STA / the parent block.
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "<project_name>"
set flow(type)                 "PNR"
set flow(design_name)          "<design_name>"
set flow(run_name)             "<run_name>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set pnr(tool,name)             "openroad"             ;# selects PNR_openroad_config.tcl

# Netlist + SDC + UPF from the SYNTH release (Pattern A — one knob);
# floorplan DEF from the FP release (Pattern B — per-input tag)
set pnr(input,release_tag)     "<phase>_SYNTH_v1"
set pnr(input,def_file_release_tag) "<phase>_FP_v1"

set project(release,tag)       "<phase>_PNR_v1"

