#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — UPF Power Intent Check
# ║  Flow: UPF_CHECK   (array: upf_check)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set upf_check {
    stages {rtl1 upf1 analyze1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,upf1                 {}
    dependencies,analyze1             {rtl1 upf1}
    dependencies,release_data1        {rtl1 upf1 analyze1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _upf_check_exec {analyze1 release_data1}
foreach _s $_upf_check_exec {
    set upf_check(subnodes,$_s) {setup run validate finish}
    set upf_check(subnode_dependencies,${_s},setup)    {}
    set upf_check(subnode_dependencies,${_s},run)      {setup}
    set upf_check(subnode_dependencies,${_s},validate) {run}
    set upf_check(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set upf_check(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _upf_check_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set upf_check {
    stage_types,rtl1                 "inputs"
    stage_types,upf1                 "inputs"
    stage_types,analyze1             "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,upf1                  "inputs"
    node_types,analyze1              "upf_check"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL source input"
    node_descriptions,upf1                 "UPF power intent input"
    node_descriptions,analyze1             "UPF structural + syntactic + intent validation"
    node_descriptions,release_data1        "Release UPF check reports + warnings ledger"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set upf_check {
    runtime,timeout,rtl1                 10
    runtime,timeout,upf1                 10
    runtime,timeout,analyze1             60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set upf_check {
    supported_tools {vc_lp questa_lp}
    default_tool    "vc_lp"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists upf_check(tool,name)] ? $upf_check(tool,name) : $upf_check(default_tool)}]
set _tool_config "$_node_config_dir/UPF_CHECK_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
