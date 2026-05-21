#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              STA Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (PT, Tempus).
# Tool-specific settings sourced from STA_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    stages {netlist1 sdc1 spef1 library1 extraction1 timing1 reporting1 release_data1}

    dependencies,netlist1       {}
    dependencies,sdc1           {}
    dependencies,spef1          {}
    dependencies,library1       {}
    dependencies,extraction1    {netlist1 sdc1 spef1 library1}
    dependencies,timing1        {extraction1}
    dependencies,reporting1     {timing1}
    dependencies,release_data1  {reporting1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Dynamic subnodes for extraction and timing (per-scenario parallelism)
array set sta {
    subnodes,extraction1    {dynamic}
    subnodes,timing1        {dynamic}

    subnode_dependencies,extraction1,dynamic {}
    subnode_dependencies,timing1,dynamic {}
}

# Execution stages with standard 4-subnode pattern
set _sta_exec_stages {reporting1 release_data1}
foreach _s $_sta_exec_stages {
    set sta(subnodes,$_s) {setup run validate finish}
    set sta(subnode_dependencies,${_s},setup)    {}
    set sta(subnode_dependencies,${_s},run)      {setup}
    set sta(subnode_dependencies,${_s},validate) {run}
    set sta(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set sta(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    stage_types,netlist1       "inputs"
    stage_types,sdc1           "inputs"
    stage_types,spef1          "inputs"
    stage_types,library1       "inputs"
    stage_types,extraction1    "execution"
    stage_types,timing1        "execution"
    stage_types,reporting1     "execution"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,sdc1           "inputs"
    node_types,spef1          "inputs"
    node_types,library1       "inputs"
    node_types,extraction1    "extraction"
    node_types,timing1        "timing"
    node_types,reporting1     "reporting"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1       "Gate-level netlist input"
    node_descriptions,sdc1           "SDC timing constraints input"
    node_descriptions,spef1          "SPEF parasitic data input"
    node_descriptions,library1       "Technology library input"
    node_descriptions,extraction1    "Per-RC-corner parasitic extraction (dynamic: rc_max, rc_typ, rc_min run in parallel)"
    node_descriptions,timing1        "Dynamic per-scenario timing analysis - each scenario runs setup+hold (parallelizable via make -j)"
    node_descriptions,reporting1     "Cross-corner aggregation - worst-case analysis, MMMC timing summary (4 subnodes)"
    node_descriptions,release_data1  "Package and release final timing sign-off deliverables (4 subnodes)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    mmmc,enabled            true
    mmmc,enabled_stages     {extraction1 timing1 reporting1}
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set       "signoff"
    mmmc,dynamic_scenarios  true
    mmmc,parallel_scenarios true

    runtime,timeout,netlist1       10
    runtime,timeout,sdc1           10
    runtime,timeout,spef1          10
    runtime,timeout,library1       10
    runtime,timeout,extraction1    30
    runtime,timeout,timing1        60
    runtime,timeout,reporting1     20
    runtime,timeout,release_data1  10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    critical_files,extraction1    {sta(input,netlist) sta(input,sdc_func_file)}
    critical_files,timing1        {sta(input,netlist) sta(input,spef) sta(input,sdc_func_file)}
    critical_files,reporting1     {}
    critical_files,release_data1  {}

    mandatory_outputs,extraction1    {results/extraction/parasitic.spef}
    mandatory_outputs,timing1        {}
    mandatory_outputs,reporting1     {reports/sta/mmmc_timing_summary.rpt}

    mandatory_input_groups {
        netlist_inputs {sta(input,netlist)}
        sdc_inputs {sta(input,sdc_release_tag) sta(input,sdc_release_dir) sta(input,sdc_func_file)}
        spef_inputs {sta(input,spef)}
    }

    mmmc_reports,base              {mmmc_timing mmmc_scenarios}
    mmmc_reports,timing1           {mmmc_hold_timing mmmc_hold_violations}
    mmmc_reports,reporting1        {mmmc_final_summary mmmc_cross_corner}

    merge_parallel_stages {release_data1}

    output,report_dir          "reports/sta"
    output,results_dir         "results/sta"
    output,work_dir            "work/STA"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    release_types,timing,description "MMMC timing analysis reports and sign-off data"
    release_types,timing,files {
        "reports/sta/mmmc_timing_summary.rpt"     "reports/final_mmmc_timing.rpt"
        "reports/sta/mmmc_hold_summary.rpt"         "reports/hold_timing_summary.rpt"
        "results/extraction/parasitic.spef"         "spef/final_parasitic.spef"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON ANALYSIS CONTROL                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    reporting,top_violations   50
    reporting,include_input_pins true
    reporting,include_nets     true
    reporting,report_format    "rpt"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set sta {
    supported_tools {pt tempus}
    default_tool    "pt"
}

# Source tool-specific configuration
# Tool is set via: user_config sta(tool,name) or defaults to sta(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists sta(tool,name)] ? $sta(tool,name) : $sta(default_tool)}]

set _tool_config "$_node_config_dir/STA_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $sta(supported_tools)"
    exit 1
}
