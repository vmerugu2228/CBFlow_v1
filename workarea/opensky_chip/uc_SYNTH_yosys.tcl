#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH with the open-source stack (Yosys, cbflow-oss)
# Publishes the synthesis release consumed by PNR: P0_SYNTH_v<n>
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "SYNTH"
set flow(design_name)          "opensky_chip"        ;# must be in project(design_hierarchy)
set flow(run_name)             "oss_u10"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set synth(tool,name)           "yosys"                ;# selects SYNTH_yosys_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc / <design>.upf
set synth(input,rtl_filelist)  "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.f"
set synth(input,rtl_format)    "verilog"
set synth(input,sdc_func_file) "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.func.sdc"
set synth(input,upf_file)      "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/opensky_chip/opensky_chip.upf"

set project(release,tag)       "P0_SYNTH_v1"

# Hierarchical blocks: children (project(design_hierarchy)) are read as
# blackboxes from the library tag — integrate each child's PNR release first:
#   cbflow flow library-manager add --tech <tech> --tag <lib_tag> --category block \
#       --path <release,path>/P0/<child>/P0_PNR_v<n>
