#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# GLS_FUNC — Open-source tool configuration (vendor opensource, tool iverilog)
# Sourced from GLS_FUNC_config.tcl when gls_func(tool,name) = iverilog.
# Command files: DFT/cmds/GLS_FUNC/opensource/iverilog/v1.0.0/
#
# Zero-delay gate-level functional simulation (Icarus Verilog): the released
# netlist (SYNTH / PNR, by tag) + the cell models (FUNCTIONAL) + the memory
# models of the library tag + the user's self-checking testbench. Pass =
# gls_func(oss,pass_regex) in the log, no gls_func(oss,fail_regex) line, and
# $finish reached. Toggle coverage of gls_func(oss,dump_scope) from a VCD.
# Signoff-style: the netlist comes only from the release of the tag it
# verifies (gls_func(input,netlist_release_tag)); the release goes to
# GLS_FUNC/<that tag>.
# ═══════════════════════════════════════════════════════════════════════════════

array set gls_func {
    tool,vendor   "opensource"
    tool,name     "iverilog"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {netlist1 testbench1 init_sim1 compile1 run_sim1 coverage1 release_data1}
    dependencies,init_sim1    {netlist1 testbench1}

    release,exit_from          "input,netlist_release_tag"
    release,exit_exempt_inputs {testbench}
}
array unset gls_func *,sdf1
array unset gls_func *,lib1

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set gls_func {
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
array set gls_func {
    oss,tb_input         testbench
    oss,tb_top           ""
    oss,defines          {}
    oss,plusargs         {}
    oss,macros           models
    oss,pass_regex       {TEST PASSED}
    oss,fail_regex       {ERROR|TEST FAILED|MISMATCH}
    oss,toggle,enable    true
    oss,dump_scope       ""
}

# ┌─ Inputs / mandatory outputs (relative to work/GLS_FUNC/<node>/outputs/) ───┐
set gls_func(required_inputs,init_sim1)     "work/GLS_FUNC/netlist1/netlist work/GLS_FUNC/testbench1/testbench"
set gls_func(mandatory_outputs,init_sim1)    {sim_files.txt}
set gls_func(mandatory_outputs,compile1)     {sim.vvp}
set gls_func(mandatory_outputs,run_sim1)     {run_sim.status}
set gls_func(mandatory_outputs,coverage1)    {coverage.rpt}
set gls_func(mandatory_outputs,release_data1) {release.manifest}
