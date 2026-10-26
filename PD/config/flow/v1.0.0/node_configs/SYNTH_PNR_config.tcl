#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              SYNTH_PNR Flow Configuration (Tool-Independent)                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Innovus).
# Tool-specific settings sourced from SYNTH_PNR_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth_pnr {
    stages {rtl1 sdc1 upf1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}

    dependencies,rtl1             {}
    dependencies,sdc1             {}
    dependencies,upf1             {}
    dependencies,init_design1     {rtl1 sdc1 upf1}
    dependencies,synthesis1       {init_design1}
    dependencies,place1           {synthesis1}
    dependencies,cts1             {place1}
    dependencies,cts_opt1         {cts1}
    dependencies,route1           {cts_opt1}
    dependencies,pro1             {route1}
    dependencies,signoff1         {pro1}
    dependencies,export_data1     {signoff1}
    dependencies,release_data1    {export_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _synth_pnr_exec_stages {init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
foreach _s $_synth_pnr_exec_stages {
    set synth_pnr(subnodes,$_s) {setup run validate finish}
    set synth_pnr(subnode_dependencies,${_s},setup)    {}
    set synth_pnr(subnode_dependencies,${_s},run)      {setup}
    set synth_pnr(subnode_dependencies,${_s},validate) {run}
    set synth_pnr(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set synth_pnr(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth_pnr {
    node_types,rtl1           "inputs"
    node_types,sdc1           "inputs"
    node_types,upf1           "inputs"
    node_types,init_design1   "init_design"
    node_types,synthesis1     "synthesis"
    node_types,place1         "place"
    node_types,cts1           "cts"
    node_types,cts_opt1       "cts_opt"
    node_types,route1         "route"
    node_types,pro1           "pro"
    node_types,signoff1       "signoff"
    node_types,export_data1   "export_data"
    node_types,release_data1  "release_data"

    stage_types,rtl1          "inputs"
    stage_types,sdc1          "inputs"
    stage_types,upf1          "inputs"
    stage_types,init_design1  "execution"
    stage_types,synthesis1    "execution"
    stage_types,place1        "execution"
    stage_types,cts1          "execution"
    stage_types,cts_opt1      "execution"
    stage_types,route1        "execution"
    stage_types,pro1          "execution"
    stage_types,signoff1      "execution"
    stage_types,export_data1  "export_data"
    stage_types,release_data1 "release_data"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth_pnr {
    mmmc,enabled              true
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set         "signoff"
    mmmc,multi_corner_compile true

    runtime,timeout,rtl1             10
    runtime,timeout,sdc1             10
    runtime,timeout,upf1             10
    runtime,timeout,init_design1     30
    runtime,timeout,synthesis1       180
    runtime,timeout,place1           180
    runtime,timeout,cts1             120
    runtime,timeout,cts_opt1         120
    runtime,timeout,route1           240
    runtime,timeout,pro1             180
    runtime,timeout,signoff1         90
    runtime,timeout,export_data1     30
    runtime,timeout,release_data1    20
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth_pnr {
    subnode_input_types,rtl1,rtl "rtl_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,upf1,upf "upf_inputs"

    mandatory_user_inputs {
        synth_pnr(input,rtl_filelist)
        synth_pnr(input,rtl_format)
        synth_pnr(input,sdc_func_file)
        synth_pnr(input,upf_file)
    }

    chip_type "flat"

    output,netlist_dir    "results/synth_pnr"
    output,report_dir     "reports/synth_pnr"
    output,work_dir       "work/SYNTH_PNR"
    output,write_gds      true
    output,write_oasis    false
    output,block_labeling true

    release_types,signoff1,description "SYNTH_PNR signoff deliverables for tapeout"
    release_types,signoff1,files {
        "results/gds/final.gds"          "gds/final_layout.gds"
        "results/netlist/final.v"        "netlist/final_netlist.v"
        "results/def/final.def"          "def/final_design.def"
        "results/spef/final.spef"        "spef/final_parasitic.spef"
        "results/timing/final_timing.rpt" "reports/final_timing.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth_pnr {
    supported_tools {fc}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config synth_pnr(tool,name) or defaults to synth_pnr(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists synth_pnr(tool,name)] ? $synth_pnr(tool,name) : $synth_pnr(default_tool)}]

set _tool_config "$_node_config_dir/SYNTH_PNR_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $synth_pnr(supported_tools)"
    exit 1
}
