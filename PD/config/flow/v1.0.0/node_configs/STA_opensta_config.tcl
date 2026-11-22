#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# STA — Open-source tool configuration (OpenRCX extraction + OpenSTA timing)
# Sourced from STA_config.tcl when sta(tool,name) = opensta.
# Command files: PD/cmds/STA/opensource/opensta/v1.0.0/
# Input: a PNR release (routed DEF, netlist, per-mode SDC) — sta(input,release_tag).
# Dynamic subnodes: extraction per rc_corner_list entry, timing per MMMC
# scenario (sta(mmmc,setup_scenarios) / sta(mmmc,hold_scenarios), else the
# node's scenario set).
# ═══════════════════════════════════════════════════════════════════════════════

array set sta {
    tool,vendor   "opensource"
    tool,name     "opensta"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stage list: libraries come from the library tag — no library input ───────┐
array set sta {
    stages {netlist1 sdc1 def1 extraction1 timing1 merge_reports1 release_data1}
    dependencies,extraction1 {netlist1 sdc1 def1}

    mandatory_user_inputs {
        sta(input,netlist)
        sta(input,sdc,func)
        sta(input,def_file)
    }
}
foreach _k [array names sta "*library1*"] { unset sta($_k) }
unset -nocomplain _k

# ┌─ Tool binary per stage ────────────────────────────────────────────────────┐
array set sta {
    oss,tool,extraction    "openroad"
    oss,tool,timing        "sta"
    oss,tool,merge_reports "oss_tclsh"
    oss,tool,release_data  "oss_tclsh"
    oss,threads            4
}

# ┌─ Mandatory outputs (relative to work/STA/<node>/outputs/) ──────────────────┐
# extraction / timing: one SPEF per RC corner and one QoR per scenario land in
# outputs/ (the dynamic handlers fail any corner / scenario that produces none).
set sta(mandatory_outputs,extraction1)    {}
set sta(mandatory_outputs,timing1)        {}
set sta(mandatory_outputs,merge_reports1) {sta_summary.rpt sta_summary.tcl}
set sta(mandatory_outputs,release_data1)  {release.manifest}

# ┌─ Signoff verdict (release metrics.rpt Status; SmartGrid Signoff tab) ──────┐
# PASS when the worst slack over all scenarios meets these (library time units).
array set sta {
    signoff,min_setup_wns   0
    signoff,min_hold_wns    0
}

# ┌─ Release tag ───────────────────────────────────────────────────────────────┐
# Default tag = the exit this run verifies (the tag of sta(input,release_tag)); the
# release lands at <phase>/<block>/STA/<exit> beside the PNR release.
array set sta {
    release,exit_from   "input,release_tag"
}
