#!/usr/bin/env tclsh
# ATPG — Synopsys TestMAX
array set atpg {
    tool,vendor       "synopsys"
    tool,name         "testmax"
    tool,version      "v1.0.0"
    tool,args         "-shell"
    atpg,pattern_type "stuck_at transition"
    atpg,max_patterns 100000
}
