#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              FP Flow Configuration (Tool-Independent)                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Innovus).
# Tool-specific settings sourced from FP_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    stages {netlist1 sdc1 def1 upf1 library1 init_design1 import_design1 floorplan1 powerplan1 place_pins1 export_data1 release_data1}

    merge_entry_stage     netlist1
    merge_handoff_stage   export_data1
    merge_parallel_stages {release_data1}

    dependencies,netlist1          {}
    dependencies,sdc1              {}
    dependencies,def1              {}
    dependencies,upf1              {}
    dependencies,library1          {}
    dependencies,init_design1      {netlist1 sdc1 def1 upf1 library1}
    dependencies,import_design1    {init_design1}
    dependencies,floorplan1        {import_design1}
    dependencies,powerplan1        {floorplan1}
    dependencies,place_pins1       {powerplan1}
    dependencies,export_data1      {place_pins1}
    dependencies,release_data1     {export_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _fp_exec_stages {init_design1 import_design1 floorplan1 powerplan1 place_pins1 export_data1 release_data1}
foreach _s $_fp_exec_stages {
    set fp(subnodes,$_s) {setup run validate finish}
    set fp(subnode_dependencies,${_s},setup)    {}
    set fp(subnode_dependencies,${_s},run)      {setup}
    set fp(subnode_dependencies,${_s},validate) {run}
    set fp(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set fp(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    node_types,netlist1          "inputs"
    node_types,sdc1              "inputs"
    node_types,def1              "inputs"
    node_types,upf1              "inputs"
    node_types,library1          "inputs"
    node_types,init_design1      "init_design"
    node_types,import_design1    "import_design"
    node_types,floorplan1        "floorplan"
    node_types,powerplan1        "powerplan"
    node_types,place_pins1       "place_pins"
    node_types,export_data1      "export_data"
    node_types,release_data1     "release_data"

    stage_types,netlist1         "inputs"
    stage_types,sdc1             "inputs"
    stage_types,def1             "inputs"
    stage_types,upf1             "inputs"
    stage_types,library1         "inputs"
    stage_types,init_design1     "execution"
    stage_types,import_design1   "execution"
    stage_types,floorplan1       "execution"
    stage_types,powerplan1       "execution"
    stage_types,place_pins1      "execution"
    stage_types,export_data1     "export_data"
    stage_types,release_data1    "release_data"

    node_descriptions,netlist1          "Gate-level netlist input"
    node_descriptions,sdc1              "SDC timing constraints input"
    node_descriptions,def1              "DEF floorplan input"
    node_descriptions,upf1              "UPF power intent input"
    node_descriptions,library1          "Technology library input"
    node_descriptions,init_design1      "Design library creation, RTL/netlist load, technology setup"
    node_descriptions,import_design1    "Early compile for area estimation"
    node_descriptions,floorplan1        "Floorplan creation: initialize, macros, boundaries, tap cells"
    node_descriptions,powerplan1        "Power network synthesis and stdcell placement"
    node_descriptions,place_pins1       "Pin placement and legalization"
    node_descriptions,export_data1      "Export floorplan DEF, netlist, and data"
    node_descriptions,release_data1     "Release FP deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    runtime,timeout,netlist1          10
    runtime,timeout,sdc1              10
    runtime,timeout,def1              10
    runtime,timeout,upf1              10
    runtime,timeout,library1          10
    runtime,timeout,init_design1      30
    runtime,timeout,import_design1    60
    runtime,timeout,floorplan1        90
    runtime,timeout,powerplan1        60
    runtime,timeout,place_pins1       30
    runtime,timeout,export_data1      20
    runtime,timeout,release_data1     15
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,def1,def "def_inputs"
    subnode_input_types,upf1,upf "upf_inputs"
    subnode_input_types,library1,library "library_inputs"

    mandatory_input_groups {
        netlist_inputs {fp(input,netlist)}
        sdc_inputs {fp(input,sdc_release_tag) fp(input,sdc_release_dir) fp(input,sdc_func_file)}
        def_inputs {fp(input,def_file)}
        upf_inputs {fp(input,upf_release_tag) fp(input,upf_release_dir) fp(input,upf_file)}
    }

    mandatory_user_inputs {
        fp(input,netlist)
        fp(input,sdc_func_file)
    }

    output,write_def            true
    output,write_floorplan      true
    output,floorplan_dir        "results/fp"
    output,report_dir           "reports/fp"
    output,work_dir             "work/FP"
    input,macro_placement_file  ""
    input,io_constraint_file    ""
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        FILE REQUIREMENTS & RELEASE                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    critical_files,import_design1 {fp(input,netlist)}
    critical_files,floorplan1     {fp(input,netlist) fp(input,def_file)}
    critical_files,powerplan1     {fp(input,upf_file)}

    mandatory_outputs,import_design1 {results/design/design_imported.def}
    mandatory_outputs,floorplan1     {results/floorplan/floorplan.def results/floorplan/io_placement.rpt}
    mandatory_outputs,powerplan1     {results/powerplan/power_grid.def results/powerplan/power_analysis.rpt}

    release_types,floorplan,description "Floorplan deliverables for place and route"
    release_types,floorplan,files {
        "results/floorplan/floorplan.def" "def/floorplan.def"
        "results/powerplan/power_grid.def" "def/powerplan.def"
        "results/post_fp/final_floorplan.def" "def/final_floorplan.def"
        "results/floorplan/io_placement.rpt" "reports/io_placement.rpt"
        "results/powerplan/power_analysis.rpt" "reports/power_analysis.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fp {
    supported_tools {fc innovus}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config fp(tool,name) or defaults to fp(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists fp(tool,name)] ? $fp(tool,name) : $fp(default_tool)}]

set _tool_config "$_node_config_dir/FP_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $fp(supported_tools)"
    exit 1
}
