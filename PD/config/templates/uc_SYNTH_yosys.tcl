#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — SYNTH with the open-source stack (Yosys, cbflow-oss)
# Publishes the synthesis release consumed by PNR: <phase>_SYNTH_v<n>
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "<project_name>"
set flow(type)                 "SYNTH"
set flow(design_name)          "<design_name>"        ;# must be in project(design_hierarchy)
set flow(run_name)             "<run_name>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set synth(tool,name)           "yosys"                ;# selects SYNTH_yosys_config.tcl

# Inputs — named <design>.f / <design>.<mode>.sdc / <design>.upf
set synth(input,rtl_filelist)  "<PROJECT_ROOT>/<design_name>.f"
set synth(input,rtl_format)    "verilog"
set synth(input,sdc_func_file) "<PROJECT_ROOT>/<design_name>.func.sdc"
set synth(input,upf_file)      "<PROJECT_ROOT>/<design_name>.upf"

set project(release,tag)       "<phase>_SYNTH_v1"

# Hierarchical blocks: children (project(design_hierarchy)) are read as
# blackboxes from the library tag — integrate each child's PNR release first:
#   cbflow flow library-manager add --tech <tech> --tag <lib_tag> --category block \
#       --path <release,path>/<phase>/<child>/<phase>_PNR_v<n>
