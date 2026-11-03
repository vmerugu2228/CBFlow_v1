#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  UPF_CHECK — Synopsys VC-LP tool overlay                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    tool,vendor          "synopsys"
    tool,name            "vc_lp"
    tool,version         "v1.0.0"
    tool,executable      "vc_static_shell"
    tool,args            "-batch"

    vc_lp,mode              "rtl"
    vc_lp,enable_structural "true"
    vc_lp,enable_functional "true"
    vc_lp,abort_on_fatal    "true"
    vc_lp,waiver_mode       "project"
    vc_lp,upf_version       "2.1"

    vc_lp,iso_check         "true"
    vc_lp,retention_check   "true"
    vc_lp,level_shifter_check "true"
    vc_lp,power_switch_check  "true"
}

array set upf_check {
    cmd_files,init1          "init_vc_lp.tcl"
    cmd_files,compile1       "compile_vc_lp.tcl"
    cmd_files,upf_parse1     "upf_parse_vc_lp.tcl"
    cmd_files,upf_check1     "upf_check_vc_lp.tcl"
    cmd_files,upf_report1    "upf_report_vc_lp.tcl"
    cmd_files,waiver_apply1  "waiver_apply_vc_lp.tcl"
    cmd_files,signoff1       "signoff_vc_lp.tcl"
    cmd_files,release_data1  "release_data_vc_lp.tcl"
}
