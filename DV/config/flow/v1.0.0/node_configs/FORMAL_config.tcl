#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — Formal Property Verification
# ║  Flow: FORMAL   (array: formal)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set formal {
    stages {rtl1 props1 constraints1 analyze1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,props1               {}
    dependencies,constraints1         {}
    dependencies,analyze1             {rtl1 props1 constraints1}
    dependencies,release_data1        {rtl1 props1 constraints1 analyze1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _formal_exec {analyze1 release_data1}
foreach _s $_formal_exec {
    set formal(subnodes,$_s) {setup run validate finish}
    set formal(subnode_dependencies,${_s},setup)    {}
    set formal(subnode_dependencies,${_s},run)      {setup}
    set formal(subnode_dependencies,${_s},validate) {run}
    set formal(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set formal(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _formal_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set formal {
    stage_types,rtl1                 "inputs"
    stage_types,props1               "inputs"
    stage_types,constraints1         "inputs"
    stage_types,analyze1             "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,props1                "inputs"
    node_types,constraints1          "inputs"
    node_types,analyze1              "formal"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL source input"
    node_descriptions,props1               "SVA / property definitions"
    node_descriptions,constraints1         "Formal assume constraints"
    node_descriptions,analyze1             "Property proof / bounded model checking"
    node_descriptions,release_data1        "Release proof results + counterexample DBs"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set formal {
    runtime,timeout,rtl1                 10
    runtime,timeout,props1               10
    runtime,timeout,constraints1         10
    runtime,timeout,analyze1             60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set formal {
    supported_tools {jaspergold vc_formal questa_formal}
    default_tool    "jaspergold"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists formal(tool,name)] ? $formal(tool,name) : $formal(default_tool)}]
set _tool_config "$_node_config_dir/FORMAL_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
