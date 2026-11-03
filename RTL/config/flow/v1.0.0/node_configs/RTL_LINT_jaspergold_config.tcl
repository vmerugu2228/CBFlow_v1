#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_LINT — Cadence Jaspergold (HAL app) tool overlay — SCAFFOLD            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Jaspergold HAL (High-Level Analysis) is Cadence's RTL lint analyzer.
# This overlay ships as a scaffold — the owner team fills in HAL-specific
# knobs when adopting Cadence as the primary lint tool for a project.

array set rtl_lint {
    tool,vendor          "cadence"
    tool,name            "jaspergold"
    tool,version         "v1.0.0"
    tool,executable      "jg"
    tool,args            "-superlint -no_gui -batch"

    jaspergold,app             "HAL"
    jaspergold,rule_pack       "lint_rtl"
    jaspergold,parallel        "true"
    jaspergold,parallel_cores  4
    jaspergold,abort_on_fatal  "true"
    jaspergold,waiver_mode     "project"
}

array set rtl_lint {
    cmd_files,init1          "init_jaspergold.tcl"
    cmd_files,compile1       "compile_jaspergold.tcl"
    cmd_files,lint1          "lint_jaspergold.tcl"
    cmd_files,waiver_apply1  "waiver_apply_jaspergold.tcl"
    cmd_files,report1        "report_jaspergold.tcl"
    cmd_files,release_data1  "release_data_jaspergold.tcl"
}
