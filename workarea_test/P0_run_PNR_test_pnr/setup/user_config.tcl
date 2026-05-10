#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "PNR"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_pnr"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set pnr(input,netlist)         "/Users/vmerugu/projects/CBflow_clone/netlist.v"
set pnr(input,sdc_func_file)   "/Users/vmerugu/projects/CBflow_clone/func.sdc"
set pnr(input,def_file)        "/Users/vmerugu/projects/CBflow_clone/floorplan.def"

