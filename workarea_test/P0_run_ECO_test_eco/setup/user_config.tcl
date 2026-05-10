#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "ECO"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_eco"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set eco(eco,type)              "timing"
set eco(input,netlist)         "/Users/vmerugu/projects/CBflow_clone/netlist.v"

