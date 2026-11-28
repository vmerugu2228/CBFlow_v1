#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# ATPG — Open-source tool configuration (vendor opensource, tool fault)
# Sourced from ATPG_config.tcl when atpg(tool,name) = fault.
# Command files: DFT/cmds/ATPG/opensource/fault/v1.0.0/
#
# Stuck-at ATPG on a full-scan netlist:
#   init_atpg    netlist → scan cells, chains traced on THIS netlist (checked
#                against the SCAN_INSERT scandef), macro stubs; pd_phase decision
#   pattern_gen  macros stubbed (outputs held 0), `fault cut` (scan flops →
#                pseudo inputs / outputs), nl2bench (liberty functions → gates),
#                bench cleanup, Atalanta (FAN ATPG + compaction)
#   fault_sim    independent stuck-at fault simulation of the pattern set (cell
#                pin faults, oss_dft.py fsim)
#   coverage_report / export_patterns (chain-ordered STIL + serial-scan
#                testbench) / zd_sim (zero-delay serial-scan simulation of every
#                pattern on the gate netlist) / signoff (coverage targets
#                project(dft,atpg,*_min), 0 mismatches)
# pd_phase pre (SCAN_INSERT release) | post (PNR release netlist + the
# SCAN_INSERT scandef): post adds timing_sim1 — not supported by the
# open-source flow yet (it fails with that message; bypass it explicitly).
# Atalanta is built for the tool image by global/utils/oss/install_atalanta.sh
# (lsf(oss,tools_dir)); its licence is research / teaching use.
# ═══════════════════════════════════════════════════════════════════════════════

array set atpg {
    tool,vendor   "opensource"
    tool,name     "fault"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {netlist1 scandef1
            init_atpg1 pattern_gen1 fault_sim1 coverage_report1 export_patterns1
            zd_sim1 timing_sim1 signoff1
            release_data1}
    dependencies,init_atpg1   {netlist1 scandef1}
    dependencies,signoff1     {zd_sim1 timing_sim1}

    decision_next,init_atpg1,pre   {zd_sim1 signoff1}
    decision_next,init_atpg1,post  {zd_sim1 timing_sim1 signoff1}
    conditional_stages,pd_phase,post {timing_sim1}
}
array unset atpg *,sdf1
array unset atpg *,lib1

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set atpg {
    oss,tool,init_atpg        "fault"
    oss,tool,pattern_gen      "fault"
    oss,tool,fault_sim        "fault"
    oss,tool,coverage_report  "oss_tclsh"
    oss,tool,export_patterns  "fault"
    oss,tool,zd_sim           "iverilog"
    oss,tool,timing_sim       "iverilog"
    oss,tool,signoff          "oss_tclsh"
    oss,tool,release_data     "oss_tclsh"
}

# ┌─ ATPG engine (Atalanta) ───────────────────────────────────────────────────┐
# backtrack: FAN phase-1 backtrack limit (-b); phase2_backtrack: phase-2
# (dynamic unique sensitization) limit, 0 = off (-B); random_packets: random
# pattern session stops after N packets of 32 patterns with no new detection
# (-r, 0 = none); compaction: shuffle-compaction limit (-c); seed: random seed
# (-s, fixed for reproducible patterns); fill: unspecified inputs R (random) |
# 0 | 1 (-R / -0 / -1).
array set atpg {
    oss,atalanta,backtrack         10
    oss,atalanta,phase2_backtrack  0
    oss,atalanta,random_packets    16
    oss,atalanta,compaction        2
    oss,atalanta,seed              1
    oss,atalanta,fill              R
}

# ┌─ Constraints / fault simulation ───────────────────────────────────────────┐
# oss,hold_ports {<port> <0|1> …}: ports held constant in ATPG and in the
# pattern simulation (async resets, test-mode pins). The scan clock and
# scan-in / scan-enable ports are handled by the scan protocol.
# oss,fault_sim,sample: 0 = every fault; N = a random sample of N faults
# (large blocks; coverage estimate +- 95 % confidence).
array set atpg {
    oss,hold_ports          {}
    oss,fault_sim,sample    0
    runtime,timeout,pattern_gen1  240
}

