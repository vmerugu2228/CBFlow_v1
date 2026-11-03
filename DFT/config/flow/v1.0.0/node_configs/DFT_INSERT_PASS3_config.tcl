#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    DFT_INSERT_PASS3 Flow Configuration — EDT & OCC                          ║
# ║    (Compression + At-Speed Clocking)                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Pass 3 of the three-pass DFT insertion flow. Consumes Pass2 release output
# (top-level DFT-inserted netlist) and inserts EDT compression + OCC
# (on-chip clocking) for at-speed testing.
#
# Pass3 release feeds SCAN_INSERT.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    stages {netlist1 spec1 lib1
            init1
            constraints1 ctrl_points1
            drc1 drc_opt1 drc2
            edt_spec1 occ_spec1
            insert1 vgen1 sim1
            release_data1}

    dependencies,netlist1       {}
    dependencies,spec1          {}
    dependencies,lib1           {}
    dependencies,init1          {netlist1 spec1 lib1}
    dependencies,constraints1   {init1}
    dependencies,ctrl_points1   {constraints1}
    dependencies,drc1           {ctrl_points1}
    dependencies,drc_opt1       {drc1}
    dependencies,drc2           {drc_opt1}
    dependencies,edt_spec1      {drc2}
    dependencies,occ_spec1      {edt_spec1}
    dependencies,insert1        {occ_spec1}
    dependencies,vgen1          {insert1}
    dependencies,sim1           {vgen1}
    dependencies,release_data1  {sim1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _pass3_exec_stages {init1 constraints1 ctrl_points1
                        drc1 drc_opt1 drc2
                        edt_spec1 occ_spec1
                        insert1 vgen1 sim1
                        release_data1}
foreach _s $_pass3_exec_stages {
    set dft_insert_pass3(subnodes,$_s) {setup run validate finish}
    set dft_insert_pass3(subnode_dependencies,${_s},setup)    {}
    set dft_insert_pass3(subnode_dependencies,${_s},run)      {setup}
    set dft_insert_pass3(subnode_dependencies,${_s},validate) {run}
    set dft_insert_pass3(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set dft_insert_pass3(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    stage_types,netlist1      "inputs"
    stage_types,spec1         "inputs"
    stage_types,lib1          "inputs"
    stage_types,init1         "execution"
    stage_types,constraints1  "execution"
    stage_types,ctrl_points1  "execution"
    stage_types,drc1          "execution"
    stage_types,drc_opt1      "execution"
    stage_types,drc2          "execution"
    stage_types,edt_spec1     "execution"
    stage_types,occ_spec1     "execution"
    stage_types,insert1       "execution"
    stage_types,vgen1         "execution"
    stage_types,sim1          "execution"
    stage_types,release_data1 "release_data"

    node_types,netlist1      "inputs"
    node_types,spec1         "inputs"
    node_types,lib1          "inputs"
    node_types,init1         "init"
    node_types,constraints1  "constraints"
    node_types,ctrl_points1  "ctrl_points"
    node_types,drc1          "drc1"
    node_types,drc_opt1      "drc_opt"
    node_types,drc2          "drc2"
    node_types,edt_spec1     "edt_spec"
    node_types,occ_spec1     "occ_spec"
    node_types,insert1       "insert"
    node_types,vgen1         "vgen"
    node_types,sim1          "sim"
    node_types,release_data1 "release_data"

    node_descriptions,netlist1      "Pass2 release netlist (top-level DFT-inserted RTL)"
    node_descriptions,spec1         "EDT + OCC specification override"
    node_descriptions,lib1          "Memory + standard-cell libraries"
    node_descriptions,init1         "Setup Tessent context, read Pass2 release, elaborate"
    node_descriptions,constraints1  "EDT + OCC constraint setup"
    node_descriptions,ctrl_points1  "Control points setup for at-speed test"
    node_descriptions,drc1          "DRC check — pre-optimization"
    node_descriptions,drc_opt1      "DRC optimization — resolve pre-opt violations"
    node_descriptions,drc2          "DRC check — post-optimization, strict"
    node_descriptions,edt_spec1     "EDT compression specification"
    node_descriptions,occ_spec1     "OCC at-speed clocking specification"
    node_descriptions,insert1       "DFT insertion + database extract"
    node_descriptions,vgen1         "Pattern generation — EDT compressed + OCC"
    node_descriptions,sim1          "Simulation prep"
    node_descriptions,release_data1 "Package Pass3 deliverables for release"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    mmmc,enabled            false

    runtime,timeout,netlist1      10
    runtime,timeout,spec1         10
    runtime,timeout,lib1          10
    runtime,timeout,init1         20
    runtime,timeout,constraints1  15
    runtime,timeout,ctrl_points1  30
    runtime,timeout,drc1          20
    runtime,timeout,drc_opt1      45
    runtime,timeout,drc2          20
    runtime,timeout,edt_spec1     45
    runtime,timeout,occ_spec1     30
    runtime,timeout,insert1       90
    runtime,timeout,vgen1         75
    runtime,timeout,sim1          30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    critical_files,init1   {dft_insert_pass3(input,netlist) dft_insert_pass3(input,tcelllib)}
    critical_files,insert1 {dft_insert_pass3(input,netlist)}

    mandatory_input_groups {
        netlist_inputs {dft_insert_pass3(input,netlist)}
        spec_inputs    {dft_insert_pass3(input,dft_spec)}
        lib_inputs     {dft_insert_pass3(input,tcelllib)}
    }

    mandatory_user_inputs {
        dft_insert_pass3(input,netlist)
        dft_insert_pass3(input,dft_spec)
        dft_insert_pass3(input,tcelllib)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    mandatory_outputs,drc1 {
        reports/dft_insert_pass3/drc_pre.rpt
    }
    mandatory_outputs,drc_opt1 {
        reports/dft_insert_pass3/drc_opt.rpt
    }
    mandatory_outputs,drc2 {
        reports/dft_insert_pass3/drc_post.rpt
    }
    mandatory_outputs,edt_spec1 {
        outputs/${design_name}.edt.icl
        outputs/${design_name}.edt_spec
    }
    mandatory_outputs,occ_spec1 {
        outputs/${design_name}.occ.icl
        outputs/${design_name}.occ_spec
    }
    mandatory_outputs,insert1 {
        outputs/${design_name}.edt_occ.v
        outputs/${design_name}.edt_occ.sdc
        outputs/${design_name}.edt_occ.pdl
        outputs/${design_name}.edt_occ.tcd
        reports/dft_insert_pass3/insertion.rpt
    }
    mandatory_outputs,vgen1 {
        outputs/EDT_patterns.v
        outputs/EDT_patterns.pdl
    }
    mandatory_outputs,sim1 {
        outputs/edt_occ_simulation_data_dictionary
    }

    output,report_dir   "reports/dft_insert_pass3"
    output,results_dir  "results/dft_insert_pass3"
    output,work_dir     "work/DFT_INSERT_PASS3"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    release_types,dft_pass3,description "DFT Pass3 — EDT + OCC deliverables"
    release_types,dft_pass3,files {
        "outputs/${design_name}.edt_occ.v"            "netlist/${design_name}.edt_occ.v"
        "outputs/${design_name}.edt_occ.sdc"          "sdc/${design_name}.edt_occ.sdc"
        "outputs/${design_name}.edt_occ.pdl"          "pdl/${design_name}.edt_occ.pdl"
        "outputs/${design_name}.edt_occ.tcd"          "tcd/${design_name}.edt_occ.tcd"
        "outputs/${design_name}.edt.icl"              "icl/${design_name}.edt.icl"
        "outputs/${design_name}.edt_spec"             "spec/${design_name}.edt_spec"
        "outputs/${design_name}.occ.icl"              "icl/${design_name}.occ.icl"
        "outputs/${design_name}.occ_spec"             "spec/${design_name}.occ_spec"
        "outputs/EDT_patterns.v"                      "patterns/EDT_patterns.v"
        "outputs/EDT_patterns.pdl"                    "patterns/EDT_patterns.pdl"
        "outputs/edt_occ_simulation_data_dictionary"  "sim/edt_occ_simulation_data_dictionary"
        "reports/dft_insert_pass3/drc_pre.rpt"        "reports/drc_pre.rpt"
        "reports/dft_insert_pass3/drc_opt.rpt"        "reports/drc_opt.rpt"
        "reports/dft_insert_pass3/drc_post.rpt"       "reports/drc_post.rpt"
        "reports/dft_insert_pass3/insertion.rpt"      "reports/insertion.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass3 {
    supported_tools {tessent dft_compiler}
    default_tool    "tessent"
}

set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists dft_insert_pass3(tool,name)] ? $dft_insert_pass3(tool,name) : $dft_insert_pass3(default_tool)}]

set _tool_config "$_node_config_dir/DFT_INSERT_PASS3_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $dft_insert_pass3(supported_tools)"
    exit 1
}
