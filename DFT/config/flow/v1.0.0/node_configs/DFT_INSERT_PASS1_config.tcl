#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    DFT_INSERT_PASS1 Flow Configuration — Core DFT (MBIST + BSCAN)           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Pass 1 of the three-pass DFT insertion flow specified in the owner spreadsheet
# (DFT_FLOW_Dependencies_Input_Output.xlsx):
#   Pass 1 (this file) : Core DFT  — MBIST + BSCAN insertion at block level
#   Pass 2             : Top DFT   — TDR, DFT Signals, SRI configuration
#   Pass 3             : EDT & OCC — compression + at-speed clocking
#
# Pass1 output (DFT-inserted RTL + ICL/PDL/SDC/TCD/dictionaries + MBIST
# controller/BAP/BSCAN interface files + pattern files) is consumed by Pass2
# via release_tag handoff.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    stages {rtl1 spec1 lib1
            init1
            tap_cfg1 bscan_cfg1 mbist_cfg1
            drc1 tpi1 drc2
            tap_spec1 bscan_spec1 mbist_spec1
            insert1 vgen1 sim1
            release_data1}

    dependencies,rtl1          {}
    dependencies,spec1         {}
    dependencies,lib1          {}
    dependencies,init1         {rtl1 spec1 lib1}
    dependencies,tap_cfg1      {init1}
    dependencies,bscan_cfg1    {tap_cfg1}
    dependencies,mbist_cfg1    {bscan_cfg1}
    dependencies,drc1          {mbist_cfg1}
    dependencies,tpi1          {drc1}
    dependencies,drc2          {tpi1}
    dependencies,tap_spec1     {drc2}
    dependencies,bscan_spec1   {tap_spec1}
    dependencies,mbist_spec1   {bscan_spec1}
    dependencies,insert1       {mbist_spec1}
    dependencies,vgen1         {insert1}
    dependencies,sim1          {vgen1}
    dependencies,release_data1 {sim1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _pass1_exec_stages {init1
                        tap_cfg1 bscan_cfg1 mbist_cfg1
                        drc1 tpi1 drc2
                        tap_spec1 bscan_spec1 mbist_spec1
                        insert1 vgen1 sim1
                        release_data1}
foreach _s $_pass1_exec_stages {
    set dft_insert_pass1(subnodes,$_s) {setup run validate finish}
    set dft_insert_pass1(subnode_dependencies,${_s},setup)    {}
    set dft_insert_pass1(subnode_dependencies,${_s},run)      {setup}
    set dft_insert_pass1(subnode_dependencies,${_s},validate) {run}
    set dft_insert_pass1(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set dft_insert_pass1(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    stage_types,rtl1          "inputs"
    stage_types,spec1         "inputs"
    stage_types,lib1          "inputs"
    stage_types,init1         "execution"
    stage_types,tap_cfg1      "execution"
    stage_types,bscan_cfg1    "execution"
    stage_types,mbist_cfg1    "execution"
    stage_types,drc1          "execution"
    stage_types,tpi1          "execution"
    stage_types,drc2          "execution"
    stage_types,tap_spec1     "execution"
    stage_types,bscan_spec1   "execution"
    stage_types,mbist_spec1   "execution"
    stage_types,insert1       "execution"
    stage_types,vgen1         "execution"
    stage_types,sim1          "execution"
    stage_types,release_data1 "release_data"

    node_types,rtl1          "inputs"
    node_types,spec1         "inputs"
    node_types,lib1          "inputs"
    node_types,init1         "init"
    node_types,tap_cfg1      "tap_cfg"
    node_types,bscan_cfg1    "bscan_cfg"
    node_types,mbist_cfg1    "mbist_cfg"
    node_types,drc1          "drc1"
    node_types,tpi1          "tpi"
    node_types,drc2          "drc2"
    node_types,tap_spec1     "tap_spec"
    node_types,bscan_spec1   "bscan_spec"
    node_types,mbist_spec1   "mbist_spec"
    node_types,insert1       "insert"
    node_types,vgen1         "vgen"
    node_types,sim1          "sim"
    node_types,release_data1 "release_data"

    node_descriptions,rtl1          "RTL source filelist (Verilog/SystemVerilog)"
    node_descriptions,spec1         "DFT specification override — block-level customizations"
    node_descriptions,lib1          "Memory + standard-cell libraries (TCD + adk.tcelllib)"
    node_descriptions,init1         "Setup Tessent context, read libs, elaborate RTL"
    node_descriptions,tap_cfg1      "TAP controller configuration (pins, IR/DR widths)"
    node_descriptions,bscan_cfg1    "Boundary-scan configuration (pads, BC cells)"
    node_descriptions,mbist_cfg1    "MBIST configuration — memory groups, bbox models, constraints"
    node_descriptions,drc1          "DRC check — pre-TPI DFT rule validation"
    node_descriptions,tpi1          "Test-point insertion"
    node_descriptions,drc2          "DRC check — post-TPI, compared to pre"
    node_descriptions,tap_spec1     "TAP spec extraction (ICL)"
    node_descriptions,bscan_spec1   "BSCAN interface spec (ICL + Verilog)"
    node_descriptions,mbist_spec1   "MBIST controller + BAP spec (ICL/PDL/TCD/Verilog)"
    node_descriptions,insert1       "DFT insertion + database extract — produces DFT-inserted RTL"
    node_descriptions,vgen1         "Pattern generation — MBIST + retention test"
    node_descriptions,sim1          "Simulation prep — write ICLNetwork + simulation_data_dictionary"
    node_descriptions,release_data1 "Package Pass1 deliverables for release"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    mmmc,enabled            false

    runtime,timeout,rtl1          10
    runtime,timeout,spec1         10
    runtime,timeout,lib1          10
    runtime,timeout,init1         20
    runtime,timeout,tap_cfg1      15
    runtime,timeout,bscan_cfg1    15
    runtime,timeout,mbist_cfg1    30
    runtime,timeout,drc1          20
    runtime,timeout,tpi1          30
    runtime,timeout,drc2          20
    runtime,timeout,tap_spec1     20
    runtime,timeout,bscan_spec1   20
    runtime,timeout,mbist_spec1   45
    runtime,timeout,insert1       90
    runtime,timeout,vgen1         60
    runtime,timeout,sim1          30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    critical_files,init1         {dft_insert_pass1(input,rtl) dft_insert_pass1(input,memory_libs) dft_insert_pass1(input,tcelllib)}
    critical_files,mbist_cfg1    {dft_insert_pass1(input,memory_libs)}
    critical_files,insert1       {dft_insert_pass1(input,rtl)}

    mandatory_input_groups {
        rtl_inputs    {dft_insert_pass1(input,rtl)}
        spec_inputs   {dft_insert_pass1(input,dft_spec)}
        lib_inputs    {dft_insert_pass1(input,memory_libs) dft_insert_pass1(input,tcelllib)}
    }

    mandatory_user_inputs {
        dft_insert_pass1(input,rtl)
        dft_insert_pass1(input,dft_spec)
        dft_insert_pass1(input,memory_libs)
        dft_insert_pass1(input,tcelllib)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ║  Enumerates every artifact listed in the spreadsheet "MBIST Config          ║
# ║  Dependencies" sheet (Generated Outputs sections B-G).                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    mandatory_outputs,drc1 {
        reports/dft_insert_pass1/drc_pre.rpt
    }
    mandatory_outputs,drc2 {
        reports/dft_insert_pass1/drc_post.rpt
    }
    mandatory_outputs,tap_spec1 {
        outputs/${design_name}.tap.icl
    }
    mandatory_outputs,bscan_spec1 {
        outputs/${design_name}_rtl1_tessent_bscan_interface_m1.icl
        outputs/${design_name}_rtl1_tessent_bscan_interface_m1.v
        outputs/${design_name}_rtl1_tessent_bscan_interface_m2.icl
        outputs/${design_name}_rtl1_tessent_bscan_interface_m2.v
    }
    mandatory_outputs,mbist_spec1 {
        outputs/${design_name}_rtl1_mbist.sdc_dictionary
        outputs/${design_name}_rtl1_mbist.synthesis_dictionary
        outputs/${design_name}_rtl1_tessent_mbist_bap.icl
        outputs/${design_name}_rtl1_tessent_mbist_bap.tcd
        outputs/${design_name}_rtl1_tessent_mbist_bap.v
        outputs/${design_name}_rtl1_tessent_mbist_c1_controller.icl
        outputs/${design_name}_rtl1_tessent_mbist_c1_controller.pdl
        outputs/${design_name}_rtl1_tessent_mbist_c1_controller.tcd
        outputs/${design_name}_rtl1_tessent_mbist_c1_controller.v
    }
    mandatory_outputs,insert1 {
        outputs/${design_name}_rtl1.dft_inserted_design
        outputs/modified_rtl_files/${design_name}.v
        outputs/${design_name}.design_source_dictionary
        outputs/${design_name}.dft_info_dictionary
        outputs/${design_name}.dft_summary_dictionary
        outputs/${design_name}.icl
        outputs/${design_name}.pdl
        outputs/${design_name}.sdc
        outputs/${design_name}.tcd
        outputs/${design_name}.tsdb_info
        outputs/${design_name}.dft_spec
        reports/dft_insert_pass1/insertion.rpt
    }
    mandatory_outputs,vgen1 {
        outputs/ICLNetwork.pdl
        outputs/ICLNetwork.v
        outputs/MemoryBist_P1.pdl
        outputs/MemoryBist_P1.v
        outputs/MemoryBist_ParallelRetentionTest_P1.pdl
        outputs/MemoryBist_ParallelRetentionTest_P1.v
    }
    mandatory_outputs,sim1 {
        outputs/simulation_data_dictionary
    }

    output,report_dir   "reports/dft_insert_pass1"
    output,results_dir  "results/dft_insert_pass1"
    output,work_dir     "work/DFT_INSERT_PASS1"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    release_types,dft_pass1,description "DFT Pass1 — Core DFT (MBIST + BSCAN) deliverables"
    release_types,dft_pass1,files {
        "outputs/${design_name}_rtl1.dft_inserted_design"                              "dft_inserted_design/${design_name}_rtl1.dft_inserted_design"
        "outputs/modified_rtl_files/${design_name}.v"                                  "netlist/${design_name}.v"
        "outputs/${design_name}.icl"                                                   "icl/${design_name}.icl"
        "outputs/${design_name}.pdl"                                                   "pdl/${design_name}.pdl"
        "outputs/${design_name}.sdc"                                                   "sdc/${design_name}.sdc"
        "outputs/${design_name}.tcd"                                                   "tcd/${design_name}.tcd"
        "outputs/${design_name}.tsdb_info"                                             "tsdb/${design_name}.tsdb_info"
        "outputs/${design_name}.dft_spec"                                              "spec/${design_name}.dft_spec"
        "outputs/${design_name}.design_source_dictionary"                              "dict/${design_name}.design_source_dictionary"
        "outputs/${design_name}.dft_info_dictionary"                                   "dict/${design_name}.dft_info_dictionary"
        "outputs/${design_name}.dft_summary_dictionary"                                "dict/${design_name}.dft_summary_dictionary"
        "outputs/${design_name}_rtl1_mbist.sdc_dictionary"                             "mbist/${design_name}_rtl1_mbist.sdc_dictionary"
        "outputs/${design_name}_rtl1_mbist.synthesis_dictionary"                       "mbist/${design_name}_rtl1_mbist.synthesis_dictionary"
        "outputs/${design_name}_rtl1_tessent_mbist_bap.icl"                            "mbist/${design_name}_rtl1_tessent_mbist_bap.icl"
        "outputs/${design_name}_rtl1_tessent_mbist_bap.tcd"                            "mbist/${design_name}_rtl1_tessent_mbist_bap.tcd"
        "outputs/${design_name}_rtl1_tessent_mbist_bap.v"                              "mbist/${design_name}_rtl1_tessent_mbist_bap.v"
        "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.icl"                  "mbist/${design_name}_rtl1_tessent_mbist_c1_controller.icl"
        "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.pdl"                  "mbist/${design_name}_rtl1_tessent_mbist_c1_controller.pdl"
        "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.tcd"                  "mbist/${design_name}_rtl1_tessent_mbist_c1_controller.tcd"
        "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.v"                    "mbist/${design_name}_rtl1_tessent_mbist_c1_controller.v"
        "outputs/${design_name}_rtl1_tessent_bscan_interface_m1.icl"                   "bscan/${design_name}_rtl1_tessent_bscan_interface_m1.icl"
        "outputs/${design_name}_rtl1_tessent_bscan_interface_m1.v"                     "bscan/${design_name}_rtl1_tessent_bscan_interface_m1.v"
        "outputs/${design_name}_rtl1_tessent_bscan_interface_m2.icl"                   "bscan/${design_name}_rtl1_tessent_bscan_interface_m2.icl"
        "outputs/${design_name}_rtl1_tessent_bscan_interface_m2.v"                     "bscan/${design_name}_rtl1_tessent_bscan_interface_m2.v"
        "outputs/ICLNetwork.pdl"                                                       "patterns/ICLNetwork.pdl"
        "outputs/ICLNetwork.v"                                                         "patterns/ICLNetwork.v"
        "outputs/MemoryBist_P1.pdl"                                                    "patterns/MemoryBist_P1.pdl"
        "outputs/MemoryBist_P1.v"                                                      "patterns/MemoryBist_P1.v"
        "outputs/MemoryBist_ParallelRetentionTest_P1.pdl"                              "patterns/MemoryBist_ParallelRetentionTest_P1.pdl"
        "outputs/MemoryBist_ParallelRetentionTest_P1.v"                                "patterns/MemoryBist_ParallelRetentionTest_P1.v"
        "outputs/simulation_data_dictionary"                                           "sim/simulation_data_dictionary"
        "outputs/${design_name}.tap.icl"                                               "tap/${design_name}.tap.icl"
        "reports/dft_insert_pass1/drc_pre.rpt"                                         "reports/drc_pre.rpt"
        "reports/dft_insert_pass1/drc_post.rpt"                                        "reports/drc_post.rpt"
        "reports/dft_insert_pass1/insertion.rpt"                                       "reports/insertion.rpt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS & TOOL CONFIG                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dft_insert_pass1 {
    supported_tools {tessent dft_compiler}
    default_tool    "tessent"
}

# Source tool-specific configuration
set _node_config_dir [file dirname [info script]]
set _tool_name [expr {[info exists dft_insert_pass1(tool,name)] ? $dft_insert_pass1(tool,name) : $dft_insert_pass1(default_tool)}]

set _tool_config "$_node_config_dir/DFT_INSERT_PASS1_${_tool_name}_config.tcl"
if {[file exists $_tool_config]} {
    source $_tool_config
} else {
    puts "ERROR: Tool config not found: $_tool_config"
    puts "       Supported tools: $dft_insert_pass1(supported_tools)"
    exit 1
}
