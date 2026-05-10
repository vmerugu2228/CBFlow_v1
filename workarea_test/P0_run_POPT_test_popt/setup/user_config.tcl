#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "POPT"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_popt"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set popt(input,netlist)        "/Users/vmerugu/projects/CBflow_clone/netlist.v"
set popt(input,sdc_func_file)  "/Users/vmerugu/projects/CBflow_clone/func.sdc"

