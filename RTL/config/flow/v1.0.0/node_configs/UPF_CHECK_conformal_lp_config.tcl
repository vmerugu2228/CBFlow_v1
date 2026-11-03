#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  UPF_CHECK — Cadence Conformal LP tool overlay — SCAFFOLD                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    tool,vendor          "cadence"
    tool,name            "conformal_lp"
    tool,version         "v1.0.0"
    tool,executable      "lec"
    tool,args            "-xl -nogui -dofile"

    conformal_lp,mode              "rtl"
    conformal_lp,enable_structural "true"
    conformal_lp,enable_functional "true"
    conformal_lp,abort_on_fatal    "true"
    conformal_lp,upf_version       "2.1"
}

array set upf_check {
    cmd_files,init1          "init_conformal_lp.tcl"
    cmd_files,compile1       "compile_conformal_lp.tcl"
    cmd_files,upf_parse1     "upf_parse_conformal_lp.tcl"
    cmd_files,upf_check1     "upf_check_conformal_lp.tcl"
    cmd_files,upf_report1    "upf_report_conformal_lp.tcl"
    cmd_files,waiver_apply1  "waiver_apply_conformal_lp.tcl"
    cmd_files,signoff1       "signoff_conformal_lp.tcl"
    cmd_files,release_data1  "release_data_conformal_lp.tcl"
}
