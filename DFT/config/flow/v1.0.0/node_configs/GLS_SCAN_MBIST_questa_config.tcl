#!/usr/bin/env tclsh
# GLS_SCAN_MBIST — Mentor Questa
array set gls_scan_mbist {
    tool,vendor   "mentor"
    tool,name     "questa"
    tool,version  "v1.0.0"
    tool,args     "-64 -sv"
    sim,timescale "1ns/1ps"
}
