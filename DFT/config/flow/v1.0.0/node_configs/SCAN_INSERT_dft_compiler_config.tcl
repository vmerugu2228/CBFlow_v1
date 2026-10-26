#!/usr/bin/env tclsh
# SCAN_INSERT — Synopsys DFT Compiler
array set scan_insert {
    tool,vendor       "synopsys"
    tool,name         "dft_compiler"
    tool,version      "v1.0.0"
    tool,args         "-no_gui"
    scan,chain_count  16
    scan,style        "multiplexed_flip_flop"
}
