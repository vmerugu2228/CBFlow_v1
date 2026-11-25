#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# GLS_SCAN_MBIST — Open-source tool configuration (vendor opensource, tool iverilog)
# Sourced from GLS_SCAN_MBIST_config.tcl when gls_scan_mbist(tool,name) = iverilog.
# Command files: DFT/cmds/GLS_SCAN_MBIST/opensource/iverilog/v1.0.0/
#
# Zero-delay gate-level simulation of the ATPG scan patterns (Icarus Verilog):
# the released netlist (PNR, by tag) + the cell models (FUNCTIONAL) + macro
# stubs (outputs held 0 — the ATPG model) + the serial-scan testbench of the
# ATPG release (patterns input, flow_input_handshake(GLS_SCAN_MBIST,patterns)).
# Running the pre-PD patterns on the post-route netlist proves the chains and
# the captured responses survived implementation. Pass = 0 mismatches.
# oss,verify scan (mbist / bscan are not part of the open-source flow yet).
# Signoff-style: the netlist comes only from the release of the tag it
# verifies (gls_scan_mbist(input,netlist_release_tag)); the release goes to
# GLS_SCAN_MBIST/<that tag>.
# ═══════════════════════════════════════════════════════════════════════════════

array set gls_scan_mbist {
    tool,vendor   "opensource"
    tool,name     "iverilog"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {netlist1 patterns1 init_sim1 compile1 run_sim1 coverage1 release_data1}
    dependencies,init_sim1    {netlist1 patterns1}

    release,exit_from          "input,netlist_release_tag"
    release,exit_exempt_inputs {patterns}
}
array unset gls_scan_mbist *,sdf1
array unset gls_scan_mbist *,lib1

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set gls_scan_mbist {
    oss,tool,init_sim      "iverilog"
    oss,tool,compile       "iverilog"
    oss,tool,run_sim       "iverilog"
    oss,tool,coverage      "iverilog"
    oss,tool,release_data  "oss_tclsh"
}

# ┌─ Simulation ───────────────────────────────────────────────────────────────┐
# oss,tb_input: the input node holding the testbench; oss,tb_top: its top
# module (set it in the run's user config); oss,defines: +define macros;
# oss,plusargs: vvp plusargs; oss,macros: models (memory models of the tag,
# declaration order fixed for iverilog) | stubs (outputs held 0);
# oss,toggle,enable + oss,dump_scope (hierarchical scope dumped, e.g.
# <tb_top>.dut) for toggle coverage.
array set gls_scan_mbist {
    oss,verify           scan
    oss,tb_input         patterns
    oss,tb_top           cbflow_scan_tb
    oss,defines          {}
    oss,plusargs         {}
    oss,macros           stubs
    oss,pass_regex       {SCAN PATTERN TEST PASSED}
    oss,fail_regex       {MISMATCH|TEST FAILED}
    oss,toggle,enable    false
    oss,dump_scope       ""
}

# ┌─ Inputs / mandatory outputs (relative to work/GLS_SCAN_MBIST/<node>/outputs/) ───┐
set gls_scan_mbist(required_inputs,init_sim1)     "work/GLS_SCAN_MBIST/netlist1/netlist work/GLS_SCAN_MBIST/patterns1/patterns"
set gls_scan_mbist(mandatory_outputs,init_sim1)    {sim_files.txt}
set gls_scan_mbist(mandatory_outputs,compile1)     {sim.vvp}
set gls_scan_mbist(mandatory_outputs,run_sim1)     {run_sim.status}
set gls_scan_mbist(mandatory_outputs,coverage1)    {coverage.rpt}
set gls_scan_mbist(mandatory_outputs,release_data1) {release.manifest}
