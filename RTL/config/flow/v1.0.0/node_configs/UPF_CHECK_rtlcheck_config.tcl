#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# UPF_CHECK — Open-source tool configuration (vendor opensource, tool rtlcheck)
# Sourced from UPF_CHECK_config.tcl when upf_check(tool,name) = rtlcheck.
# Command files: RTL/cmds/UPF_CHECK/opensource/rtlcheck/v1.0.0/
#
# Power intent of the RTL release (RTL_SPEC: rtl/<d>.f, upf/<d>.upf,
# spec/<d>.spec.yaml) checked against the elaborated RTL and the spec:
# domains and their elements, supply ports / nets / connections, primary
# supplies, port states, PST states, isolation on crossings out of switchable
# domains, domains / supplies vs the spec's power section (rtl_check.py
# upf-check — IEEE 1801 subset). Released as UPF_SIGNOFF: upf/<d>.upf (the
# checked UPF — handshake PNR,upf_from_check) + reports.
# ═══════════════════════════════════════════════════════════════════════════════

array set upf_check {
    tool,vendor   "opensource"
    tool,name     "rtlcheck"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {rtl1 upf1 spec1 init1 compile1 upf_parse1 upf_check1 upf_report1 waiver_apply1 signoff1 release_data1}
    dependencies,spec1          {}
    dependencies,init1          {rtl1 upf1 spec1}
    dependencies,waiver_apply1  {upf_report1}
    stage_types,spec1           "inputs"
    node_types,spec1            "inputs"
    node_descriptions,spec1     "Block spec (power section) from the RTL_SPEC release"
    runtime,timeout,spec1       10

    mandatory_user_inputs { upf_check(input,rtl) upf_check(input,upf) upf_check(input,spec) }
}
array unset upf_check *,waivers1

array set upf_check {
    oss,tool,init          "rtlcheck"
    oss,tool,compile       "rtlcheck"
    oss,tool,upf_parse     "rtlcheck"
    oss,tool,upf_check     "rtlcheck"
    oss,tool,upf_report    "rtlcheck"
    oss,tool,waiver_apply  "rtlcheck"
    oss,tool,signoff       "rtlcheck"
    oss,tool,release_data  "oss_tclsh"
}

array set upf_check {
    oss,top                       ""
    oss,waivers                   ""
    oss,signoff,fail_on_warning   true
}

set upf_check(required_inputs,init1)           "work/UPF_CHECK/rtl1/rtl work/UPF_CHECK/upf1/upf work/UPF_CHECK/spec1/spec"
set upf_check(mandatory_outputs,init1)         {sources.f stubs.v}
set upf_check(mandatory_outputs,compile1)      {design.json}
set upf_check(mandatory_outputs,upf_parse1)    {upf_parse.status}
set upf_check(mandatory_outputs,upf_check1)    {violations.csv}
set upf_check(mandatory_outputs,upf_report1)   {upf_report.status}
set upf_check(mandatory_outputs,waiver_apply1) {violations_final.csv}
set upf_check(mandatory_outputs,signoff1)      {signoff.status}
set upf_check(mandatory_outputs,release_data1) {release.manifest}

set upf_check(smartgrid,milestone) "UPF_SIGNOFF"
set upf_check(checklist,exit_node,UPF_SIGNOFF) signoff1
set upf_check(checklist,report)                      {work/UPF_CHECK/signoff1/reports/upf_signoff.rpt}
set upf_check(checklist,metric,upf_open_errors)      {Open errors\s*:\s*(\d+)}
set upf_check(checklist,metric,upf_open_warnings)    {Open warnings\s*:\s*(\d+)}
set upf_check(checklist,mandatory_files,UPF_SIGNOFF) {work/UPF_CHECK/signoff1/reports/upf_signoff.rpt
    work/UPF_CHECK/waiver_apply1/outputs/violations_final.csv}
