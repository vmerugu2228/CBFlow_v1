#!/usr/bin/env tclsh
# CBflow user_config — PV flow with new nettran stage (demo)

set project(name)              "bumblebee"

set flow(type)                 "PV"
set flow(design_name)          "cpu_core"
set flow(run_name)             "nettran_demo"
set flow(run_type)             "hier"
set flow(test_mode)            "true"

set pv(tool,name)              "icv"

set pv(input,netlist)          "/Users/vmerugu/projects/CBflow_clone/inputs/netlist.v"
set pv(input,def_file)         "/Users/vmerugu/projects/CBflow_clone/inputs/design.def"
set pv(input,gds)              "/Users/vmerugu/projects/CBflow_clone/inputs/design.gds"

set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
