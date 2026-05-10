#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "SYNTH"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_synth"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set synth(input,rtl_filelist)   "/Users/vmerugu/projects/CBflow_clone/rtl.list"
set synth(input,sdc_func_file)  "/Users/vmerugu/projects/CBflow_clone/func.sdc"
set synth(input,rtl_format)     "sverilog"

