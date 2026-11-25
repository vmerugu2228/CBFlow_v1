#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SCAN_INSERT — Open-source tool configuration (vendor opensource, tool fault)
# Sourced from SCAN_INSERT_config.tcl when scan_insert(tool,name) = fault.
# Command files: DFT/cmds/SCAN_INSERT/opensource/fault/v1.0.0/
#
# In the open-source flow the scan chains are inserted by SYNTH
# (project(dft,enable): OpenROAD scan_replace + execute_dft_plan). SCAN_INSERT
# reads that scan netlist and its scandef from the SYNTH release and signs the
# scan structure off: the chains are traced through the netlist (scan-in port
# -> scan flops -> scan-out) and must match the SYNTH scandef exactly, checked
# against the DFT rules, flush-simulated (iverilog), and released as the scan
# netlist + scandef that ATPG consumes.
#
# The liberty comes from the library tag (the lib set of the node's MMMC view —
# mmmc_node_scenarios.tcl node init_scan), so there is no lib input node.
# ═══════════════════════════════════════════════════════════════════════════════

array set scan_insert {
    tool,vendor   "opensource"
    tool,name     "fault"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {netlist1 sdc1 scandef1 init_scan1 scan_stitch1 scan_check1 scan_export1 release_data1}
    dependencies,scandef1       {}
    dependencies,init_scan1     {netlist1 sdc1 scandef1}
    stage_types,scandef1        "inputs"
    node_types,scandef1         "inputs"
    node_descriptions,scandef1  "Scandef SYNTH wrote with the scan netlist"
    runtime,timeout,scandef1    10

    mandatory_input_groups {
        netlist_inputs {scan_insert(input,netlist)}
        sdc_inputs     {scan_insert(input,sdc)}
        scandef_inputs {scan_insert(input,scandef)}
    }
}
array unset scan_insert *,lib1

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set scan_insert {
    oss,tool,init_scan     "fault"
    oss,tool,scan_stitch   "fault"
    oss,tool,scan_check    "iverilog"
    oss,tool,scan_export   "oss_tclsh"
    oss,tool,release_data  "oss_tclsh"
}

# ┌─ Scan structure ───────────────────────────────────────────────────────────┐
# Scan ports: scan-enable from project(dft,scan_enable_pattern); scan-in /
# scan-out from project(dft,scan_in_pattern|scan_out_pattern) (DFT overlay).
# A chain whose tail drives a functional output (OpenROAD reuses one) has that
# port as its scan-out. oss,flush,enable: chain-flush simulation in scan_check.
# oss,allow_unscanned: flops left off the chains (listed) — false = violation.
array set scan_insert {
    oss,flush,enable      true
    oss,allow_unscanned   false
}

# ┌─ Inputs / mandatory outputs (relative to work/SCAN_INSERT/<node>/outputs/) ┐
set scan_insert(required_inputs,init_scan1)   "work/SCAN_INSERT/netlist1/netlist"
set scan_insert(mandatory_outputs,init_scan1)    {cells.json netlist.json}
set scan_insert(mandatory_outputs,scan_stitch1)  {scan.json scan.scandef}
set scan_insert(mandatory_outputs,scan_check1)   {scan_check.status}
set scan_insert(mandatory_outputs,scan_export1)  {scan.v scan.scandef scan.sdc scan.json}
set scan_insert(mandatory_outputs,release_data1) {release.manifest}

# ┌─ Release / exit checklist ─────────────────────────────────────────────────┐
# The release tag defaults to the exit (project(release,tag) overrides); the
# SCAN_INSERT_EXIT checks read this flow's own files.
set scan_insert(smartgrid,milestone) "SCAN_INSERT_EXIT"
set scan_insert(checklist,exit_node,SCAN_INSERT_EXIT) scan_check1
set scan_insert(checklist,report)                       {work/SCAN_INSERT/scan_check1/reports/scan_check.rpt}
set scan_insert(checklist,report,scan_stitched_netlist) {work/SCAN_INSERT/scan_export1/outputs/scan.v}
set scan_insert(checklist,report,scan_def)              {work/SCAN_INSERT/scan_export1/outputs/scan.scandef}
set scan_insert(checklist,report,scan_check_report)     {work/SCAN_INSERT/scan_check1/reports/scan_check.rpt}
set scan_insert(checklist,metric,scan_coverage_pct)     {scan_coverage_pct\s*:\s*([\d.]+)}
set scan_insert(checklist,mandatory_files,SCAN_INSERT_EXIT) {work/SCAN_INSERT/scan_export1/outputs/scan.v
    work/SCAN_INSERT/scan_export1/outputs/scan.scandef work/SCAN_INSERT/scan_check1/reports/scan_check.rpt}
