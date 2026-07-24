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
    stages {netlist1 def1 gds1 nettran1 merge_gds1 fill_merge_gds1 decomp1 decomp_merge_gds1 drc1 lvs1 perc1 perc_ldl1 xor1 merge_data1 release_data1}

    dependencies,netlist1          {}
    dependencies,def1              {}
    dependencies,gds1              {}
    dependencies,nettran1          {netlist1}
    dependencies,merge_gds1        {netlist1 def1 gds1}
    dependencies,fill_merge_gds1   {merge_gds1}
    dependencies,decomp1           {fill_merge_gds1}
    dependencies,decomp_merge_gds1 {fill_merge_gds1 decomp1}
    dependencies,drc1              {decomp_merge_gds1}
    dependencies,lvs1              {decomp_merge_gds1 nettran1}
    dependencies,perc1             {decomp_merge_gds1}
    dependencies,perc_ldl1         {decomp_merge_gds1}
    dependencies,xor1              {decomp_merge_gds1}
    dependencies,merge_data1       {drc1 lvs1 perc1 perc_ldl1 xor1}
    dependencies,release_data1     {merge_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# All execution stages share the same subnode pattern
set _pv_exec_stages {nettran1 merge_gds1 fill_merge_gds1 decomp1 decomp_merge_gds1 drc1 lvs1 perc1 perc_ldl1 xor1 merge_data1 release_data1}
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
    stage_types,netlist1           "inputs"
    stage_types,def1               "inputs"
    stage_types,gds1               "inputs"
    stage_types,nettran1           "execution"
    stage_types,merge_gds1         "execution"
    stage_types,fill_merge_gds1    "execution"
    stage_types,decomp1            "execution"
    stage_types,decomp_merge_gds1  "execution"
    stage_types,drc1               "execution"
    stage_types,lvs1               "execution"
    stage_types,perc1              "execution"
    stage_types,perc_ldl1          "execution"
    stage_types,xor1               "execution"
    stage_types,merge_data1        "data"
    stage_types,release_data1      "release_data"

    node_types,netlist1            "inputs"
    node_types,def1                "inputs"
    node_types,gds1                "inputs"
    node_types,nettran1            "nettran"
    node_types,merge_gds1          "merge_gds"
    node_types,fill_merge_gds1     "fill_merge_gds"
    node_types,decomp1             "decomp"
    node_types,decomp_merge_gds1   "decomp_merge_gds"
    node_types,drc1                "drc"
    node_types,lvs1                "lvs"
    node_types,perc1               "perc"
    node_types,perc_ldl1           "perc_ldl"
    node_types,xor1                "xor"
    node_types,merge_data1         "merge_data"
    node_types,release_data1       "release_data"

    node_descriptions,netlist1          "Gate-level netlist input"
    node_descriptions,def1              "DEF floorplan input"
    node_descriptions,gds1              "GDS layout data input"
    node_descriptions,nettran1          "Netlist translation (source netlist → LVS-ready format)"
    node_descriptions,merge_gds1        "Merge fill GDS with base layout"
    node_descriptions,fill_merge_gds1   "Post-merge fill validation / stitching"
    node_descriptions,decomp1           "Mask decomposition (multi-patterning colorization)"
    node_descriptions,decomp_merge_gds1 "Merge decomposed colors back into a single GDS for signoff checks"
    node_descriptions,drc1              "Design Rule Check with foundry runset"
    node_descriptions,lvs1              "Layout vs Schematic with netlist comparison"
    node_descriptions,perc1             "PERC (Parasitic Electrical Rule Check)"
    node_descriptions,perc_ldl1         "PERC-LDL (latch-up / leakage-driven variant of PERC)"
    node_descriptions,xor1              "XOR comparison (pre-fill vs post-fill layout)"
    node_descriptions,merge_data1       "Merge filled layout with original design"
    node_descriptions,release_data1     "Package and release PV signoff deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    runtime,timeout,netlist1           10
    runtime,timeout,def1               10
    runtime,timeout,gds1               10
    runtime,timeout,nettran1           30
    runtime,timeout,merge_gds1         30
    runtime,timeout,fill_merge_gds1    30
    runtime,timeout,decomp1            60
    runtime,timeout,decomp_merge_gds1  30
    runtime,timeout,drc1               90
    runtime,timeout,lvs1               60
    runtime,timeout,perc1              30
    runtime,timeout,perc_ldl1          30
    runtime,timeout,xor1               30
    runtime,timeout,merge_data1        15
    runtime,timeout,release_data1      10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,def1,def "def_inputs"
    subnode_input_types,gds1,gds "gds_inputs"

    critical_files,drc1      {pv(input,gds)}
    critical_files,lvs1      {pv(input,netlist) pv(input,gds)}
    critical_files,perc1     {pv(input,gds)}
    critical_files,perc_ldl1 {pv(input,gds)}

    mandatory_outputs,drc1        {results/drc/drc.rpt}
    mandatory_outputs,lvs1        {results/lvs/lvs.rpt}
    mandatory_outputs,perc1       {results/perc/perc.rpt}
    mandatory_outputs,perc_ldl1   {results/perc_ldl/perc_ldl.rpt}
    mandatory_outputs,merge_data1 {results/verification/verification_summary.rpt}

    mandatory_input_groups {
        netlist_inputs {pv(input,netlist)}
        def_inputs {pv(input,def_file)}
        gds_inputs {pv(input,gds)}
    }

    mandatory_user_inputs {
        pv(input,gds)
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
        "results/perc/perc.rpt" "reports/perc_verification.rpt"
        "results/verification/verification_summary.rpt" "reports/verification_summary.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        COMMON VERIFICATION CONTROL                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set pv {
    input,rule_deck_drc              ""
    input,rule_deck_lvs              ""
    input,rule_deck_perc             ""
    input,rule_deck_perc_ldl         ""
    input,rule_deck_fill             ""
    input,rule_deck_multi_patterning ""
    input,rule_deck_xor              ""
    input,lvs_reference_netlist      ""
    input,fill_gds                   ""
    input,spice_stdcell              ""
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