# ┌─ Inputs / mandatory outputs (relative to work/ATPG/<node>/outputs/) ───────┐
set atpg(required_inputs,init_atpg1)       "work/ATPG/netlist1/netlist work/ATPG/scandef1/scandef"
set atpg(mandatory_outputs,init_atpg1)       {decision_outcome.txt cells.json netlist.json scan.json macro_stubs.v}
set atpg(mandatory_outputs,pattern_gen1)     {atpg.bench atpg.test bench_map.json}
set atpg(mandatory_outputs,fault_sim1)       {fault_sim.json}
set atpg(mandatory_outputs,coverage_report1) {coverage.json}
set atpg(mandatory_outputs,export_patterns1) {patterns.json patterns.stil scan_tb.v}
set atpg(mandatory_outputs,zd_sim1)          {zd_sim.status}
set atpg(mandatory_outputs,signoff1)         {signoff.status}
set atpg(mandatory_outputs,release_data1)    {release.manifest}

# ┌─ Release / exit checklist ─────────────────────────────────────────────────┐
# Tag: ATPG_PREPD_EXIT (pd_phase pre) | ATPG_POSTPD_EXIT (post), unless
# project(release,tag). The exit checks read this flow's own reports.
set atpg(smartgrid,milestone) "ATPG_PREPD_EXIT"
set atpg(checklist,exit_node,ATPG_PREPD_EXIT)  coverage_report1
set atpg(checklist,exit_node,ATPG_POSTPD_EXIT) signoff1
set atpg(checklist,report)                     {work/ATPG/coverage_report1/reports/coverage.rpt}
set atpg(checklist,report,atpg_patterns_generated) {work/ATPG/export_patterns1/outputs/patterns.stil}
set atpg(checklist,report,atpg_fault_sim_log)      {work/ATPG/fault_sim1/reports/fault_sim.rpt}
set atpg(checklist,metric,atpg_fault_coverage_pct) {Fault coverage\s*:\s*([\d.]+)}
set atpg(checklist,metric,atpg_test_coverage_pct)  {Test coverage\s*:\s*([\d.]+)}
set atpg(checklist,report,atpg_zd_sim_log)         {work/ATPG/zd_sim1/reports/zd_sim.log}
set atpg(checklist,report,atpg_timing_sim_log)     {work/ATPG/timing_sim1/reports/timing_sim.log}
set atpg(checklist,report,atpg_signoff_report)     {work/ATPG/signoff1/reports/signoff.rpt}
set atpg(checklist,report,atpg_delivery_manifest)  {work/ATPG/signoff1/outputs/delivery/MANIFEST.json}
set atpg(checklist,mandatory_files,ATPG_PREPD_EXIT) {work/ATPG/export_patterns1/outputs/patterns.stil
    work/ATPG/coverage_report1/reports/coverage.rpt work/ATPG/fault_sim1/reports/fault_sim.rpt}
set atpg(checklist,mandatory_files,ATPG_POSTPD_EXIT) {work/ATPG/export_patterns1/outputs/patterns.stil
    work/ATPG/zd_sim1/reports/zd_sim.log work/ATPG/timing_sim1/reports/timing_sim.log
    work/ATPG/signoff1/reports/signoff.rpt work/ATPG/signoff1/outputs/delivery/MANIFEST.json}
set atpg(checklist,report,atpg_coverage_report)        {work/ATPG/coverage_report1/reports/coverage.rpt}
set atpg(checklist,report,atpg_post_patterns)          {work/ATPG/export_patterns1/outputs/patterns.stil}
set atpg(checklist,metric,atpg_post_fault_coverage_pct) {Fault coverage\s*:\s*([\d.]+)}
set atpg(checklist,report,atpg_post_fault_coverage_pct) {work/ATPG/coverage_report1/reports/coverage.rpt}
set atpg(checklist,grep,atpg_timing_sim_pass)          {Mismatches\s*:\s*0}
set atpg(checklist,report,atpg_timing_sim_pass)        {work/ATPG/timing_sim1/reports/timing_sim.log}
