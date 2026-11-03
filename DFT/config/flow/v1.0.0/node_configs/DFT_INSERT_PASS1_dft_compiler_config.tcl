#!/usr/bin/env tclsh
# DFT_INSERT_PASS1 — Synopsys DFT Compiler
# Scaffold only — owner-team fills tool-specific detail. Tessent is the primary
# Pass1 tool per owner spreadsheet ($MBIST_TOOL = tessent).

array set dft_insert_pass1 {
    tool,vendor   "synopsys"
    tool,name     "dft_compiler"
    tool,version  "v1.0.0"
    tool,args     "-no_gui"

    tap,tck_pin        "TCK"
    tap,tms_pin        "TMS"
    tap,tdi_pin        "TDI"
    tap,tdo_pin        "TDO"
    tap,trst_pin       "TRST_N"

    bscan,enabled      "auto"
    bscan,cell_template "BC_1"

    mbist,controller_type     "smart_serial"
    mbist,wrap_memories       true
    mbist,bist_clock_domain   "dft_clk"

    tpi,enabled               true
    tpi,coverage_target       99.0

    drc,level                 "strict"

    vgen,memory_test          true
    vgen,retention_test       true

    sim,write_data_dictionary true
    sim,write_icl_network     true

    write_design_import_script "ON"
}
