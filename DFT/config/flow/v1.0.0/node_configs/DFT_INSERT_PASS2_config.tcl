#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    DFT_INSERT_PASS2 Flow Configuration — Top DFT                            ║
# ║    (TDR + DFT Signals + SRI Configuration)                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Pass 2 of the three-pass DFT insertion flow. Consumes Pass1 release output
# (DFT-inserted RTL + ICL/PDL/dictionaries) and inserts top-level DFT:
# Test Data Registers (TDR), DFT signal routing, Scan Resource Interface (SRI).
#
# vgen1/sim1 are declared but optional at this pass per spreadsheet; the owner
# controls via dft_insert_pass2(vgen,enabled) + (sim,enabled).

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    stages {netlist1 spec1 lib1
            init1
            tdr_cfg1
            drc1 dft_spec1
            insert1 vgen1 sim1
            release_data1}

    dependencies,netlist1      {}
    dependencies,spec1         {}
    dependencies,lib1          {}
    dependencies,init1         {netlist1 spec1 lib1}
    dependencies,tdr_cfg1      {init1}
    dependencies,drc1          {tdr_cfg1}
    dependencies,dft_spec1     {drc1}
    dependencies,insert1       {dft_spec1}
    dependencies,vgen1         {insert1}
    dependencies,sim1          {vgen1}
    dependencies,release_data1 {sim1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _pass2_exec_stages {init1 tdr_cfg1 drc1 dft_spec1 insert1 vgen1 sim1 release_data1}
foreach _s $_pass2_exec_stages {
    set dft_insert_pass2(subnodes,$_s) {setup run validate finish}
    set dft_insert_pass2(subnode_dependencies,${_s},setup)    {}
    set dft_insert_pass2(subnode_dependencies,${_s},run)      {setup}
    set dft_insert_pass2(subnode_dependencies,${_s},validate) {run}
    set dft_insert_pass2(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set dft_insert_pass2(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    stage_types,netlist1      "inputs"
    stage_types,spec1         "inputs"
    stage_types,lib1          "inputs"
    stage_types,init1         "execution"
    stage_types,tdr_cfg1      "execution"
    stage_types,drc1          "execution"
    stage_types,dft_spec1     "execution"
    stage_types,insert1       "execution"
    stage_types,vgen1         "execution"
    stage_types,sim1          "execution"
    stage_types,release_data1 "release_data"

    node_types,netlist1      "inputs"
    node_types,spec1         "inputs"
    node_types,lib1          "inputs"
    node_types,init1         "init_dft"
    node_types,tdr_cfg1      "tdr_cfg"
    node_types,drc1          "drc_check"
    node_types,dft_spec1     "dft_spec"
    node_types,insert1       "dft_insert"
    node_types,vgen1         "vector_gen"
    node_types,sim1          "simulation_prep"
    node_types,release_data1 "release_data"

    node_descriptions,netlist1      "Pass1 release netlist (DFT-inserted RTL from Pass1)"
    node_descriptions,spec1         "Top-level DFT spec — TDR + SRI + DFT Signals config"
    node_descriptions,lib1          "Memory + standard-cell libraries"
    node_descriptions,init1         "Setup Tessent context, read Pass1 release, elaborate"
    node_descriptions,tdr_cfg1      "TDR + DFT Signals + SRI configuration"
    node_descriptions,drc1          "DRC check — top-level DFT rules"
    node_descriptions,dft_spec1     "Top DFT specification — write combined spec"
    node_descriptions,insert1       "Top DFT insertion + database extract"
    node_descriptions,vgen1         "Vector generation (optional — gated by vgen,enabled)"
    node_descriptions,sim1          "Simulation prep (optional — gated by sim,enabled)"
    node_descriptions,release_data1 "Package Pass2 deliverables for release"

    optional_stages {vgen1 sim1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    mmmc,enabled            false

    runtime,timeout,netlist1      10
    runtime,timeout,spec1         10
    runtime,timeout,lib1          10
    runtime,timeout,init1         20
    runtime,timeout,tdr_cfg1      30
    runtime,timeout,drc1          20
    runtime,timeout,dft_spec1     30
    runtime,timeout,insert1       75
    runtime,timeout,vgen1         60
    runtime,timeout,sim1          30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    critical_files,init1   {dft_insert_pass2(input,netlist) dft_insert_pass2(input,tcelllib)}
    critical_files,insert1 {dft_insert_pass2(input,netlist)}

    mandatory_input_groups {
        netlist_inputs {dft_insert_pass2(input,netlist)}
        spec_inputs    {dft_insert_pass2(input,dft_spec)}
        lib_inputs     {dft_insert_pass2(input,tcelllib)}
    }

    mandatory_user_inputs {
        dft_insert_pass2(input,netlist)
        dft_insert_pass2(input,dft_spec)
        dft_insert_pass2(input,tcelllib)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    mandatory_outputs,drc1 {
        reports/dft_insert_pass2/drc.rpt
    }
    mandatory_outputs,dft_spec1 {
        outputs/${design_name}.top.dft_spec
        outputs/${design_name}.top.icl
    }
    mandatory_outputs,insert1 {
        outputs/${design_name}.top.dft.v
        outputs/${design_name}.top.sdc
        outputs/${design_name}.top.pdl
        outputs/${design_name}.top.tcd
        outputs/${design_name}.top.tsdb_info
        reports/dft_insert_pass2/insertion.rpt
    }

    output,report_dir   "reports/dft_insert_pass2"
    output,results_dir  "results/dft_insert_pass2"
    output,work_dir     "work/DFT_INSERT_PASS2"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    release_types,dft_pass2,description "DFT Pass2 — Top DFT (TDR + DFT Signals + SRI) deliverables"
    release_types,dft_pass2,files {
        "outputs/${design_name}.top.dft.v"           "rtl/${design_name}.top.dft.v"
        "outputs/${design_name}.top.icl"             "icl/${design_name}.top.icl"
        "outputs/${design_name}.top.pdl"             "pdl/${design_name}.top.pdl"
        "outputs/${design_name}.top.sdc"             "sdc/${design_name}.top.sdc"
        "outputs/${design_name}.top.tcd"             "tcd/${design_name}.top.tcd"
        "outputs/${design_name}.top.tsdb_info"       "tsdb/${design_name}.top.tsdb_info"
        "outputs/${design_name}.top.dft_spec"        "spec/${design_name}.top.dft_spec"
        "reports/dft_insert_pass2/drc.rpt"           "reports/drc.rpt"
        "reports/dft_insert_pass2/insertion.rpt"     "reports/insertion.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass2 {
    supported_tools {tessent dft_compiler}
    default_tool    "tessent"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists dft_insert_pass2(tool,name)] ? $dft_insert_pass2(tool,name) : $dft_insert_pass2(default_tool)}]

set _tool_config "$_node_config_dir/DFT_INSERT_PASS2_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $dft_insert_pass2(supported_tools)"
    exit 1
}
