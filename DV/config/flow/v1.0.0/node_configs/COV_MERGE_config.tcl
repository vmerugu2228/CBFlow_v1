#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — Functional Coverage Merge & Reporting
# ║  Flow: COV_MERGE   (array: cov_merge)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set cov_merge {
    stages {cov_inputs1 merge1 report1 release_data1}

    merge_entry_stage     cov_inputs1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,cov_inputs1          {}
    dependencies,merge1               {cov_inputs1}
    dependencies,report1              {cov_inputs1 merge1}
    dependencies,release_data1        {cov_inputs1 report1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _cov_merge_exec {merge1 report1 release_data1}
foreach _s $_cov_merge_exec {
    set cov_merge(subnodes,$_s) {setup run validate finish}
    set cov_merge(subnode_dependencies,${_s},setup)    {}
    set cov_merge(subnode_dependencies,${_s},run)      {setup}
    set cov_merge(subnode_dependencies,${_s},validate) {run}
    set cov_merge(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set cov_merge(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _cov_merge_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set cov_merge {
    stage_types,cov_inputs1          "inputs"
    stage_types,merge1               "execution"
    stage_types,report1              "execution"
    stage_types,release_data1        "release"

    node_types,cov_inputs1           "inputs"
    node_types,merge1                "cov_merge"
    node_types,report1               "cov_report"
    node_types,release_data1         "release_data"

    node_descriptions,cov_inputs1          "Per-run coverage DB inputs"
    node_descriptions,merge1               "Merge coverage DBs across regressions / seeds"
    node_descriptions,report1              "Generate HTML/text coverage reports"
    node_descriptions,release_data1        "Release merged coverage DB + reports"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set cov_merge {
    runtime,timeout,cov_inputs1          10
    runtime,timeout,merge1               60
    runtime,timeout,report1              60
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set cov_merge {
    supported_tools {urg imc}
    default_tool    "urg"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists cov_merge(tool,name)] ? $cov_merge(tool,name) : $cov_merge(default_tool)}]
set _tool_config "$_node_config_dir/COV_MERGE_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
