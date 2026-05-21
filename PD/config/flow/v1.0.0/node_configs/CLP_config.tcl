#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              CLP Flow Configuration (Tool-Independent)                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (VC_LP, Conformal LP).
# Tool-specific settings sourced from CLP_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    stages {netlist1 upf1 power_spec1 clp1 release_data1}

    merge_entry_stage     netlist1
    merge_handoff_stage   clp1
    merge_parallel_stages {release_data1}

    dependencies,netlist1     {}
    dependencies,upf1         {}
    dependencies,power_spec1  {}
    dependencies,clp1         {netlist1 upf1 power_spec1}
    dependencies,release_data1 {clp1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _clp_exec_stages {clp1 release_data1}
foreach _s $_clp_exec_stages {
    set clp(subnodes,$_s) {setup run validate finish}
    set clp(subnode_dependencies,${_s},setup)    {}
    set clp(subnode_dependencies,${_s},run)      {setup}
    set clp(subnode_dependencies,${_s},validate) {run}
    set clp(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set clp(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    stage_types,netlist1     "inputs"
    stage_types,upf1         "inputs"
    stage_types,power_spec1  "inputs"
    stage_types,clp1         "execution"
    stage_types,release_data1 "release_data"

    node_types,netlist1     "inputs"
    node_types,upf1         "inputs"
    node_types,power_spec1  "inputs"
    node_types,clp1         "clp"
    node_types,release_data1 "release_data"

    node_descriptions,netlist1     "Gate-level netlist input"
    node_descriptions,upf1         "UPF power intent input"
    node_descriptions,power_spec1  "Power specification input"
    node_descriptions,clp1         "Conformal low power verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release CLP deliverables (4 subnodes: setup, run, validate, finish)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    runtime,timeout,netlist1     10
    runtime,timeout,upf1         10
    runtime,timeout,power_spec1  10
    runtime,timeout,clp1         60
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,upf1,upf "upf_inputs"
    subnode_input_types,power_spec1,power_spec "power_spec_inputs"

    critical_files,clp1 {clp(input,netlist) clp(input,upf_file)}

    mandatory_outputs,clp1 {results/clp/power_verification.rpt}

    mandatory_input_groups {
        netlist_inputs {clp(input,netlist)}
        upf_inputs {clp(input,upf_release_tag) clp(input,upf_release_dir) clp(input,upf_file)}
        power_spec_inputs {clp(input,power_spec)}
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    release_types,verification,description "Conformal low power verification reports and database"
    release_types,verification,files {
        "results/clp/power_verification.rpt" "reports/clp_verification.rpt"
        "results/db/clp_verification.db" "db/clp_verification.db"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        OUTPUTS                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    output,report_dir          "reports/clp"
    output,results_dir         "results/clp"
    output,work_dir            "work/CLP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set clp {
    supported_tools {vc_lp conformal_lp}
    default_tool    "vc_lp"
}

# Source tool-specific configuration
# Tool is set via: user_config clp(tool,name) or defaults to clp(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists clp(tool,name)] ? $clp(tool,name) : $clp(default_tool)}]

set _tool_config "$_node_config_dir/CLP_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $clp(supported_tools)"
    exit 1
}
