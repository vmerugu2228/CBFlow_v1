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

# ┌─ Extraction / timing files and reports ────────────────────────────────────┐
# oss,extraction,spef: SPEF of one RC corner, relative to
# work/STA/<extraction node>/<rc_corner>/ — written by extraction, read by
# timing (${design_name} / ${rc_corner} substituted at run time).
# oss,scenario_qor_file: per-scenario QoR metrics (reports/ of the scenario),
# copied to outputs/<scenario><oss,qor_file_suffix>.
# oss,report,group_path_count: paths per group in setup.rpt / hold.rpt.
# oss,allow_no_spef: true = a scenario whose RC corner has no SPEF is timed
# with wire-load estimates (warning); false = the scenario fails.
# oss,drv,max_fanout: fanout limit set on the design before the DRV checks
# (tran / cap limits come from the libraries); 10 = the sky130 OpenLane default.
# oss,dont_use,tech_key: tech(<track>,<key>) list no instance may use
# (dont_use_pnr: the post-route list — the synthesis list bans the clock
# cells CTS adds). oss,dont_touch,instances: instance patterns that must still
# exist (isolation clamps, spare / tie cells, macros); set per block in the uc.
# oss,report_power: report_power per scenario (reports/power.rpt), merged into
# outputs/sta_power.rpt (mW) and the release metrics.rpt '# category: power'.
# oss,sta,mode: flat = a design with child blocks is timed flat — every
# descendant's gate netlist (tech(block,<b>,netlist)) with its SPEF for the
# scenario's RC corner (tech(block,<b>,spef,<rc>)) stitched onto each of its
# instances; hier = children as their timing models (tech(block,<b>,lib,*)).
array set sta {
    oss,sta,mode                flat
    oss,extraction,spef         {results/${design_name}_${rc_corner}.spef}
    oss,scenario_qor_file       "qor.tcl"
    oss,qor_file_suffix         "_qor.tcl"
    oss,report,group_path_count 10
    oss,allow_no_spef           false
    oss,report_power            true
    oss,drv,max_fanout          10
    oss,dont_use,tech_key       dont_use_pnr
    oss,dont_touch,instances    {}
}

# ┌─ Mandatory outputs (relative to work/STA/<node>/outputs/) ──────────────────┐
# extraction / timing: one SPEF per RC corner and one QoR per scenario land in
# outputs/ (the dynamic handlers fail any corner / scenario that produces none).
set sta(mandatory_outputs,extraction1)    {}
set sta(mandatory_outputs,timing1)        {}
set sta(mandatory_outputs,merge_reports1) {sta_summary.rpt sta_summary.tcl sta_checklist.rpt}
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

# ┌─ Checklist (STA_SIGNOFF — global/config/exit/v1.0.0/STA_SIGNOFF_config.tcl)
# Each check reads one "Key : value" line of merge_reports' sta_checklist.rpt
# (worst / total over every timed scenario).
array set sta {
    checklist,exit_node,STA_SIGNOFF        merge_reports1
    checklist,report                       "work/STA/${exit_node}/outputs/sta_checklist.rpt"
    checklist,mandatory_files,STA_SIGNOFF  "work/STA/${exit_node}/outputs/sta_summary.rpt work/STA/${exit_node}/outputs/sta_checklist.rpt"
    checklist,metric,sta_scenarios         {^Scenarios timed\s*:\s*(\d+)}
    checklist,metric,sta_failing_scenarios {^Failing scenarios\s*:\s*(\d+)}
    checklist,metric,sta_setup_wns         {^Worst setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,sta_setup_tns         {^Worst setup TNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,sta_hold_wns          {^Worst hold WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,sta_hold_tns          {^Worst hold TNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)}
    checklist,metric,sta_max_tran          {^Tran violations\s*:\s*(\d+)}
    checklist,metric,sta_max_cap           {^Cap violations\s*:\s*(\d+)}
    checklist,metric,sta_max_fanout        {^Fanout violations\s*:\s*(\d+)}
    checklist,metric,sta_noise             {^Noise\s*:\s*(-?[0-9.]+)}
    checklist,metric,sta_total_power       {^Total power mW\s*:\s*([0-9.eE+-]+)}
    checklist,metric,sta_dont_use          {^Dont use cells\s*:\s*(\d+)}
    checklist,metric,sta_dont_touch        {^Dont touch missing\s*:\s*(\d+)}
}

# ┌─ Path groups (timing by group: report + WNS / TNS per corner) ─────────────┐
# NAME {from to} — from / to: all_registers | all_inputs | all_outputs.
# report_paths: paths per <stage>_<setup|hold>_<group>_<corner>.rpt.
set sta(oss,path_groups) {
    R2R {all_registers all_registers}
    I2R {all_inputs    all_registers}
    R2O {all_registers all_outputs}
    I2O {all_inputs    all_outputs}
}
set sta(oss,path_groups,report_paths) 10
