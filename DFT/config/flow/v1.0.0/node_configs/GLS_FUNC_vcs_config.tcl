#!/usr/bin/env tclsh
# GLS_FUNC — Synopsys VCS
array set gls_func {
    tool,vendor   "synopsys"
    tool,name     "vcs"
    tool,version  "v1.0.0"
    tool,args     "-full64 -sverilog +vcs+lic+wait"
    sim,timescale "1ns/1ps"
}
