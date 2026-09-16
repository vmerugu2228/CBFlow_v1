#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SCAN_INSERT Flow Configuration (Tool-Independent)                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Logical netlist → scan-stitched netlist + scandef. Common for Tessent and DFT
# Compiler. Tool-specific settings sourced from SCAN_INSERT_<tool>_config.tcl.

array set scan_insert {
    stages {netlist1 sdc1 lib1 init_scan1 scan_stitch1 scan_check1 scan_export1 release_data1}

    dependencies,netlist1       {}
    dependencies,sdc1           {}
    dependencies,lib1           {}
    dependencies,init_scan1     {netlist1 sdc1 lib1}
    dependencies,scan_stitch1   {init_scan1}
    dependencies,scan_check1    {scan_stitch1}
    dependencies,scan_export1   {scan_check1}
    dependencies,release_data1  {scan_export1}
}

set _scan_insert_exec_stages {init_scan1 scan_stitch1 scan_check1 scan_export1 release_data1}
foreach _s $_scan_insert_exec_stages {
    set scan_insert(subnodes,$_s) {setup run validate finish}
    set scan_insert(subnode_dependencies,${_s},setup)    {}
    set scan_insert(subnode_dependencies,${_s},run)      {setup}
    set scan_insert(subnode_dependencies,${_s},validate) {run}
    set scan_insert(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set scan_insert(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

array set scan_insert {
    stage_types,netlist1       "inputs"
    stage_types,sdc1           "inputs"
    stage_types,lib1           "inputs"
    stage_types,init_scan1     "execution"
    stage_types,scan_stitch1   "execution"
    stage_types,scan_check1    "execution"
    stage_types,scan_export1   "execution"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,sdc1           "inputs"
    node_types,lib1           "inputs"
    node_types,init_scan1     "init_scan"
    node_types,scan_stitch1   "scan_stitch"
    node_types,scan_check1    "scan_check"
    node_types,scan_export1   "scan_export"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1       "Pre-scan logical netlist input"
    node_descriptions,sdc1           "SDC constraints input"
    node_descriptions,lib1           "Technology library input"
    node_descriptions,init_scan1     "Initialize scan environment, read netlist"
    node_descriptions,scan_stitch1   "Stitch flops into scan chains, generate scandef"
    node_descriptions,scan_check1    "Scan DRC and shift/capture analysis"
    node_descriptions,scan_export1   "Export scan-inserted netlist and scandef"
    node_descriptions,release_data1  "Release scan-insertion deliverables"

    mmmc,enabled            false

    runtime,timeout,netlist1       10
    runtime,timeout,sdc1           10
    runtime,timeout,lib1           10
    runtime,timeout,init_scan1     20
    runtime,timeout,scan_stitch1   45
    runtime,timeout,scan_check1    30
    runtime,timeout,scan_export1   15
    runtime,timeout,release_data1  10

    mandatory_input_groups {
        netlist_inputs {scan_insert(input,netlist)}
        sdc_inputs     {scan_insert(input,sdc)}
    }
    mandatory_user_inputs {
        scan_insert(input,netlist)
    }

    output,report_dir   "reports/scan_insert"
    output,results_dir  "results/scan_insert"
    output,work_dir     "work/SCAN_INSERT"

    supported_tools {tessent dft_compiler}
    default_tool    "tessent"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists scan_insert(tool,name)] ? $scan_insert(tool,name) : $scan_insert(default_tool)}]
set _tool_config "$_node_config_dir/SCAN_INSERT_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config } else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $scan_insert(supported_tools)"
    exit 1
}
