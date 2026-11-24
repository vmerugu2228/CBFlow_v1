#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# ECO — Open-source tool configuration (OpenROAD + KLayout)
# Sourced from ECO_config.tcl when eco(tool,name) = openroad.
# Input: a PNR (or earlier ECO) release — eco(input,release_tag): its routed
# database (db/<design>.odb) and SDC. Timing ECO on the routed design:
#   eco1      apply the changes (eco(oss,mode) changes | repair), legalize,
#             re-route (global route + detailed route)
#   signoff1  fillers, supply connections, deliverables, OpenRCX per RC corner,
#             post-ECO timing / QoR
#   export_data1 / release_data1  GDS + release as <EXIT>_ECO<n>
# Command files: PD/cmds/ECO/opensource/openroad/v1.0.0/
# Driven by the timing-eco Claude Code skill (.claude/skills/timing-eco/).
# ═══════════════════════════════════════════════════════════════════════════════

array set eco {
    tool,vendor   "opensource"
    tool,name     "openroad"
    tool,version  "v1.0.0"
    tool,args     ""
}

# ┌─ Stage list (replaces the common netlist/def/library inputs) ─────────────┐
foreach _k [array names eco "*,netlist1"] { unset eco($_k) }
foreach _k [array names eco "*,def1"]     { unset eco($_k) }
foreach _k [array names eco "*,library1"] { unset eco($_k) }
foreach _k [array names eco "*,export_db1*"] { unset eco($_k) }
unset -nocomplain _k eco(critical_files,eco1) eco(mandatory_outputs,eco1) eco(release_types,eco,files)

array set eco {
    stages {odb1 sdc1 eco1 signoff1 export_data1 release_data1}
    merge_entry_stage     odb1
    merge_handoff_stage   release_data1

    dependencies,odb1          {}
    dependencies,sdc1          {}
    dependencies,eco1          {odb1 sdc1}
    dependencies,signoff1      {eco1}
    dependencies,export_data1  {signoff1}
    dependencies,release_data1 {export_data1}

    stage_types,odb1          "inputs"
    stage_types,sdc1          "inputs"
    stage_types,eco1          "execution"
    stage_types,signoff1      "execution"
    stage_types,export_data1  "export_data"
    stage_types,release_data1 "release_data"

    node_types,odb1          "inputs"
    node_types,sdc1          "inputs"
    node_types,eco1          "eco"
    node_types,signoff1      "signoff"
    node_types,export_data1  "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,odb1          "Routed database from the release (db/<design>.odb)"
    node_descriptions,sdc1          "SDC from the release"
    node_descriptions,eco1          "Apply the timing ECO (change file or guided repair), legalize, re-route"
    node_descriptions,signoff1      "Fillers, supply connections, deliverables, OpenRCX, post-ECO timing"
    node_descriptions,export_data1  "GDS stream-out of the ECO'd layout"
    node_descriptions,release_data1 "Release as <EXIT>_ECO<n> (project(release,tag))"

    runtime,timeout,odb1          10
    runtime,timeout,sdc1          10
    runtime,timeout,eco1          240
    runtime,timeout,signoff1      120
    runtime,timeout,export_data1  60
    runtime,timeout,release_data1 20

    mandatory_user_inputs {
        eco(input,odb)
        eco(input,sdc)
    }
    mandatory_input_groups {
        odb_inputs {eco(input,odb)}
        sdc_inputs {eco(input,sdc)}
    }
}
foreach _s {eco1 signoff1 export_data1 release_data1} {
    set eco(subnodes,$_s) {setup run validate finish}
    set eco(subnode_dependencies,${_s},setup)    {}
    set eco(subnode_dependencies,${_s},run)      {setup}
    set eco(subnode_dependencies,${_s},validate) {run}
    set eco(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set eco(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _s _sub

array set eco {
    mandatory_outputs,eco1         {outputs/eco.odb reports/eco_changes.rpt}
    mandatory_outputs,signoff1     {outputs/final.odb outputs/final.def outputs/final.v}
    mandatory_outputs,export_data1 {outputs/final.gds}
}

# ┌─ Tool binary per stage (lsf(tool_shell,<tool>) → cbflow-oss) ──────────────┐
array set eco {
    oss,tool,eco          "openroad"
    oss,tool,signoff      "openroad"
    oss,tool,export_data  "oss_tclsh"
    oss,tool,release_data "oss_tclsh"
    oss,threads           6
}

# ┌─ ECO mode ─────────────────────────────────────────────────────────────────┐
# oss,mode: changes = source eco(input,change_file) (written by the timing-eco
# skill; only the commands in oss,changes,allowed are accepted, counted
# against the oss,limit,* caps before anything is applied) | repair = guided
# OpenROAD repair_timing with the oss,repair,* knobs below.
# oss,limit,*: per-run caps (ECO Agent safety rails) — buffers inserted,
# instances resized (replace_cell to another drive of the same family),
# (eco_insert_buffer <buffer_cell> <net> [load pins]: OpenROAD insert_buffer
# crashes on a routed database in this build),
# Vt swaps (replace_cell to another Vt flavour), buffers removed.
array set eco {
    oss,mode                   "changes"
    oss,changes,allowed        {replace_cell eco_insert_buffer remove_buffers}
    oss,limit,buffers          50
    oss,limit,resizes          50
    oss,limit,vt_swaps         20
    oss,limit,removals         20
}
# oss,repair,*: repair_timing knobs (repair mode). sequence: move list
# (e.g. "unbuffer,sizeup,swap,buffer"; empty = OpenROAD default); skip:
# repair_timing -skip_* flags (e.g. {gate_cloning pin_swap}).
array set eco {
    oss,repair,setup            true
    oss,repair,hold             true
    oss,repair,setup_margin     0.0
    oss,repair,hold_margin      0.05
    oss,repair,max_buffer_percent 2
    oss,repair,max_utilization  90
    oss,repair,sequence         ""
    oss,repair,skip             {gate_cloning}
}

# ┌─ Legalize / re-route ──────────────────────────────────────────────────────┐
# oss,place,max_displacement: detailed_placement bound (um) for the cells the
# ECO moved / added. oss,route,max_drc: detailed-route DRC allowed after the
# re-route (0 = clean). oss,fail_on_violations: true = DRC above the limit
# fails eco1.
array set eco {
    oss,place,max_displacement 20
    oss,route,max_drc          0
    oss,fail_on_violations     true
}

# ┌─ Export / release (same recipe as PNR) ────────────────────────────────────┐
set eco(oss,export,klayout_batch)          {klayout -zz -r}
set eco(oss,export,min_area_layers)        {}
set eco(oss,qor_file_suffix)               "_qor.tcl"
# oss,release,tag_pattern: an ECO release tag is <EXIT>_ECO<n> of an exit of
# the run's phase (SmartGrid shows it as a variant of the exit); the exit's
# earlier exits must be released (exit order).
set eco(oss,release,tag_pattern)           {^([A-Z0-9_]+?)_ECO([0-9]+)$}

# ┌─ Exit checklist data (this tool) ─────────────────────────────────────────┐
array set eco {
    checklist,report "work/ECO/${exit_node}/reports/checklist_metrics.rpt"
}
