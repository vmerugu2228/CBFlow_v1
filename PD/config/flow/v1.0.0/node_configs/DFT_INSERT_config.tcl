#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          DFT_INSERT Flow Configuration (Tool-Independent)                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# RTL → DFT-inserted RTL (MBIST + OCC + EDT/SSN). Common stages & dependencies
# for all tools (Tessent, DFT Compiler). Tool-specific settings sourced from
# DFT_INSERT_<tool>_config.tcl.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    stages {rtl1 spec1 lib1 init_dft1 insert_mbist1 insert_occ1 insert_edt1 dft_verify1 dft_inserted_export1 release_data1}

    dependencies,rtl1                  {}
    dependencies,spec1                 {}
    dependencies,lib1                  {}
    dependencies,init_dft1             {rtl1 spec1 lib1}
    dependencies,insert_mbist1         {init_dft1}
    dependencies,insert_occ1           {init_dft1}
    dependencies,insert_edt1           {insert_mbist1 insert_occ1}
    dependencies,dft_verify1           {insert_edt1}
    dependencies,dft_inserted_export1  {dft_verify1}
    dependencies,release_data1         {dft_inserted_export1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _dft_insert_exec_stages {init_dft1 insert_mbist1 insert_occ1 insert_edt1 dft_verify1 dft_inserted_export1 release_data1}
foreach _s $_dft_insert_exec_stages {
    set dft_insert(subnodes,$_s) {setup run validate finish}
    set dft_insert(subnode_dependencies,${_s},setup)    {}
    set dft_insert(subnode_dependencies,${_s},run)      {setup}
    set dft_insert(subnode_dependencies,${_s},validate) {run}
    set dft_insert(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set dft_insert(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    stage_types,rtl1                  "inputs"
    stage_types,spec1                 "inputs"
    stage_types,lib1                  "inputs"
    stage_types,init_dft1             "execution"
    stage_types,insert_mbist1         "execution"
    stage_types,insert_occ1           "execution"
    stage_types,insert_edt1           "execution"
    stage_types,dft_verify1           "execution"
    stage_types,dft_inserted_export1  "execution"
    stage_types,release_data1         "release_data"

    node_types,rtl1                  "inputs"
    node_types,spec1                 "inputs"
    node_types,lib1                  "inputs"
    node_types,init_dft1             "init_dft"
    node_types,insert_mbist1         "insert_mbist"
    node_types,insert_occ1           "insert_occ"
    node_types,insert_edt1           "insert_edt"
    node_types,dft_verify1           "dft_verify"
    node_types,dft_inserted_export1  "dft_inserted_export"
    node_types,release_data1         "release_data"

    node_descriptions,rtl1                  "RTL source input (Verilog/SystemVerilog)"
    node_descriptions,spec1                 "DFT specification input (MBIST/OCC/EDT intent)"
    node_descriptions,lib1                  "Technology library input (tech LEFs, .lib, NDM)"
    node_descriptions,init_dft1             "Initialize DFT environment, read RTL, read DFT spec"
    node_descriptions,insert_mbist1         "Insert MBIST controllers and wrappers for memories"
    node_descriptions,insert_occ1           "Insert on-chip clocking (OCC) controllers for at-speed test"
    node_descriptions,insert_edt1           "Insert EDT / streaming scan compression (SSN)"
    node_descriptions,dft_verify1           "DFT verification — DRC checks, sim handoff readiness"
    node_descriptions,dft_inserted_export1  "Write DFT-inserted RTL for downstream synthesis"
    node_descriptions,release_data1         "Package and release DFT deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    mmmc,enabled            false

    runtime,timeout,rtl1                  10
    runtime,timeout,spec1                 10
    runtime,timeout,lib1                  10
    runtime,timeout,init_dft1             20
    runtime,timeout,insert_mbist1         60
    runtime,timeout,insert_occ1           45
    runtime,timeout,insert_edt1           60
    runtime,timeout,dft_verify1           30
    runtime,timeout,dft_inserted_export1  15
    runtime,timeout,release_data1         10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    critical_files,init_dft1             {dft_insert(input,rtl) dft_insert(input,dft_spec)}
    critical_files,insert_mbist1         {dft_insert(input,rtl)}
    critical_files,insert_occ1           {dft_insert(input,rtl)}
    critical_files,insert_edt1           {dft_insert(input,rtl)}
    critical_files,dft_verify1           {}
    critical_files,dft_inserted_export1  {}
    critical_files,release_data1         {}

    mandatory_outputs,insert_mbist1         {outputs/${design_name}.mbist.v}
    mandatory_outputs,insert_occ1           {outputs/${design_name}.occ.v}
    mandatory_outputs,insert_edt1           {outputs/${design_name}.edt.v}
    mandatory_outputs,dft_inserted_export1  {outputs/${design_name}.dft.v}

    mandatory_input_groups {
        rtl_inputs   {dft_insert(input,rtl)}
        spec_inputs  {dft_insert(input,dft_spec)}
    }

    mandatory_user_inputs {
        dft_insert(input,rtl)
        dft_insert(input,dft_spec)
    }

    output,report_dir   "reports/dft_insert"
    output,results_dir  "results/dft_insert"
    output,work_dir     "work/DFT_INSERT"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    release_types,dft,description "DFT-inserted RTL and DFT-insertion reports"
    release_types,dft,files {
        "outputs/${design_name}.dft.v"               "rtl/${design_name}.dft.v"
        "reports/dft_insert/mbist_insertion.rpt"     "reports/mbist_insertion.rpt"
        "reports/dft_insert/occ_insertion.rpt"       "reports/occ_insertion.rpt"
        "reports/dft_insert/edt_insertion.rpt"       "reports/edt_insertion.rpt"
        "reports/dft_insert/dft_verify.rpt"          "reports/dft_verify.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert {
    supported_tools {tessent dft_compiler}
    default_tool    "tessent"
}

# Source tool-specific configuration
# Tool is set via: user_config dft_insert(tool,name) or defaults to dft_insert(default_tool)
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists dft_insert(tool,name)] ? $dft_insert(tool,name) : $dft_insert(default_tool)}]

set _tool_config "$_node_config_dir/DFT_INSERT_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $dft_insert(supported_tools)"
    exit 1
}
