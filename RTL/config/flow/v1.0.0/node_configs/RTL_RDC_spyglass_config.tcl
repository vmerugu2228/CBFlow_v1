#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_RDC — Synopsys Spyglass RDC tool overlay                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    tool,vendor          "synopsys"
    tool,name            "spyglass"
    tool,version         "v1.0.0"
    tool,executable      "spyglass"
    tool,args            "-shell -tcl"

    spyglass,goal              "rdc/rdc_verify"
    spyglass,parallel          "true"
    spyglass,parallel_cores    4
    spyglass,enable_structural "true"
    spyglass,enable_functional "true"
    spyglass,abort_on_fatal    "true"
    spyglass,waiver_mode       "project"

    spyglass,reset_tree_check  "true"
    spyglass,reset_sync_depth  2
}

array set rtl_rdc {
    cmd_files,init1          "init_spyglass.tcl"
    cmd_files,compile1       "compile_spyglass.tcl"
    cmd_files,rdc_setup1     "rdc_setup_spyglass.tcl"
    cmd_files,rdc_analyze1   "rdc_analyze_spyglass.tcl"
    cmd_files,rdc_report1    "rdc_report_spyglass.tcl"
    cmd_files,waiver_apply1  "waiver_apply_spyglass.tcl"
    cmd_files,signoff1       "signoff_spyglass.tcl"
    cmd_files,release_data1  "release_data_spyglass.tcl"
}
