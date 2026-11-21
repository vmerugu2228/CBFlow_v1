#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH_PNR with the open-source stack
# (Yosys → OpenROAD → KLayout GDS, tools in the cbflow-oss container)
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"       ;# e.g. opensky
set flow(type)                 "SYNTH_PNR"
set flow(design_name)          "gcd"        ;# must be in project(design_hierarchy)
set flow(run_name)             "oss_tm1"
set flow(run_type)             "hier"
set flow(test_mode)            "true"                 ;# "true" = dry run (no container)
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"

set synth_pnr(tool,name)       "openroad"             ;# selects SYNTH_PNR_openroad_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc
set synth_pnr(input,rtl_filelist)    "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/gcd.f"
set synth_pnr(input,rtl_format)      "verilog"
set synth_pnr(input,sdc_func_file)   "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/gcd.func.sdc"
set synth_pnr(input,upf_file)        "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/gcd.upf"

# Release tag this run publishes (consumed by the parent block / STA / PV)
set project(release,tag)       "OSS_v1"

# Hierarchical blocks only: children (from project(design_hierarchy)) come
# from their releases. One tag for all children, or per child:
#   set synth_pnr(input,blocks_release_tag)          "OSS_v1"
#   set synth_pnr(input,block,<child>,release_tag)   "<tag>"
#   set synth_pnr(input,block,<child>,dir)           "/path/to/release/dir"
# Floorplan for macro-integrating blocks (µm) and optional fixed macro spots:
#   set synth_pnr(oss,fp,die_area)       {0 0 2400 2400}
#   set synth_pnr(oss,macro,placement)   {u_child 100 100 R0}
