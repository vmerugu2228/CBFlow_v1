#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# LEC — Open-source tool configuration (Yosys equiv_make / equiv_simple /
# equiv_induct, gate-level netlist vs netlist)
# Sourced from LEC_config.tcl when lec(tool,name) = yosys.
# Command files: PD/cmds/LEC/opensource/yosys/v1.0.0/
# Golden: SYNTH release netlist; revised: PNR release netlist (by tag).
# ═══════════════════════════════════════════════════════════════════════════════

array set lec {
    tool,vendor   "opensource"
    tool,name     "yosys"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stages: no constraints input (compare points matched by name) ────────────┐
array set lec {
    stages {netlist_golden1 netlist_revised1 compare1 release_data1}
    dependencies,compare1 {netlist_golden1 netlist_revised1}
}
array unset lec "*,constraints1"
array unset lec "*,constraints1,*"

# ┌─ Tool binary per stage + knobs ────────────────────────────────────────────┐
array set lec {
    oss,tool,compare       "yosys"
    oss,tool,release_data  "oss_tclsh"
    oss,lec,lib_set        "ss_1p60v_100c"
    oss,lec,seq_depth      5
    oss,fail_on_violations false
}

# ┌─ Mandatory outputs (relative to work/LEC/<node>/outputs/) ──────────────────┐
set lec(mandatory_outputs,compare1)      {lec.rpt}
set lec(mandatory_outputs,release_data1) {release.manifest}
