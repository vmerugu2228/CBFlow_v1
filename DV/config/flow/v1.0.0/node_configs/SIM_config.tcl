#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  DV — RTL Regression Simulation
# ║  Flow: SIM   (array: sim)
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Stages ────────────────────────────────────────────────────────────────────
array set sim {
    stages {rtl1 tb1 tests1 compile1 run1 release_data1}

    merge_entry_stage     rtl1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,rtl1                 {}
    dependencies,tb1                  {}
    dependencies,tests1               {}
    dependencies,compile1             {rtl1 tb1 tests1}
    dependencies,run1                 {rtl1 tb1 tests1 compile1}
    dependencies,release_data1        {rtl1 tb1 tests1 run1}
}

# ── Subnodes ──────────────────────────────────────────────────────────────────
set _sim_exec {compile1 run1 release_data1}
foreach _s $_sim_exec {
    set sim(subnodes,$_s) {setup run validate finish}
    set sim(subnode_dependencies,${_s},setup)    {}
    set sim(subnode_dependencies,${_s},run)      {setup}
    set sim(subnode_dependencies,${_s},validate) {run}
    set sim(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set sim(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}
unset -nocomplain _sim_exec _s _sub

# ── Stage / Node types ────────────────────────────────────────────────────────
array set sim {
    stage_types,rtl1                 "inputs"
    stage_types,tb1                  "inputs"
    stage_types,tests1               "inputs"
    stage_types,compile1             "execution"
    stage_types,run1                 "execution"
    stage_types,release_data1        "release"

    node_types,rtl1                  "inputs"
    node_types,tb1                   "inputs"
    node_types,tests1                "inputs"
    node_types,compile1              "sim_compile"
    node_types,run1                  "sim_run"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                 "RTL / netlist DUT sources"
    node_descriptions,tb1                  "Testbench sources"
    node_descriptions,tests1               "Test list / regression seeds"
    node_descriptions,compile1             "DUT + TB compilation"
    node_descriptions,run1                 "Regression run (multi-seed / multi-test)"
    node_descriptions,release_data1        "Release regression logs + coverage DBs"
}

# ── Runtime ───────────────────────────────────────────────────────────────────
array set sim {
    runtime,timeout,rtl1                 10
    runtime,timeout,tb1                  10
    runtime,timeout,tests1               10
    runtime,timeout,compile1             120
    runtime,timeout,run1                 120
    runtime,timeout,release_data1        10
}

# ── Tools ─────────────────────────────────────────────────────────────────────
array set sim {
    supported_tools {vcs questa xcelium}
    default_tool    "vcs"
}

# ── Tool-specific config ──────────────────────────────────────────────────────
# Tool selection cascades: node_config default → user_config override.
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists sim(tool,name)] ? $sim(tool,name) : $sim(default_tool)}]
set _tool_config "$_node_config_dir/SIM_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
}
# (No hard-fail if the tool config is missing — DV scaffold ships stub configs
#  only for the default tool. Non-default tools can be added incrementally.)
