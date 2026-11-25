#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# RTL_LINT — Open-source tool configuration (vendor opensource, tool verilator)
# Sourced from RTL_LINT_config.tcl when rtl_lint(tool,name) = verilator.
# Command files: RTL/cmds/RTL_LINT/opensource/verilator/v1.0.0/
#
# Lint of the RTL release (the RTL_SPEC filelist, handshake RTL_LINT,rtl):
#   compile  slang elaboration (IEEE 1800 front end — errors / warnings)
#   lint     Verilator --lint-only -Wall (SARIF) + Verible style lint
#   waivers  rtl_lint(oss,waivers) (YAML: rule / file / line / message,
#            reason, owner, expires) -> violations_final.csv
#   report   sign-off: 0 open errors (+ 0 open warnings with
#            rtl_lint(oss,signoff,fail_on_warning))
# Findings in generated RTL (rtl_lint(oss,generated_globs) — the PeakRDL
# register block) are reported with status excluded, not signed off on.
# Released as LINT_SIGNOFF: rtl/ (sources + <d>.f — the SystemVerilog SYNTH
# reads through the slang front end, handshake SYNTH,rtl) + reports.
# ═══════════════════════════════════════════════════════════════════════════════

array set rtl_lint {
    tool,vendor   "opensource"
    tool,name     "verilator"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {rtl1 init1 compile1 lint1 waiver_apply1 report1 release_data1}
    dependencies,init1          {rtl1}
    dependencies,waiver_apply1  {lint1}

    mandatory_user_inputs { rtl_lint(input,rtl) }
}
array unset rtl_lint *,ruledeck1
array unset rtl_lint *,waivers1

array set rtl_lint {
    oss,tool,init          "rtlcheck"
    oss,tool,compile       "rtlcheck"
    oss,tool,lint          "verilator"
    oss,tool,waiver_apply  "rtlcheck"
    oss,tool,report        "rtlcheck"
    oss,tool,release_data  "oss_tclsh"
}

# ┌─ Rules / policy ───────────────────────────────────────────────────────────┐
# oss,top: RTL top ("" = flow(design_name)); oss,verilator,flags: extra
# Verilator lint options; oss,verible,rules: Verible --rules (e.g.
# "-line-length,+..." ; "" = defaults); oss,verible,severity: warning | info;
# oss,generated_globs: generated RTL (findings excluded from sign-off);
# oss,waivers: waiver YAML ("" = none); oss,signoff,fail_on_warning.
array set rtl_lint {
    oss,top                       ""
    oss,verilator,flags           {-Wall}
    oss,verible,rules             ""
    oss,verible,severity          warning
    oss,generated_globs           {*_regs.sv *_regs_pkg.sv}
    oss,waivers                   ""
    oss,signoff,fail_on_warning   true
}

set rtl_lint(required_inputs,init1)          "work/RTL_LINT/rtl1/rtl"
set rtl_lint(mandatory_outputs,init1)        {sources.f stubs.v}
set rtl_lint(mandatory_outputs,compile1)     {compile.status}
set rtl_lint(mandatory_outputs,lint1)        {violations.csv}
set rtl_lint(mandatory_outputs,waiver_apply1) {violations_final.csv}
set rtl_lint(mandatory_outputs,report1)      {signoff.status}
set rtl_lint(mandatory_outputs,release_data1) {release.manifest}

set rtl_lint(smartgrid,milestone) "LINT_SIGNOFF"
set rtl_lint(checklist,exit_node,LINT_SIGNOFF) report1
set rtl_lint(checklist,report)                       {work/RTL_LINT/report1/reports/lint_signoff.rpt}
set rtl_lint(checklist,metric,lint_open_errors)      {Open errors\s*:\s*(\d+)}
set rtl_lint(checklist,metric,lint_open_warnings)    {Open warnings\s*:\s*(\d+)}
set rtl_lint(checklist,metric,lint_expired_waivers)  {Expired\s*:\s*(\d+)}
set rtl_lint(checklist,report,lint_expired_waivers)  {work/RTL_LINT/waiver_apply1/reports/waivers.rpt}
set rtl_lint(checklist,mandatory_files,LINT_SIGNOFF) {work/RTL_LINT/report1/reports/lint_signoff.rpt
    work/RTL_LINT/waiver_apply1/outputs/violations_final.csv}
