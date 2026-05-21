#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              PV Flow Configuration (Tool-Independent)                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Common stages, dependencies, subnodes — same for all tools (ICV, Calibre).
# Tool-specific settings sourced from PV_<tool>_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    stages {netlist1 def1 gds1 fill1 drc1 lvs1 perc1 erc1 xor1 merge_data1 release_data1}

    dependencies,netlist1      {}
    dependencies,def1          {}
    dependencies,gds1          {}
    dependencies,fill1         {netlist1 def1 gds1}
    dependencies,drc1          {fill1}
    dependencies,lvs1          {fill1}
    dependencies,perc1         {fill1}
    dependencies,erc1          {fill1}
    dependencies,xor1          {fill1}
    dependencies,merge_data1   {drc1 lvs1 perc1 erc1 xor1}
    dependencies,release_data1 {merge_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _pv_exec_stages {fill1 drc1 lvs1 perc1 erc1 xor1 merge_data1 release_data1}
foreach _s $_pv_exec_stages {
    set pv(subnodes,$_s) {setup run validate finish}
    set pv(subnode_dependencies,${_s},setup)    {}
    set pv(subnode_dependencies,${_s},run)      {setup}
    set pv(subnode_dependencies,${_s},validate) {run}
    set pv(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set pv(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    stage_types,netlist1       "inputs"
    stage_types,def1           "inputs"
    stage_types,gds1           "inputs"
    stage_types,drc1           "execution"
    stage_types,lvs1           "execution"
    stage_types,fill1          "execution"
    stage_types,perc1          "execution"
    stage_types,erc1           "execution"
    stage_types,xor1           "execution"
    stage_types,merge_data1    "data"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,def1           "inputs"
    node_types,gds1           "inputs"
    node_types,drc1           "drc"
    node_types,lvs1           "lvs"
    node_types,fill1          "fill"
    node_types,perc1          "perc"
    node_types,erc1           "erc"
    node_types,xor1           "xor"
    node_types,merge_data1    "merge_data"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1      "Gate-level netlist input"
    node_descriptions,def1          "DEF floorplan input"
    node_descriptions,gds1          "GDS layout data input"
    node_descriptions,drc1          "Design Rule Check with foundry runset"
    node_descriptions,lvs1          "Layout vs Schematic with netlist comparison"
    node_descriptions,fill1         "Metal Fill (BEOL/FEOL) generation"
    node_descriptions,perc1         "PERC (Parasitic Electrical Rule Check)"
    node_descriptions,erc1          "ERC (Electrical Rule Check)"
    node_descriptions,xor1          "XOR comparison (pre-fill vs post-fill layout)"
    node_descriptions,merge_data1   "Merge filled layout with original design"
    node_descriptions,release_data1 "Package and release PV signoff deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    runtime,timeout,netlist1       10
    runtime,timeout,def1           10
    runtime,timeout,gds1           10
    runtime,timeout,fill1          60
    runtime,timeout,drc1           90
    runtime,timeout,lvs1           60
    runtime,timeout,erc1           45
    runtime,timeout,perc1          30
    runtime,timeout,xor1           30
    runtime,timeout,merge_data1    15
    runtime,timeout,release_data1  10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,def1,def "def_inputs"
    subnode_input_types,gds1,gds "gds_inputs"

    critical_files,drc1  {pv(input,gds)}
    critical_files,lvs1  {pv(input,netlist) pv(input,gds)}
    critical_files,erc1  {pv(input,gds)}
    critical_files,perc1 {pv(input,gds)}

    mandatory_outputs,drc1        {results/drc/drc.rpt}
    mandatory_outputs,lvs1        {results/lvs/lvs.rpt}
    mandatory_outputs,erc1        {results/erc/erc.rpt}
    mandatory_outputs,perc1       {results/perc/perc.rpt}
    mandatory_outputs,merge_data1 {results/verification/verification_summary.rpt}

    mandatory_input_groups {
        netlist_inputs {pv(input,netlist)}
        def_inputs {pv(input,def_file)}
        gds_inputs {pv(input,gds)}
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    release_types,verification,description "Physical verification reports and sign-off data"
    release_types,verification,files {
        "results/drc/drc.rpt" "reports/drc_verification.rpt"
        "results/lvs/lvs.rpt" "reports/lvs_verification.rpt"
        "results/erc/erc.rpt" "reports/erc_verification.rpt"
        "results/perc/perc.rpt" "reports/perc_verification.rpt"
        "results/verification/verification_summary.rpt" "reports/verification_summary.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON VERIFICATION CONTROL                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    input,rule_deck_drc        ""
    input,rule_deck_lvs        ""
    input,rule_deck_erc        ""
    input,rule_deck_perc       ""
    input,lvs_reference_netlist ""
    output,report_dir          "reports/pv"
    output,results_dir         "results/pv"
    output,work_dir            "work/PV"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    supported_tools {icv calibre}
    default_tool    "icv"
}

# Source tool-specific configuration
# Tool is set via: user_config pv(tool,name) or defaults to pv(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists pv(tool,name)] ? $pv(tool,name) : $pv(default_tool)}]

set _tool_config "$_node_config_dir/PV_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $pv(supported_tools)"
    exit 1
}
