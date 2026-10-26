#!/usr/bin/env tclsh
# DFT_INSERT — Synopsys DFT Compiler
array set dft_insert {
    tool,vendor   "synopsys"
    tool,name     "dft_compiler"
    tool,version  "v1.0.0"
    tool,args     "-no_gui"

    mbist,controller_type     "smart_serial"
    mbist,wrap_memories       true
    mbist,bist_clock_domain   "dft_clk"

    occ,clock_domains         "auto"
    occ,scan_enable_pin       "scan_en"
    occ,test_clock_pin        "test_clk"

    edt,enable                true
    edt,compression_ratio     100
    edt,input_channels        8
    edt,output_channels       8

    verify,drc_level          "strict"
    verify,coverage_threshold 98.0
}
