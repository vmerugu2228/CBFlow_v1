#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — RTL Lint & Style Checking
# ║  Flow: LINT   (array: lint)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set lint {
    stages {rtl1 waivers1 analyze1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,waivers1             {}
    dependencies,analyze1             {rtl1 waivers1}
    dependencies,release_data1        {rtl1 waivers1 analyze1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _lint_exec {analyze1 release_data1}
foreach _s $_lint_exec {
    set lint(subnodes,$_s) {setup run validate finish}
    set lint(subnode_dependencies,${_s},setup)    {}
    set lint(subnode_dependencies,${_s},run)      {setup}
    set lint(subnode_dependencies,${_s},validate) {run}
    set lint(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set lint(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _lint_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set lint {
    stage_types,rtl1                 "inputs"
    stage_types,waivers1             "inputs"
    stage_types,analyze1             "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,waivers1              "inputs"
    node_types,analyze1              "lint"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL source input"
    node_descriptions,waivers1             "Lint waiver rules input"
    node_descriptions,analyze1             "Static RTL lint / style / synthesizability analysis"
    node_descriptions,release_data1        "Release lint reports + waiver ledger"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set lint {
    runtime,timeout,rtl1                 10
    runtime,timeout,waivers1             10
    runtime,timeout,analyze1             60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set lint {
    supported_tools {spyglass ascentlint}
    default_tool    "spyglass"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists lint(tool,name)] ? $lint(tool,name) : $lint(default_tool)}]
set _tool_config "$_node_config_dir/LINT_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
