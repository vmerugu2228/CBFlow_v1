#!/usr/bin/env tclsh
# CBflow user_config — Denali PV on Siemens Calibre

set project(name)              "denali"

set flow(type)                 "PV"
set flow(design_name)          "tom"
set flow(run_name)             "calibre_demo"
set flow(run_type)             "hier"
set flow(test_mode)            "true"

set pv(tool,name)              "calibre"

set pv(input,netlist)          "/Users/vmerugu/projects/CBflow_clone/inputs/netlist.v"
set pv(input,def_file)         "/Users/vmerugu/projects/CBflow_clone/inputs/design.def"
set pv(input,gds)              "/Users/vmerugu/projects/CBflow_clone/inputs/design.gds"

set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
