#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# PV — Open-source tool configuration (Magic DRC + Magic/Netgen LVS)
# Sourced from PV_config.tcl when pv(tool,name) = magic.
# Command files: PD/cmds/PV/opensource/magic/v1.0.0/
# Tools run inside the CBflow tool container (global/bin/cbflow-oss).
# ═══════════════════════════════════════════════════════════════════════════════

array set pv {
    tool,vendor   "opensource"
    tool,name     "magic"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stages: DRC + LVS on the released GDS / power-aware netlist ──────────────┐
# (No decomposition / PERC / fill-merge / XOR for sky130 with Magic+Netgen.)
array set pv {
    stages {netlist1 gds1 drc1 lvs1 merge_data1 release_data1}
    dependencies,drc1          {gds1}
    dependencies,lvs1          {gds1 netlist1}
    dependencies,merge_data1   {drc1 lvs1}
    dependencies,release_data1 {merge_data1}

    mandatory_input_groups {
        netlist_inputs {pv(input,netlist)}
        gds_inputs {pv(input,gds)}
    }
}
foreach _s {nettran1 merge_gds1 fill_merge_gds1 decomp1 decomp_merge_gds1 perc1 perc_ldl1 xor1 def1} {
    array unset pv "*,$_s"
    array unset pv "*,$_s,*"
}
unset _s

# ┌─ Tool binary per stage (oss_tclsh drivers exec magic / netgen) ────────────┐
array set pv {
    oss,tool,drc          "oss_tclsh"
    oss,tool,lvs          "oss_tclsh"
    oss,tool,merge_data   "oss_tclsh"
    oss,tool,release_data "oss_tclsh"

    oss,drc,engine        klayout
    oss,pv,mode           flat
    oss,drc,style         "drc(full)"
    oss,drc,klayout_threads 4
    oss,drc,klayout_options {feol true beol true offgrid true floating_met false seal false sram_exclude true}
    oss,drc,max_errors    0

    oss,fail_on_violations false
}
# oss,pv,mode: flat = DRC on the full GDS (every child block's layout merged)
# and LVS of the whole hierarchy (every descendant's LVS netlist); hier = child
# blocks as abstracts — DRC on the GDS with their cells emptied (the top-level
# layout only; each block has its own PV) and LVS with them as black boxes
# (Magic reads their LEF, Netgen sees empty cells on both sides).
# oss,drc,engine: klayout = the sky130 KLayout manufacturing deck
# (tech(klayout,drc); deep / hierarchical — scales to large flat layouts),
# magic = Magic drc style oss,drc,style. klayout_options: deck switches
# (-rd key=value); klayout_threads: deck threads.
# oss,fail_on_violations: false = DRC errors / LVS mismatches are reported
# (stage reports + verification summary) and the flow continues; true = a
# stage fails when DRC exceeds oss,drc,max_errors or LVS does not match.

array set pv {
    runtime,timeout,drc1  600
    runtime,timeout,lvs1  600
}

# ┌─ Mandatory outputs (relative to work/PV/<node>/outputs/) ──────────────────┐
set pv(mandatory_outputs,drc1)          {drc.rpt}
set pv(mandatory_outputs,lvs1)          {lvs.rpt}
set pv(mandatory_outputs,merge_data1)   {verification_summary.rpt}
set pv(mandatory_outputs,release_data1) {release.manifest}

# ┌─ Signoff verdict (release metrics.rpt Status; SmartGrid Signoff tab) ──────┐
# PASS when DRC errors <= max_drc and the LVS result matches lvs_pass (regex);
# lvs_required false (PV on a floorplan release) = DRC only, LVS reported.
array set pv {
    signoff,max_drc     0
    signoff,lvs_pass    {^Circuits match uniquely}
    signoff,lvs_required true
}

# ┌─ Release tag ───────────────────────────────────────────────────────────────┐
# Default tag = the exit this run verifies (the tag of pv(input,release_tag)); the
# release lands at <phase>/<block>/PV/<exit> beside the PNR release.
array set pv {
    release,exit_from   "input,release_tag"
}
