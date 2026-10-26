#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              FCFP Flow Configuration (Tool-Independent)                     ║
# ║              Hierarchical Design Planning                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Innovus).
# Tool-specific settings sourced from FCFP_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    stages {netlist1 sdc1 def1 upf1 library1 init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1}

    dependencies,netlist1          {}
    dependencies,sdc1              {}
    dependencies,def1              {}
    dependencies,upf1              {}
    dependencies,library1          {}
    dependencies,init_design1      {netlist1 sdc1 def1 upf1 library1}
    dependencies,commit_blocks1    {init_design1}
    dependencies,init_compile1     {commit_blocks1}
    dependencies,create_floorplan1 {init_compile1}
    dependencies,shaping1          {create_floorplan1}
    dependencies,placement1        {shaping1}
    dependencies,create_power1     {placement1}
    dependencies,place_pins1       {create_power1}
    dependencies,top_compile1      {place_pins1}
    dependencies,timing_budget1    {top_compile1}
    dependencies,export_data1      {timing_budget1}
    dependencies,release_data1     {export_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _fcfp_exec_stages {init_design1 commit_blocks1 init_compile1 create_floorplan1 shaping1 placement1 create_power1 place_pins1 top_compile1 timing_budget1 export_data1 release_data1}
foreach _s $_fcfp_exec_stages {
    set fcfp(subnodes,$_s) {setup run validate finish}
    set fcfp(subnode_dependencies,${_s},setup)    {}
    set fcfp(subnode_dependencies,${_s},run)      {setup}
    set fcfp(subnode_dependencies,${_s},validate) {run}
    set fcfp(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set fcfp(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    node_types,netlist1          "inputs"
    node_types,sdc1              "inputs"
    node_types,def1              "inputs"
    node_types,upf1              "inputs"
    node_types,library1          "inputs"
    node_types,init_design1      "init_design"
    node_types,commit_blocks1    "commit_blocks"
    node_types,init_compile1     "init_compile"
    node_types,create_floorplan1 "create_floorplan"
    node_types,shaping1          "shaping"
    node_types,placement1        "placement"
    node_types,create_power1     "create_power"
    node_types,place_pins1       "place_pins"
    node_types,top_compile1      "top_compile"
    node_types,timing_budget1    "timing_budget"
    node_types,export_data1      "export_data"
    node_types,release_data1     "release_data"

    stage_types,netlist1          "inputs"
    stage_types,sdc1              "inputs"
    stage_types,def1              "inputs"
    stage_types,upf1              "inputs"
    stage_types,library1          "inputs"
    stage_types,init_design1      "execution"
    stage_types,commit_blocks1    "execution"
    stage_types,init_compile1     "execution"
    stage_types,create_floorplan1 "execution"
    stage_types,shaping1          "execution"
    stage_types,placement1        "execution"
    stage_types,create_power1     "execution"
    stage_types,place_pins1       "execution"
    stage_types,top_compile1      "execution"
    stage_types,timing_budget1    "execution"
    stage_types,export_data1      "export_data"
    stage_types,release_data1     "release_data"

    node_descriptions,netlist1          "Gate-level netlist input"
    node_descriptions,sdc1              "SDC timing constraints input"
    node_descriptions,def1              "DEF floorplan input"
    node_descriptions,upf1              "UPF power intent input"
    node_descriptions,library1          "Technology library input"
    node_descriptions,init_design1      "Hier DP init: create_lib, read RTL/netlist, UPF, SDC"
    node_descriptions,commit_blocks1    "Commit block references, split constraints"
    node_descriptions,init_compile1     "Initial hierarchical compile for area estimation"
    node_descriptions,create_floorplan1 "Initialize floorplan, macro placement, boundary/tap cells"
    node_descriptions,shaping1          "Shape hierarchical block outlines and channels"
    node_descriptions,placement1        "Hierarchical block and macro placement"
    node_descriptions,create_power1     "Power network synthesis and PG routing"
    node_descriptions,place_pins1       "Pin placement and legalization"
    node_descriptions,top_compile1      "Top-level compile and optimization"
    node_descriptions,timing_budget1    "Timing budget creation and distribution"
    node_descriptions,export_data1      "Export hierarchical design data"
    node_descriptions,release_data1     "Release FCFP deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    runtime,timeout,netlist1          10
    runtime,timeout,sdc1              10
    runtime,timeout,def1              10
    runtime,timeout,upf1              10
    runtime,timeout,library1          10
    runtime,timeout,init_design1      30
    runtime,timeout,commit_blocks1    30
    runtime,timeout,init_compile1     90
    runtime,timeout,create_floorplan1 60
    runtime,timeout,shaping1          45
    runtime,timeout,placement1        60
    runtime,timeout,create_power1     60
    runtime,timeout,place_pins1       30
    runtime,timeout,top_compile1      90
    runtime,timeout,timing_budget1    45
    runtime,timeout,export_data1      20
    runtime,timeout,release_data1     15
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        OUTPUTS                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    output,write_def            true
    output,write_floorplan      true
    output,report_dir           "reports/fcfp"
    output,results_dir          "results/fcfp"
    output,work_dir             "work/FCFP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    release_types,floorplan,description "FCFP hierarchical floorplan deliverables"
    release_types,floorplan,files {
        "work/FCFP/export_data1/reports/report_qor.rpt"  "reports/fcfp_qor.rpt"
        "work/FCFP/placement1/reports/report_timing.max.rpt" "reports/fcfp_timing.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set fcfp {
    supported_tools {fc innovus}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config fcfp(tool,name) or defaults to fcfp(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists fcfp(tool,name)] ? $fcfp(tool,name) : $fcfp(default_tool)}]

set _tool_config "$_node_config_dir/FCFP_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $fcfp(supported_tools)"
    exit 1
}
