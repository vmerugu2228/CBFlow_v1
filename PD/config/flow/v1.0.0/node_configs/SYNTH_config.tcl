#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              SYNTH Flow Configuration (Tool-Independent)                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Genus).
# Tool-specific settings sourced from SYNTH_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    stages {rtl1 sdc1 upf1 synthesis1 export_data1 release_data1}

    dependencies,rtl1             {}
    dependencies,sdc1             {}
    dependencies,upf1             {}
    dependencies,synthesis1       {rtl1 sdc1 upf1}
    dependencies,export_data1     {synthesis1}
    dependencies,release_data1    {export_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _synth_exec_stages {synthesis1 export_data1 release_data1}
foreach _s $_synth_exec_stages {
    set synth(subnodes,$_s) {setup run validate finish}
    set synth(subnode_dependencies,${_s},setup)    {}
    set synth(subnode_dependencies,${_s},run)      {setup}
    set synth(subnode_dependencies,${_s},validate) {run}
    set synth(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set synth(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    node_types,rtl1           "inputs"
    node_types,sdc1           "inputs"
    node_types,upf1           "inputs"
    node_types,synthesis1     "synthesis"
    node_types,export_data1   "export_data"
    node_types,release_data1  "release_data"

    stage_types,rtl1          "inputs"
    stage_types,sdc1          "inputs"
    stage_types,upf1          "inputs"
    stage_types,synthesis1    "execution"
    stage_types,export_data1  "export_data"
    stage_types,release_data1 "release_data"

    node_descriptions,rtl1           "RTL source input"
    node_descriptions,sdc1           "SDC timing constraints input"
    node_descriptions,upf1           "UPF power intent input"
    node_descriptions,synthesis1     "Library setup, RTL read, elaboration, compile and optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1   "Export synthesis data and results (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1  "Release synthesis deliverables (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MMMC & RUNTIME                                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    mmmc,enabled              true
    mmmc,enabled_stages       {synthesis1}
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set         "signoff"
    mmmc,multi_corner_compile true

    runtime,timeout,rtl1             10
    runtime,timeout,sdc1             10
    runtime,timeout,upf1             10
    runtime,timeout,synthesis1       150
    runtime,timeout,export_data1     15
    runtime,timeout,release_data1    10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    subnode_input_types,rtl1,rtl "rtl_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,upf1,upf "upf_inputs"

    mandatory_input_groups {
        rtl_inputs {synth(input,rtl_release_tag) synth(input,rtl_release_dir) synth(input,rtl_filelist)}
        sdc_inputs {synth(input,sdc_release_tag) synth(input,sdc_release_dir) synth(input,sdc_func_file)}
        upf_inputs {synth(input,upf_release_tag) synth(input,upf_release_dir) synth(input,upf_file)}
    }

    mandatory_user_inputs {
        synth(input,rtl_filelist)
        synth(input,sdc_func_file)
    }

    chip_type "flat"

    input,format              "verilog"
    input,rtl_format          "sverilog"
    input,rtl_release_tag     ""
    input,rtl_release_dir     ""
    input,rtl_filelist        ""
    input,sdc_release_tag     ""
    input,sdc_release_dir     ""
    input,sdc_func_file       ""
    input,sdc_scan_file       ""
    input,sdc_test_file       ""
    input,sdc_dft_file        ""
    input,upf_release_tag     ""
    input,upf_release_dir     ""
    input,upf_file            ""

    output,netlist_dir        "results/synth"
    output,report_dir         "reports/synth"
    output,work_dir           "work/SYNTH"
    output,block_labeling     true
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON SYNTHESIS CONTROL                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    strategy                  "balanced"
    effort                    "medium"
    effort,mapping            "medium"
    effort,timing             "medium"
    effort,area               "medium"

    design,top_module         ""
    design,target_library     ""
    design,link_library       ""

    constraints,max_fanout       "64"
    constraints,max_transition   "0.5"
    constraints,max_capacitance  "1.0"
    constraints,input_delay      "0.2"
    constraints,output_delay     "0.2"

    optimization,hold_fix     "false"
    optimization,multi_vt     "false"
    optimization,clock_gating "true"
    optimization,power_gating "false"
    optimization,leakage_power "false"

    area,recover_design_area  "false"
    area,target_utilization   "0.7"
    area,max_utilization      "0.8"

    power,effort                    "none"
    power,clock_gating              "true"
    power,operand_isolation         "false"
    power,multi_vt_optimization     "false"
    power,dynamic_voltage_scaling   "false"

    analysis,max_paths         100
    analysis,significant_digits 4
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        FILE REQUIREMENTS & RELEASE                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    critical_files,synthesis1    {synth(input,rtl_files) synth(input,sdc_file)}

    mandatory_outputs,synthesis1    {results/netlist/synth.v results/sdc/synth.sdc}
    mandatory_outputs,export_data1 {results/db/synth.db}

    release_types,synthesis1,description "Synthesis deliverables for RTL handoff"
    release_types,synthesis1,files {
        "results/netlist/synth.v" "netlist/synthesis_netlist.v"
        "results/sdc/synth.sdc" "sdc/synthesis_constraints.sdc"
        "reports/synthesis/timing.rpt" "reports/synthesis_timing.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set synth {
    supported_tools {fc genus}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config synth(tool,name) or defaults to synth(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists synth(tool,name)] ? $synth(tool,name) : $synth(default_tool)}]

set _tool_config "$_node_config_dir/SYNTH_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $synth(supported_tools)"
    exit 1
}
