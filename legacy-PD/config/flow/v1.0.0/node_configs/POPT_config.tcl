#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              POPT Flow Configuration (Tool-Independent)                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (PT, Joules).
# Tool-specific settings sourced from POPT_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    stages {netlist1 sdc1 upf1 merge_timing1 power_opt1 post_merge1 release_data1}

    dependencies,netlist1       {}
    dependencies,sdc1           {}
    dependencies,upf1           {}
    dependencies,merge_timing1  {netlist1 sdc1 upf1}
    dependencies,power_opt1     {merge_timing1}
    dependencies,post_merge1    {power_opt1}
    dependencies,release_data1  {post_merge1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _popt_exec_stages {merge_timing1 power_opt1 post_merge1 release_data1}
foreach _s $_popt_exec_stages {
    set popt(subnodes,$_s) {setup run validate finish}
    set popt(subnode_dependencies,${_s},setup)    {}
    set popt(subnode_dependencies,${_s},run)      {setup}
    set popt(subnode_dependencies,${_s},validate) {run}
    set popt(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set popt(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    stage_types,netlist1       "inputs"
    stage_types,sdc1           "inputs"
    stage_types,upf1           "inputs"
    stage_types,merge_timing1  "execution"
    stage_types,power_opt1     "execution"
    stage_types,post_merge1    "execution"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,sdc1           "inputs"
    node_types,upf1           "inputs"
    node_types,merge_timing1  "merge_timing"
    node_types,power_opt1     "power_opt"
    node_types,post_merge1    "post_merge"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1       "Gate-level netlist input"
    node_descriptions,sdc1           "SDC timing constraints input"
    node_descriptions,upf1           "UPF power intent input"
    node_descriptions,merge_timing1  "Merge timing data and constraints (4 subnodes: setup, run, validate, finish)"
    node_descriptions,power_opt1     "Power optimization and clock gating (4 subnodes: setup, run, validate, finish)"
    node_descriptions,post_merge1    "Post-optimization merging and cleanup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1  "Release power optimization deliverables (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    runtime,timeout,netlist1       10
    runtime,timeout,sdc1           10
    runtime,timeout,upf1           10
    runtime,timeout,merge_timing1  30
    runtime,timeout,power_opt1     90
    runtime,timeout,post_merge1    20
    runtime,timeout,release_data1  15
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,upf1,upf "upf_inputs"

    critical_files,merge_timing1 {popt(input,netlist) popt(input,sdc_func_file)}
    critical_files,power_opt1    {popt(input,netlist) popt(input,upf_file)}

    mandatory_outputs,power_opt1  {results/power_opt/optimized_netlist.v results/power_opt/power_report.rpt}
    mandatory_outputs,post_merge1 {results/merge/final_netlist.v}

    mandatory_input_groups {
        netlist_inputs {popt(input,netlist)}
        sdc_inputs {popt(input,sdc_release_tag) popt(input,sdc_release_dir) popt(input,sdc_func_file)}
        upf_inputs {popt(input,upf_release_tag) popt(input,upf_release_dir) popt(input,upf_file)}
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    release_types,optimization,description "Power optimization reports and optimized netlists"
    release_types,optimization,files {
        "results/power_opt/optimized_netlist.v" "netlist/power_optimized_netlist.v"
        "results/power_opt/power_report.rpt" "reports/power_optimization.rpt"
        "results/merge/final_netlist.v" "netlist/final_optimized_netlist.v"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        OUTPUTS                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    output,report_dir          "reports/popt"
    output,results_dir         "results/popt"
    output,work_dir            "work/POPT"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set popt {
    supported_tools {pt joules}
    default_tool    "pt"
}

# Source tool-specific configuration
# Tool is set via: user_config popt(tool,name) or defaults to popt(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists popt(tool,name)] ? $popt(tool,name) : $popt(default_tool)}]

set _tool_config "$_node_config_dir/POPT_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $popt(supported_tools)"
    exit 1
}
