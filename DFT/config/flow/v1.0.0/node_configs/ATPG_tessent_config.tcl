#!/usr/bin/env tclsh
# ATPG — Mentor Tessent
array set atpg {
    tool,vendor       "mentor"
    tool,name         "tessent"
    tool,version      "v1.0.0"
    tool,args         "-shell"
    atpg,pattern_type "stuck_at transition path_delay"
    atpg,max_patterns 100000
}
