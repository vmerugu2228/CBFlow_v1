#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              LEC Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (Formality, Conformal).
# Tool-specific settings sourced from LEC_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    stages {netlist_golden1 netlist_revised1 constraints1 compare1 release_data1}

    merge_entry_stage     netlist_golden1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    dependencies,netlist_golden1  {}
    dependencies,netlist_revised1 {}
    dependencies,constraints1     {}
    dependencies,compare1         {netlist_golden1 netlist_revised1 constraints1}
    dependencies,release_data1    {compare1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _lec_exec_stages {compare1 release_data1}
foreach _s $_lec_exec_stages {
    set lec(subnodes,$_s) {setup run validate finish}
    set lec(subnode_dependencies,${_s},setup)    {}
    set lec(subnode_dependencies,${_s},run)      {setup}
    set lec(subnode_dependencies,${_s},validate) {run}
    set lec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set lec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    stage_types,netlist_golden1  "inputs"
    stage_types,netlist_revised1 "inputs"
    stage_types,constraints1     "inputs"
    stage_types,compare1         "execution"
    stage_types,release_data1    "release"

    node_types,netlist_golden1  "inputs"
    node_types,netlist_revised1 "inputs"
    node_types,constraints1     "inputs"
    node_types,compare1         "compare"
    node_types,release_data1    "release_data"

    node_descriptions,netlist_golden1  "Golden reference netlist input"
    node_descriptions,netlist_revised1 "Revised netlist input"
    node_descriptions,constraints1     "LEC constraints input"
    node_descriptions,compare1         "Design comparison between golden and revised netlists (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1    "Release LEC results and reports"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    runtime,timeout,netlist_golden1  10
    runtime,timeout,netlist_revised1 10
    runtime,timeout,constraints1     10
    runtime,timeout,compare1         60
    runtime,timeout,release_data1    10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    critical_files,compare1 {lec(input,netlist_golden) lec(input,netlist_revised)}

    mandatory_outputs,compare1 {results/lec/comparison.rpt}

    mandatory_input_groups {
        netlist_golden_inputs {lec(input,netlist_golden)}
        netlist_revised_inputs {lec(input,netlist_revised)}
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    release_types,equivalence,description "Logic equivalence checking results and reports"
    release_types,equivalence,files {
        "results/lec/comparison.rpt" "reports/lec_comparison.rpt"
        "results/lec/equivalence.rpt" "reports/lec_equivalence.rpt"
        "results/lec/analysis.log" "logs/lec_analysis.log"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set lec {
    supported_tools {formality conformal}
    default_tool    "formality"
}

# Source tool-specific configuration
# Tool is set via: user_config lec(tool,name) or defaults to lec(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists lec(tool,name)] ? $lec(tool,name) : $lec(default_tool)}]

set _tool_config "$_node_config_dir/LEC_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $lec(supported_tools)"
    exit 1
}
