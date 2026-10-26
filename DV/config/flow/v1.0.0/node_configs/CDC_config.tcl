#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — Clock-Domain-Crossing Analysis
# ║  Flow: CDC   (array: cdc)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set cdc {
    stages {rtl1 sdc1 waivers1 analyze1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,sdc1                 {}
    dependencies,waivers1             {}
    dependencies,analyze1             {rtl1 sdc1 waivers1}
    dependencies,release_data1        {rtl1 sdc1 waivers1 analyze1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _cdc_exec {analyze1 release_data1}
foreach _s $_cdc_exec {
    set cdc(subnodes,$_s) {setup run validate finish}
    set cdc(subnode_dependencies,${_s},setup)    {}
    set cdc(subnode_dependencies,${_s},run)      {setup}
    set cdc(subnode_dependencies,${_s},validate) {run}
    set cdc(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set cdc(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _cdc_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set cdc {
    stage_types,rtl1                 "inputs"
    stage_types,sdc1                 "inputs"
    stage_types,waivers1             "inputs"
    stage_types,analyze1             "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,sdc1                  "inputs"
    node_types,waivers1              "inputs"
    node_types,analyze1              "cdc"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL source input"
    node_descriptions,sdc1                 "Clock/reset SDC definitions"
    node_descriptions,waivers1             "CDC waiver rules input"
    node_descriptions,analyze1             "Clock-domain-crossing structural + protocol analysis"
    node_descriptions,release_data1        "Release CDC reports + waiver ledger"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set cdc {
    runtime,timeout,rtl1                 10
    runtime,timeout,sdc1                 10
    runtime,timeout,waivers1             10
    runtime,timeout,analyze1             60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set cdc {
    supported_tools {spyglass questa_cdc jasper_cdc}
    default_tool    "spyglass"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists cdc(tool,name)] ? $cdc(tool,name) : $cdc(default_tool)}]
set _tool_config "$_node_config_dir/CDC_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
