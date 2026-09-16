#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          ATPG Flow Configuration (Tool-Independent)                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Scan-inserted netlist + scandef + SDF → ATPG patterns (STIL/WGL) + coverage.
# Knob: dft(mode) "zd" (zero-delay) | "sdf" (timing-aware).

array set atpg {
    stages {netlist1 scandef1 sdf1 lib1 init_atpg1 pattern_gen1 fault_sim1 coverage_report1 export_patterns1 release_data1}

    dependencies,netlist1           {}
    dependencies,scandef1           {}
    dependencies,sdf1               {}
    dependencies,lib1               {}
    dependencies,init_atpg1         {netlist1 scandef1 sdf1 lib1}
    dependencies,pattern_gen1       {init_atpg1}
    dependencies,fault_sim1         {pattern_gen1}
    dependencies,coverage_report1   {fault_sim1}
    dependencies,export_patterns1   {coverage_report1}
    dependencies,release_data1      {export_patterns1}
}

set _atpg_exec_stages {init_atpg1 pattern_gen1 fault_sim1 coverage_report1 export_patterns1 release_data1}
foreach _s $_atpg_exec_stages {
    set atpg(subnodes,$_s) {setup run validate finish}
    set atpg(subnode_dependencies,${_s},setup)    {}
    set atpg(subnode_dependencies,${_s},run)      {setup}
    set atpg(subnode_dependencies,${_s},validate) {run}
    set atpg(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set atpg(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

array set atpg {
    stage_types,netlist1            "inputs"
    stage_types,scandef1            "inputs"
    stage_types,sdf1                "inputs"
    stage_types,lib1                "inputs"
    stage_types,init_atpg1          "execution"
    stage_types,pattern_gen1        "execution"
    stage_types,fault_sim1          "execution"
    stage_types,coverage_report1    "execution"
    stage_types,export_patterns1    "execution"
    stage_types,release_data1       "release_data"

    node_types,netlist1            "inputs"
    node_types,scandef1            "inputs"
    node_types,sdf1                "inputs"
    node_types,lib1                "inputs"
    node_types,init_atpg1          "init_atpg"
    node_types,pattern_gen1        "pattern_gen"
    node_types,fault_sim1          "fault_sim"
    node_types,coverage_report1    "coverage_report"
    node_types,export_patterns1    "export_patterns"
    node_types,release_data1       "release_data"

    node_descriptions,netlist1            "Scan-inserted netlist input"
    node_descriptions,scandef1            "Scan chain definition (scandef) input"
    node_descriptions,sdf1                "SDF input (sdf mode only)"
    node_descriptions,lib1                "Technology library input"
    node_descriptions,init_atpg1          "Initialize ATPG environment"
    node_descriptions,pattern_gen1        "Generate ATPG patterns (stuck-at, transition, path-delay)"
    node_descriptions,fault_sim1          "Fault simulation and coverage measurement"
    node_descriptions,coverage_report1    "Generate coverage reports"
    node_descriptions,export_patterns1    "Export patterns (STIL/WGL/VCD)"
    node_descriptions,release_data1       "Release ATPG deliverables"

    mmmc,enabled            false
    mode                    "zd"

    runtime,timeout,netlist1            10
    runtime,timeout,scandef1            10
    runtime,timeout,sdf1                10
    runtime,timeout,lib1                10
    runtime,timeout,init_atpg1          20
    runtime,timeout,pattern_gen1        120
    runtime,timeout,fault_sim1          90
    runtime,timeout,coverage_report1    20
    runtime,timeout,export_patterns1    15
    runtime,timeout,release_data1       10

    mandatory_user_inputs {
        atpg(input,netlist)
        atpg(input,scandef)
    }

    output,report_dir   "reports/atpg"
    output,results_dir  "results/atpg"
    output,work_dir     "work/ATPG"

    supported_tools {tessent testmax}
    default_tool    "tessent"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists atpg(tool,name)] ? $atpg(tool,name) : $atpg(default_tool)}]
set _tool_config "$_node_config_dir/ATPG_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config } else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $atpg(supported_tools)"
    exit 1
}
