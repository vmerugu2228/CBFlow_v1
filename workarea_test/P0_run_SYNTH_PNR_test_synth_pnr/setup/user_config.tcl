#!/usr/bin/env tclsh
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "SYNTH_PNR"
set flow(design_name)    "cpu_core"
set flow(run_name)       "test_synth_pnr"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

set synth_pnr(input,rtl_filelist)   "/Users/vmerugu/projects/CBflow_clone/rtl.list"
set synth_pnr(input,sdc_func_file)  "/Users/vmerugu/projects/CBflow_clone/func.sdc"
set synth_pnr(input,upf_file)       "/Users/vmerugu/projects/CBflow_clone/power.upf"
set synth_pnr(input,rtl_format)     "sverilog"

