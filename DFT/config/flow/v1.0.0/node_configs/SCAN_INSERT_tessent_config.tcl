#!/usr/bin/env tclsh
# SCAN_INSERT — Mentor Tessent
array set scan_insert {
    tool,vendor       "mentor"
    tool,name         "tessent"
    tool,version      "v1.0.0"
    tool,args         "-shell"
    scan,chain_count  16
    scan,clock_domain_aware true
}
