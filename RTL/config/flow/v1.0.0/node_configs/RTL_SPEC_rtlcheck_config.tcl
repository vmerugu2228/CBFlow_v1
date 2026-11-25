#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# RTL_SPEC — Open-source tool configuration (vendor opensource, tool rtlcheck)
# Sourced from RTL_SPEC_config.tcl (rtl_spec(tool,name) = rtlcheck).
# Command files: RTL/cmds/RTL_SPEC/opensource/rtlcheck/v1.0.0/
# Helpers: RTL/utils/oss/spec_tool.py (PeakRDL / openpyxl from
# lsf(oss,tools_dir)/python — global/utils/oss/install_pytools.sh; the IP-XACT
# schema from lsf(oss,tools_dir)/ipxact — install_ipxact_schema.sh).
# ═══════════════════════════════════════════════════════════════════════════════

array set rtl_spec {
    tool,vendor   "opensource"
    tool,name     "rtlcheck"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set rtl_spec {
    oss,tool,spec_check      "rtlcheck"
    oss,tool,gen_regs        "rtlcheck"
    oss,tool,gen_ipxact      "rtlcheck"
    oss,tool,gen_collateral  "rtlcheck"
    oss,tool,release_data    "oss_tclsh"
}

# ┌─ Generation ───────────────────────────────────────────────────────────────┐
# oss,regs,cpuif: register-block bus (PeakRDL regblock CPU interface);
# oss,ipxact,schema: IEEE 1685-2014 schema index (relative to
# lsf(oss,tools_dir)); oss,vplan,generate: write the initial vPlan from the
# spec's features (the DV flows own and edit it afterwards).
array set rtl_spec {
    oss,regs,cpuif        apb4-flat
    oss,ipxact,schema     ipxact/1685-2014/index.xsd
    oss,vplan,generate    true
}

# ┌─ Inputs / mandatory outputs (relative to work/RTL_SPEC/<node>/outputs/) ───┐
set rtl_spec(required_inputs,spec_check1)      "work/RTL_SPEC/spec1/spec"
set rtl_spec(mandatory_outputs,spec_check1)    {spec.json}
set rtl_spec(mandatory_outputs,gen_regs1)      {regs.status}
set rtl_spec(mandatory_outputs,gen_ipxact1)    {component.xml}
set rtl_spec(mandatory_outputs,gen_collateral1) {design.f design.sdc}
set rtl_spec(mandatory_outputs,release_data1)  {release.manifest}

# ┌─ Release / exit checklist ─────────────────────────────────────────────────┐
set rtl_spec(smartgrid,milestone) "SPEC_EXIT"
set rtl_spec(checklist,exit_node,SPEC_EXIT) gen_collateral1
set rtl_spec(checklist,report)                       {work/RTL_SPEC/spec_check1/reports/spec_check.rpt}
set rtl_spec(checklist,metric,spec_errors)           {Errors\s*:\s*(\d+)}
set rtl_spec(checklist,report,spec_errors)           {work/RTL_SPEC/spec_check1/reports/spec_check.rpt}
set rtl_spec(checklist,grep,ipxact_schema_valid)     {Schema\s*:\s*VALID}
set rtl_spec(checklist,report,ipxact_schema_valid)   {work/RTL_SPEC/gen_ipxact1/reports/ipxact.rpt}
set rtl_spec(checklist,metric,rtl_port_mismatches)   {Mismatches\s*:\s*(\d+)}
set rtl_spec(checklist,report,rtl_port_mismatches)   {work/RTL_SPEC/gen_collateral1/reports/ports.rpt}
set rtl_spec(checklist,report,register_rtl)          {work/RTL_SPEC/gen_regs1/outputs/regs.status}
set rtl_spec(checklist,mandatory_files,SPEC_EXIT) {work/RTL_SPEC/gen_ipxact1/outputs/component.xml
    work/RTL_SPEC/gen_collateral1/outputs/design.f work/RTL_SPEC/gen_collateral1/outputs/design.sdc}
