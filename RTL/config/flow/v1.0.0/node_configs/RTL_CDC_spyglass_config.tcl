#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_CDC — Synopsys Spyglass CDC tool overlay                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    tool,vendor          "synopsys"
    tool,name            "spyglass"
    tool,version         "v1.0.0"
    tool,executable      "spyglass"
    tool,args            "-shell -tcl"

    spyglass,goal              "cdc/cdc_verify"
    spyglass,parallel          "true"
    spyglass,parallel_cores    4
    spyglass,enable_structural "true"
    spyglass,enable_functional "true"
    spyglass,abort_on_fatal    "true"
    spyglass,abort_on_error    "false"
    spyglass,waiver_mode       "project"
    spyglass,policy_file       ""

    spyglass,sync_depth_default 2
    spyglass,glitch_check       "true"
    spyglass,data_hold_check    "true"
    spyglass,sync_cell_library  ""
}

array set rtl_cdc {
    cmd_files,init1          "init_spyglass.tcl"
    cmd_files,compile1       "compile_spyglass.tcl"
    cmd_files,cdc_setup1     "cdc_setup_spyglass.tcl"
    cmd_files,cdc_analyze1   "cdc_analyze_spyglass.tcl"
    cmd_files,cdc_report1    "cdc_report_spyglass.tcl"
    cmd_files,waiver_apply1  "waiver_apply_spyglass.tcl"
    cmd_files,signoff1       "signoff_spyglass.tcl"
    cmd_files,release_data1  "release_data_spyglass.tcl"
}
