#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "FP"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_fp"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set fp(input,netlist)          "/Users/vmerugu/projects/CBflow_clone/netlist.v"
set fp(input,sdc_func_file)    "/Users/vmerugu/projects/CBflow_clone/func.sdc"

