#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — Reset-Domain-Crossing Analysis
# ║  Flow: RDC   (array: rdc)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set rdc {
    stages {rtl1 reset_spec1 waivers1 analyze1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,reset_spec1          {}
    dependencies,waivers1             {}
    dependencies,analyze1             {rtl1 reset_spec1 waivers1}
    dependencies,release_data1        {rtl1 reset_spec1 waivers1 analyze1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _rdc_exec {analyze1 release_data1}
foreach _s $_rdc_exec {
    set rdc(subnodes,$_s) {setup run validate finish}
    set rdc(subnode_dependencies,${_s},setup)    {}
    set rdc(subnode_dependencies,${_s},run)      {setup}
    set rdc(subnode_dependencies,${_s},validate) {run}
    set rdc(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set rdc(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _rdc_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set rdc {
    stage_types,rtl1                 "inputs"
    stage_types,reset_spec1          "inputs"
    stage_types,waivers1             "inputs"
    stage_types,analyze1             "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,reset_spec1           "inputs"
    node_types,waivers1              "inputs"
    node_types,analyze1              "rdc"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL source input"
    node_descriptions,reset_spec1          "Reset scheme + async assertion specification"
    node_descriptions,waivers1             "RDC waiver rules input"
    node_descriptions,analyze1             "Reset-domain-crossing structural analysis"
    node_descriptions,release_data1        "Release RDC reports + waiver ledger"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set rdc {
    runtime,timeout,rtl1                 10
    runtime,timeout,reset_spec1          10
    runtime,timeout,waivers1             10
    runtime,timeout,analyze1             60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set rdc {
    supported_tools {spyglass questa_rdc}
    default_tool    "spyglass"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists rdc(tool,name)] ? $rdc(tool,name) : $rdc(default_tool)}]
set _tool_config "$_node_config_dir/RDC_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
