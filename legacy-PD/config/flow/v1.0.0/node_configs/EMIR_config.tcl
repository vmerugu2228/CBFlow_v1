#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              EMIR Flow Configuration (Tool-Independent)                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (Redhawk, Voltus).
# Tool-specific settings sourced from EMIR_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    stages {netlist1 def1 spef1 library1 power_analysis1 ir_drop1 thermal_analysis1}

    dependencies,netlist1           {}
    dependencies,def1               {}
    dependencies,spef1              {}
    dependencies,library1           {}
    dependencies,power_analysis1    {netlist1 def1 spef1 library1}
    dependencies,ir_drop1           {power_analysis1}
    dependencies,thermal_analysis1  {ir_drop1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _emir_exec_stages {power_analysis1 ir_drop1 thermal_analysis1}
foreach _s $_emir_exec_stages {
    set emir(subnodes,$_s) {setup run validate finish}
    set emir(subnode_dependencies,${_s},setup)    {}
    set emir(subnode_dependencies,${_s},run)      {setup}
    set emir(subnode_dependencies,${_s},validate) {run}
    set emir(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set emir(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    stage_types,netlist1           "inputs"
    stage_types,def1               "inputs"
    stage_types,spef1              "inputs"
    stage_types,library1           "inputs"
    stage_types,power_analysis1    "execution"
    stage_types,ir_drop1           "execution"
    stage_types,thermal_analysis1  "execution"

    node_types,netlist1           "inputs"
    node_types,def1               "inputs"
    node_types,spef1              "inputs"
    node_types,library1           "inputs"
    node_types,power_analysis1    "power_analysis"
    node_types,ir_drop1           "ir_drop"
    node_types,thermal_analysis1  "thermal_analysis"

    node_descriptions,netlist1           "Gate-level netlist input"
    node_descriptions,def1               "DEF floorplan input"
    node_descriptions,spef1              "SPEF parasitic data input"
    node_descriptions,library1           "Technology library input"
    node_descriptions,power_analysis1    "Power consumption analysis and vectorless estimation (4 subnodes: setup, run, validate, finish)"
    node_descriptions,ir_drop1           "IR drop analysis and voltage verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,thermal_analysis1  "Thermal analysis and hotspot identification (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    runtime,timeout,netlist1           10
    runtime,timeout,def1               10
    runtime,timeout,spef1              10
    runtime,timeout,library1           10
    runtime,timeout,power_analysis1    60
    runtime,timeout,ir_drop1           45
    runtime,timeout,thermal_analysis1  30
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    critical_files,power_analysis1    {emir(input,netlist) emir(input,def_file)}
    critical_files,ir_drop1           {emir(input,netlist) emir(input,def_file) emir(input,spef)}
    critical_files,thermal_analysis1  {emir(input,netlist) emir(input,def_file)}

    mandatory_outputs,power_analysis1    {results/power/power.rpt}
    mandatory_outputs,ir_drop1           {results/ir_drop/ir_drop.rpt results/ir_drop/voltage_map.png}
    mandatory_outputs,thermal_analysis1  {results/thermal/thermal.rpt results/thermal/temperature_map.png}

    mandatory_input_groups {
        netlist_inputs {emir(input,netlist)}
        def_inputs {emir(input,def_file)}
        spef_inputs {emir(input,spef)}
    }

    mandatory_user_inputs {
        emir(input,netlist)
        emir(input,def_file)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    release_types,power,description "Power and thermal analysis reports and visualizations"
    release_types,power,files {
        "results/power/power.rpt" "reports/power_analysis.rpt"
        "results/ir_drop/ir_drop.rpt" "reports/ir_drop_analysis.rpt"
        "results/thermal/thermal.rpt" "reports/thermal_analysis.rpt"
        "results/ir_drop/voltage_map.png" "images/voltage_heatmap.png"
        "results/thermal/temperature_map.png" "images/thermal_heatmap.png"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON ANALYSIS CONTROL                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    input,power_activity_file  ""
    ir_drop,threshold          "30"
    ir_drop,enable             true
    thermal,enable             true
    thermal,max_temperature    "125"
    output,report_dir          "reports/emir"
    output,results_dir         "results/emir"
    output,work_dir            "work/EMIR"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set emir {
    supported_tools {redhawk voltus}
    default_tool    "redhawk"
}

# Source tool-specific configuration
# Tool is set via: user_config emir(tool,name) or defaults to emir(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists emir(tool,name)] ? $emir(tool,name) : $emir(default_tool)}]

set _tool_config "$_node_config_dir/EMIR_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $emir(supported_tools)"
    exit 1
}
