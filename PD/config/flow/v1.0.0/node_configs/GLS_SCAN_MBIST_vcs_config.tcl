#!/usr/bin/env tclsh
# GLS_SCAN_MBIST — Synopsys VCS
array set gls_scan_mbist {
    tool,vendor   "synopsys"
    tool,name     "vcs"
    tool,version  "v1.0.0"
    tool,args     "-full64 -sverilog +vcs+lic+wait"
    sim,timescale "1ns/1ps"
}
