#!/usr/bin/env tclsh
# DFT_INSERT_PASS3 — Synopsys DFT Compiler (scaffold)
array set dft_insert_pass3 {
    tool,vendor   "synopsys"
    tool,name     "dft_compiler"
    tool,version  "v1.0.0"
    tool,args     "-no_gui"

    edt,enable             true
    edt,compression_ratio  100
    edt,input_channels     8
    edt,output_channels    8

    occ,enable             true
    occ,clock_domains      "auto"
    occ,at_speed           true

    ctrl_points,enabled    true

    drc,level              "strict"
    drc,optimize_enabled   true

    vgen,enabled           true
}
