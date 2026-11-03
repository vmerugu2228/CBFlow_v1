#!/usr/bin/env tclsh
# DFT_INSERT_PASS2 — Synopsys DFT Compiler (scaffold)
array set dft_insert_pass2 {
    tool,vendor   "synopsys"
    tool,name     "dft_compiler"
    tool,version  "v1.0.0"
    tool,args     "-no_gui"

    tdr,enabled           true
    tdr,data_width        32

    dft_signals,enabled   true
    sri,enabled           true

    vgen,enabled          false
    sim,enabled           false
    drc,level             "strict"
}
