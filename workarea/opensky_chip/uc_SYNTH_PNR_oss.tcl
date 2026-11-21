#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH_PNR with the open-source stack
# (Yosys → OpenROAD → KLayout GDS, tools in the cbflow-oss container)
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"       ;# e.g. opensky
set flow(type)                 "SYNTH_PNR"
set flow(design_name)          "opensky_chip"        ;# must be in project(design_hierarchy)
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"                ;# "true" = dry run (no container)
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"

set synth_pnr(tool,name)       "openroad"             ;# selects SYNTH_PNR_openroad_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc
set synth_pnr(input,rtl_filelist)    "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.f"
set synth_pnr(input,rtl_format)      "verilog"
set synth_pnr(input,sdc_func_file)   "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.func.sdc"
set synth_pnr(input,upf_file)        "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.upf"   ;# IEEE 1801; OpenROAD reads its supported subset

# Release tag this run publishes (consumed by the parent block / STA / PV)
set project(release,tag)       "OSS_v1"

# Hierarchical blocks: children (project(design_hierarchy)) are taken from the
# library tag (project(lib_config_tag)). After each child's release:
#   cbflow flow library-manager add --tech <tech> --tag <tag> --category block \
#       --path <release,path>/<phase>/<child>/OSS_v1
# Floorplan for macro-integrating blocks (µm) and optional fixed macro spots:
#   set synth_pnr(oss,fp,die_area)       {0 0 2400 2400}
#   set synth_pnr(oss,macro,placement)   {u_child 100 100 R0}

# opensky_chip (DL1): ai_subsys (2000 x 1880) + ctrl_subsys (300 x 300) hard macros
# from library tag OSS0. Macro y on the 54.4 um rail pitch (snapped automatically).
set synth_pnr(oss,fp,die_area)      {0 0 2500 2050}
set synth_pnr(oss,macro,placement)  {u_ai_subsys 40 54.4 R0 u_ctrl_subsys 2120 544 R0}
