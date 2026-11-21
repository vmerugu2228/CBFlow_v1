#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH — Open-source tool configuration (Yosys)
# Sourced from SYNTH_config.tcl when synth(tool,name) = yosys.
# Command files: PD/cmds/SYNTH/opensource/yosys/v1.0.0/
# Tools run inside the CBflow tool container (global/bin/cbflow-oss).
# Output: the SYNTH release (netlist + SDC + UPF) consumed by PNR by tag.
# ═══════════════════════════════════════════════════════════════════════════════

array set synth {
    tool,vendor   "opensource"
    tool,name     "yosys"
    tool,version  "v1.0.0"
    tool,args     ""

    mandatory_user_inputs {
        synth(input,rtl_filelist)
        synth(input,sdc_func_file)
        synth(input,upf_file)
    }
}

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set synth {
    oss,tool,synthesis    "yosys"
    oss,tool,export_data  "oss_tclsh"
    oss,tool,release_data "oss_tclsh"
}

# ┌─ Synthesis ────────────────────────────────────────────────────────────────┐
# oss,synth,flatten: flatten the design's own hierarchy (child hard macros from
# the library tag stay blackboxes). oss,synth,abc_delay_ps: ABC delay target
# (0 = area-oriented mapping).
array set synth {
    oss,synth,flatten       true
    oss,synth,abc_delay_ps  0
    runtime,timeout,synthesis1 120
}

# ┌─ Inputs / mandatory outputs (relative to work/SYNTH/<node>/outputs/) ──────┐
set synth(required_inputs,synthesis1)    "work/SYNTH/rtl1/rtl work/SYNTH/sdc1/sdc work/SYNTH/upf1/upf"
set synth(required_inputs,export_data1)  "work/SYNTH/synthesis1/outputs/synthesis.v"
set synth(required_inputs,release_data1) "work/SYNTH/export_data1/outputs/final.v"
set synth(mandatory_outputs,synthesis1)    {synthesis.v}
set synth(mandatory_outputs,export_data1)  {final.v final.sdc final.upf}
set synth(mandatory_outputs,release_data1) {release.manifest}
