#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_RDC — Cadence Jaspergold RDC tool overlay — SCAFFOLD                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    tool,vendor          "cadence"
    tool,name            "jaspergold"
    tool,version         "v1.0.0"
    tool,executable      "jg"
    tool,args            "-rdc -no_gui -batch"

    jaspergold,app             "RDC"
    jaspergold,parallel        "true"
    jaspergold,parallel_cores  4
    jaspergold,abort_on_fatal  "true"
    jaspergold,reset_sync_depth 2
}

array set rtl_rdc {
    cmd_files,init1          "init_jaspergold.tcl"
    cmd_files,compile1       "compile_jaspergold.tcl"
    cmd_files,rdc_setup1     "rdc_setup_jaspergold.tcl"
    cmd_files,rdc_analyze1   "rdc_analyze_jaspergold.tcl"
    cmd_files,rdc_report1    "rdc_report_jaspergold.tcl"
    cmd_files,waiver_apply1  "waiver_apply_jaspergold.tcl"
    cmd_files,signoff1       "signoff_jaspergold.tcl"
    cmd_files,release_data1  "release_data_jaspergold.tcl"
}
