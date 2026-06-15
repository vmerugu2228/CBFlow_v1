#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          GLS_FUNC Flow Configuration (Tool-Independent)                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Gate-level functional simulation. Knob: dft(mode) "zd" | "sdf".

array set gls_func {
    stages {netlist1 sdf1 testbench1 lib1 init_sim1 compile1 run_sim1 coverage1 release_data1}

    dependencies,netlist1       {}
    dependencies,sdf1           {}
    dependencies,testbench1     {}
    dependencies,lib1           {}
    dependencies,init_sim1      {netlist1 testbench1 lib1}
    dependencies,compile1       {init_sim1}
    dependencies,run_sim1       {compile1}
    dependencies,coverage1      {run_sim1}
    dependencies,release_data1  {coverage1}
}

set _gls_func_exec_stages {init_sim1 compile1 run_sim1 coverage1 release_data1}
foreach _s $_gls_func_exec_stages {
    set gls_func(subnodes,$_s) {setup run validate finish}
    set gls_func(subnode_dependencies,${_s},setup)    {}
    set gls_func(subnode_dependencies,${_s},run)      {setup}
    set gls_func(subnode_dependencies,${_s},validate) {run}
    set gls_func(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set gls_func(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

array set gls_func {
    stage_types,netlist1       "inputs"
    stage_types,sdf1           "inputs"
    stage_types,testbench1     "inputs"
    stage_types,lib1           "inputs"
    stage_types,init_sim1      "execution"
    stage_types,compile1       "execution"
    stage_types,run_sim1       "execution"
    stage_types,coverage1      "execution"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,sdf1           "inputs"
    node_types,testbench1     "inputs"
    node_types,lib1           "inputs"
    node_types,init_sim1      "init_sim"
    node_types,compile1       "compile"
    node_types,run_sim1       "run_sim"
    node_types,coverage1      "coverage"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1       "Gate-level netlist"
    node_descriptions,sdf1           "SDF (sdf mode only)"
    node_descriptions,testbench1     "Functional testbench"
    node_descriptions,lib1           "Verilog sim library"
    node_descriptions,init_sim1      "Initialize simulator"
    node_descriptions,compile1       "Compile netlist + TB"
    node_descriptions,run_sim1       "Run simulation"
    node_descriptions,coverage1      "Generate coverage"
    node_descriptions,release_data1  "Release deliverables"

    mmmc,enabled            false
    mode                    "zd"

    runtime,timeout,netlist1       10
    runtime,timeout,sdf1           10
    runtime,timeout,testbench1     10
    runtime,timeout,lib1           10
    runtime,timeout,init_sim1      20
    runtime,timeout,compile1       60
    runtime,timeout,run_sim1       180
    runtime,timeout,coverage1      30
    runtime,timeout,release_data1  10

    mandatory_user_inputs {
        gls_func(input,netlist)
        gls_func(input,testbench)
    }

    output,report_dir   "reports/gls_func"
    output,results_dir  "results/gls_func"
    output,work_dir     "work/GLS_FUNC"

    supported_tools {vcs questa}
    default_tool    "vcs"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists gls_func(tool,name)] ? $gls_func(tool,name) : $gls_func(default_tool)}]
set _tool_config "$_node_config_dir/GLS_FUNC_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config } else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $gls_func(supported_tools)"
    exit 1
}
