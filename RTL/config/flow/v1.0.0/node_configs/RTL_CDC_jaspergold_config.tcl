#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_CDC — Cadence Jaspergold CDC tool overlay — SCAFFOLD                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    tool,vendor          "cadence"
    tool,name            "jaspergold"
    tool,version         "v1.0.0"
    tool,executable      "jg"
    tool,args            "-cdc -no_gui -batch"

    jaspergold,app             "CDC"
    jaspergold,parallel        "true"
    jaspergold,parallel_cores  4
    jaspergold,abort_on_fatal  "true"
    jaspergold,sync_depth      2
    jaspergold,glitch_check    "true"
}

array set rtl_cdc {
    cmd_files,init1          "init_jaspergold.tcl"
    cmd_files,compile1       "compile_jaspergold.tcl"
    cmd_files,cdc_setup1     "cdc_setup_jaspergold.tcl"
    cmd_files,cdc_analyze1   "cdc_analyze_jaspergold.tcl"
    cmd_files,cdc_report1    "cdc_report_jaspergold.tcl"
    cmd_files,waiver_apply1  "waiver_apply_jaspergold.tcl"
    cmd_files,signoff1       "signoff_jaspergold.tcl"
    cmd_files,release_data1  "release_data_jaspergold.tcl"
}
