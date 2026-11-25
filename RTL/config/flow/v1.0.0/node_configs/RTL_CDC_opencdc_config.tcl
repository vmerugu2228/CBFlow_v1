#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# RTL_CDC — Open-source tool configuration (vendor opensource, tool opencdc)
# Sourced from RTL_CDC_config.tcl when rtl_cdc(tool,name) = opencdc.
# Command files: RTL/cmds/RTL_CDC/opensource/opencdc/v1.0.0/
#
# Clock-domain-crossing check of the RTL release (RTL_SPEC filelist + SDC):
#   compile      the RTL elaborated by yosys-slang (clocks / flops)
#   cdc_setup    clocks from the SDC; the RTL through sv2v (opencdc does not
#                read SystemVerilog unpacked structs / packages)
#   cdc_analyze  opencdc (profile rtl_cdc(oss,cdc,profile))
#   cdc_report   findings -> violations.csv; procedural blocks opencdc could
#                not analyse are listed (info)
#   signoff      0 open errors (+ 0 open warnings with fail_on_warning)
# Released as CDC_SIGNOFF (reports).
# ═══════════════════════════════════════════════════════════════════════════════

array set rtl_cdc {
    tool,vendor   "opensource"
    tool,name     "opencdc"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {rtl1 sdc1 init1 compile1 cdc_setup1 cdc_analyze1 cdc_report1 waiver_apply1 signoff1 release_data1}
    dependencies,init1          {rtl1 sdc1}
    dependencies,waiver_apply1  {cdc_report1}

    mandatory_user_inputs { rtl_cdc(input,rtl) rtl_cdc(input,sdc) }
}
array unset rtl_cdc *,scheme1
array unset rtl_cdc *,waivers1

array set rtl_cdc {
    oss,tool,init          "rtlcheck"
    oss,tool,compile       "rtlcheck"
    oss,tool,cdc_setup     "rtlcheck"
    oss,tool,cdc_analyze   "rtlcheck"
    oss,tool,cdc_report    "rtlcheck"
    oss,tool,waiver_apply  "rtlcheck"
    oss,tool,signoff       "rtlcheck"
    oss,tool,release_data  "oss_tclsh"
}

# oss,cdc,profile: opencdc methodology profile (default / strict /
# asic_signoff / fpga / ip_development / soc_integration).
array set rtl_cdc {
    oss,top                       ""
    oss,cdc,profile               asic_signoff
    oss,waivers                   ""
    oss,signoff,fail_on_warning   true
}

set rtl_cdc(required_inputs,init1)           "work/RTL_CDC/rtl1/rtl work/RTL_CDC/sdc1/sdc"
set rtl_cdc(mandatory_outputs,init1)         {sources.f stubs.v}
set rtl_cdc(mandatory_outputs,compile1)      {compile.status}
set rtl_cdc(mandatory_outputs,cdc_setup1)    {design_sv2v.v cdc.sdc}
set rtl_cdc(mandatory_outputs,cdc_analyze1)  {cdc.json}
set rtl_cdc(mandatory_outputs,cdc_report1)   {violations.csv}
set rtl_cdc(mandatory_outputs,waiver_apply1) {violations_final.csv}
set rtl_cdc(mandatory_outputs,signoff1)      {signoff.status}
set rtl_cdc(mandatory_outputs,release_data1) {release.manifest}

set rtl_cdc(smartgrid,milestone) "CDC_SIGNOFF"
set rtl_cdc(checklist,exit_node,CDC_SIGNOFF) signoff1
set rtl_cdc(checklist,report)                      {work/RTL_CDC/signoff1/reports/cdc_signoff.rpt}
set rtl_cdc(checklist,metric,cdc_open_errors)      {Open errors\s*:\s*(\d+)}
set rtl_cdc(checklist,metric,cdc_open_warnings)    {Open warnings\s*:\s*(\d+)}
set rtl_cdc(checklist,mandatory_files,CDC_SIGNOFF) {work/RTL_CDC/signoff1/reports/cdc_signoff.rpt
    work/RTL_CDC/waiver_apply1/outputs/violations_final.csv}
