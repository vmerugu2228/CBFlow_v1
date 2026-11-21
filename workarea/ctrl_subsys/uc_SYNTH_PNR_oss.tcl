#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH_PNR with the open-source stack
# (Yosys → OpenROAD → KLayout GDS, tools in the cbflow-oss container)
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"       ;# e.g. opensky
set flow(type)                 "SYNTH_PNR"
set flow(design_name)          "ctrl_subsys"        ;# must be in project(design_hierarchy)
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"                ;# "true" = dry run (no container)
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"

set synth_pnr(tool,name)       "openroad"             ;# selects SYNTH_PNR_openroad_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc
set synth_pnr(input,rtl_filelist)    "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/ctrl_subsys/ctrl_subsys.f"
set synth_pnr(input,rtl_format)      "verilog"
set synth_pnr(input,sdc_func_file)   "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/ctrl_subsys/ctrl_subsys.func.sdc"
set synth_pnr(input,upf_file)        "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/ctrl_subsys/ctrl_subsys.upf"   ;# IEEE 1801; OpenROAD reads its supported subset

# Release tag this run publishes (consumed by the parent block / STA / PV)
set project(release,tag)       "OSS_v1"

# Hierarchical blocks: children (project(design_hierarchy)) are taken from the
# library tag (project(lib_config_tag)). After each child's release:
#   cbflow flow library-manager add --tech <tech> --tag <tag> --category block \
#       --path <release,path>/<phase>/<child>/OSS_v1
# Floorplan for macro-integrating blocks (µm) and optional fixed macro spots:
#   set synth_pnr(oss,fp,die_area)       {0 0 2400 2400}
#   set synth_pnr(oss,macro,placement)   {u_child 100 100 R0}

# ctrl_subsys (DL2): gcd (DL3) hard macro from library tag OSS0
set synth_pnr(oss,fp,die_area)      {0 0 300 300}
set synth_pnr(oss,macro,placement)  {u_gcd 150 120 R0}
