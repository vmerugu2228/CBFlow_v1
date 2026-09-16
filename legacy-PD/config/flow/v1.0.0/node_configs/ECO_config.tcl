#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              ECO Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (FC, Innovus).
# Tool-specific settings sourced from ECO_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    stages {netlist1 def1 sdc1 library1 eco1 export_db1}

    merge_entry_stage     netlist1
    merge_handoff_stage   export_db1
    merge_parallel_stages {}

    dependencies,netlist1    {}
    dependencies,def1        {}
    dependencies,sdc1        {}
    dependencies,library1    {}
    dependencies,eco1        {netlist1 def1 sdc1 library1}
    dependencies,export_db1  {eco1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _eco_exec_stages {eco1 export_db1}
foreach _s $_eco_exec_stages {
    set eco(subnodes,$_s) {setup run validate finish}
    set eco(subnode_dependencies,${_s},setup)    {}
    set eco(subnode_dependencies,${_s},run)      {setup}
    set eco(subnode_dependencies,${_s},validate) {run}
    set eco(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set eco(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    stage_types,netlist1    "inputs"
    stage_types,def1        "inputs"
    stage_types,sdc1        "inputs"
    stage_types,library1    "inputs"
    stage_types,eco1        "execution"
    stage_types,export_db1  "export_data"

    node_types,netlist1    "inputs"
    node_types,def1        "inputs"
    node_types,sdc1        "inputs"
    node_types,library1    "inputs"
    node_types,eco1        "eco"
    node_types,export_db1  "export_db"

    node_descriptions,netlist1    "Gate-level netlist input"
    node_descriptions,def1        "DEF floorplan input"
    node_descriptions,sdc1        "SDC timing constraints input"
    node_descriptions,library1    "Technology library input"
    node_descriptions,eco1        "Engineering change orders implementation and validation (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_db1  "Export ECO database and deliverables (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    runtime,timeout,netlist1    10
    runtime,timeout,def1        10
    runtime,timeout,sdc1        10
    runtime,timeout,library1    10
    runtime,timeout,eco1        45
    runtime,timeout,export_db1  20
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    critical_files,eco1 {eco(input,netlist) eco(input,def_file) eco(input,sdc_func_file)}

    mandatory_outputs,eco1       {results/eco/eco_netlist.v results/eco/eco_changes.rpt}
    mandatory_outputs,export_db1 {results/db/eco.db}

    mandatory_input_groups {
        netlist_inputs {eco(input,netlist)}
        sdc_inputs {eco(input,sdc_release_tag) eco(input,sdc_release_dir) eco(input,sdc_func_file)}
        def_inputs {eco(input,def_file)}
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    release_types,eco,description "ECO deliverables for design implementation"
    release_types,eco,files {
        "results/eco/eco_netlist.v" "netlist/eco_netlist.v"
        "results/eco/eco_changes.rpt" "reports/eco_changes.rpt"
        "results/db/eco.db" "db/eco_database.db"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON ECO CONTROL                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    input,change_file          ""
    input,reference_database   ""
    output,block_labeling      true
    output,report_dir          "reports/eco"
    output,results_dir         "results/eco"
    output,work_dir            "work/ECO"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco {
    supported_tools {fc innovus}
    default_tool    "fc"
}

# Source tool-specific configuration
# Tool is set via: user_config eco(tool,name) or defaults to eco(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists eco(tool,name)] ? $eco(tool,name) : $eco(default_tool)}]

set _tool_config "$_node_config_dir/ECO_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $eco(supported_tools)"
    exit 1
}
