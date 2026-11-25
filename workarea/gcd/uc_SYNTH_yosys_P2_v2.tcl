#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH with the open-source stack (Yosys, cbflow-oss)
# Publishes the synthesis release consumed by PNR: P0_SYNTH_v<n>
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "SYNTH"
set flow(design_name)          "gcd"        ;# must be in project(design_hierarchy)
set flow(run_name)             "p2_scandef"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"

set synth(tool,name)           "yosys"                ;# selects SYNTH_yosys_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc / <design>.upf
set synth(input,rtl_filelist)  "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P2/gcd.f"
set synth(input,rtl_format)    "verilog"
set synth(input,sdc_func_file) "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/gcd.func.sdc"
set synth(input,upf_file)      "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/gcd.upf"

set project(release,tag)       "P2_SYNTH_v2"

# Hierarchical blocks: children (project(design_hierarchy)) are read as
# blackboxes from the library tag — integrate each child's PNR release first:
#   cbflow flow library-manager add --tech <tech> --tag <lib_tag> --category block \
#       --path <release,path>/P0/<child>/P0_PNR_v<n>
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
