#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "FCFP"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_fcfp"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set fcfp(input,netlist)        "/Users/vmerugu/projects/CBflow_clone/netlist.v"

