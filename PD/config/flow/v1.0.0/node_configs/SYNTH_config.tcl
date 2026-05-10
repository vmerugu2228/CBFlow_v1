#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         SYNTHESIS FLOW CONFIGURATION                        ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all SYNTH flow specific configurations organized
# under a single synth() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/SYNTH_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         SYNTH CONFIGURATION ARRAY                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# NOTE: Stage names use numeric suffix (inputs1, synthesis1) to distinguish from node types
#       This allows multiple instances: synthesis1, synthesis2, etc.
# Merge metadata - used when SYNTH is part of a merged flow (e.g., SYNTH_FP)
array set synth {
    stages {inputs1 init_design1 synthesis1 export_data1 release_data1}

    merge_entry_stage     inputs1
    merge_handoff_stage   export_data1
    merge_parallel_stages {release_data1}

    subnodes,inputs1        {setup rtl sdc upf validate finish}
    subnodes,init_design1   {setup run validate finish}
    subnodes,synthesis1     {setup run validate finish}
    subnodes,export_data1   {setup run validate finish}
    subnodes,release_data1  {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set synth {
    dependencies,inputs1        {}
    dependencies,init_design1   {inputs1}
    dependencies,synthesis1     {init_design1}
    dependencies,export_data1   {synthesis1}
    dependencies,release_data1  {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# synthesis1 stage subnodes
# export_data1 stage subnodes
# release_data1 stage subnodes
array set synth {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,rtl {}
    subnode_dependencies,inputs1,sdc {}
    subnode_dependencies,inputs1,upf {}
    subnode_dependencies,inputs1,validate {setup rtl sdc upf}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,init_design1,setup {}
    subnode_dependencies,init_design1,run {setup}
    subnode_dependencies,init_design1,validate {run}
    subnode_dependencies,init_design1,finish {validate}

    subnode_dependencies,synthesis1,setup {}
    subnode_dependencies,synthesis1,run {setup}
    subnode_dependencies,synthesis1,validate {run}
    subnode_dependencies,synthesis1,finish {validate}

    subnode_dependencies,export_data1,setup {}
    subnode_dependencies,export_data1,run {setup}
    subnode_dependencies,export_data1,validate {run}
    subnode_dependencies,export_data1,finish {validate}

    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set synth {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {fc dc genus}
    default_tool "fc"
}

# ┌─ MMMC Configuration ────────────────────────────────────────────────────┐
array set synth {
    mmmc,enabled              true
    mmmc,enabled_stages       {synthesis1}
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set         "signoff"
    mmmc,multi_corner_compile true
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set synth {
    runtime,timeout,inputs1       15
    runtime,timeout,init_design1  30
    runtime,timeout,synthesis1    120
    runtime,timeout,export_data1  15
    runtime,timeout,release_data1 10
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set synth {
    subnode_input_types,inputs1,rtl "rtl_inputs"
    subnode_input_types,inputs1,sdc "sdc_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
    subnode_input_types,inputs1,library "library_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs1 stage directories
# synthesis1 stage directories
# export_data1 stage directories
# release_data1 stage directories
array set synth {
    subnode_work_dirs,inputs1,setup "work/inputs1/setup"
    subnode_work_dirs,inputs1,rtl "work/inputs1/rtl"
    subnode_work_dirs,inputs1,sdc "work/inputs1/sdc"
    subnode_work_dirs,inputs1,library "work/inputs1/library"
    subnode_work_dirs,inputs1,upf "work/inputs1/upf"
    subnode_work_dirs,inputs1,validate "work/inputs1/validate"
    subnode_work_dirs,inputs1,finish "work/inputs1/finish"

    subnode_work_dirs,init_design1,setup "work/init_design1/setup"
    subnode_work_dirs,init_design1,run "work/init_design1/run"
    subnode_work_dirs,init_design1,validate "work/init_design1/validate"
    subnode_work_dirs,init_design1,finish "work/init_design1/finish"

    subnode_work_dirs,synthesis1,setup "work/synthesis1/setup"
    subnode_work_dirs,synthesis1,run "work/synthesis1/run"
    subnode_work_dirs,synthesis1,validate "work/synthesis1/validate"
    subnode_work_dirs,synthesis1,finish "work/synthesis1/finish"

    subnode_work_dirs,export_data1,setup "work/export_data1/setup"
    subnode_work_dirs,export_data1,run "work/export_data1/run"
    subnode_work_dirs,export_data1,validate "work/export_data1/validate"
    subnode_work_dirs,export_data1,finish "work/export_data1/finish"

    subnode_work_dirs,release_data1,setup "work/release_data1/setup"
    subnode_work_dirs,release_data1,run "work/release_data1/run"
    subnode_work_dirs,release_data1,validate "work/release_data1/validate"
    subnode_work_dirs,release_data1,finish "work/release_data1/finish"
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
# NOTE: node_types maps NODE NAME (inputs1) to NODE TYPE (inputs)
#       This allows the system to identify the type of each named node
array set synth {
    stage_types,inputs1 "inputs"
    stage_types,init_design1 "execution"
    stage_types,synthesis1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,init_design1 "init_design"
    node_types,synthesis1 "synthesis"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (7 subnodes: setup, rtl, sdc, library, upf, validate, finish)"
    node_descriptions,init_design1 "Design library creation, technology setup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,synthesis1 "Logic synthesis and optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Export synthesis data and results (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release synthesis deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set synth {
    critical_files,inputs1 {synth(input,rtl_files)}
    critical_files,synthesis1 {synth(input,rtl_files) synth(input,sdc_file)}

    mandatory_outputs,synthesis1 {results/netlist/synth.v results/sdc/synth.sdc}
    mandatory_outputs,export_data1 {results/db/synth.db}

    optional_files,inputs1 {synth(input,upf_file) synth(input,tcl_scripts)}
}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set synth {
    mandatory_input_groups {
        rtl_inputs {synth(input,rtl_release_tag) synth(input,rtl_release_dir) synth(input,rtl_filelist)}
        sdc_inputs {synth(input,sdc_release_tag) synth(input,sdc_release_dir) synth(input,sdc_func_file)}
        upf_inputs {synth(input,upf_release_tag) synth(input,upf_release_dir) synth(input,upf_file)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set synth {
    release_types,synthesis1,description "Synthesis deliverables for RTL handoff"
    release_types,synthesis1,files {
        "results/netlist/synth.v" "netlist/synthesis_netlist.v"
        "results/sdc/synth.sdc" "sdc/synthesis_constraints.sdc"
        "reports/synthesis/timing.rpt" "reports/synthesis_timing.rpt"
    }
}

# ┌─ Synthesis Input Configuration ────────────────────────────────────────────┐
array set synth {
    input,format "verilog"
    input,rtl_release_tag ""
    input,rtl_release_dir ""
    input,rtl_filelist ""
    input,sdc_release_tag ""
    input,sdc_release_dir ""
    input,sdc_func_file ""
    input,sdc_scan_file ""
    input,sdc_test_file ""
    input,sdc_dft_file ""
    input,upf_release_tag ""
    input,upf_release_dir ""
    input,upf_file ""
}

# ┌─ Synthesis Strategy and Effort Settings ───────────────────────────────────┐
array set synth {
    strategy "balanced"
    effort "medium"
    effort,mapping "medium"
    effort,timing "medium"
    effort,area "medium"
}

# ┌─ Design Constraints Configuration ──────────────────────────────────────────┐
array set synth {
    constraints,max_fanout "64"
    constraints,max_transition "0.5"
    constraints,max_capacitance "1.0"
    constraints,input_delay "0.2"
    constraints,output_delay "0.2"
}

# ┌─ Optimization Settings ─────────────────────────────────────────────────────┐
array set synth {
    optimization,boundary "false"
    optimization,hold_fix "false"
    optimization,multi_vt "false"
    optimization,clock_gating "true"
    optimization,power_gating "false"
    optimization,leakage_power "false"
}

# ┌─ Area Recovery Settings ────────────────────────────────────────────────────┐
array set synth {
    area,recover_design_area "false"
    area,target_utilization "0.7"
    area,max_utilization "0.8"
}

# ┌─ Power Optimization Settings ───────────────────────────────────────────────┐
array set synth {
    power,effort "none"
    power,clock_gating "true"
    power,operand_isolation "false"
    power,multi_vt_optimization "false"
    power,dynamic_voltage_scaling "false"
}

# ┌─ Output Format Controls ────────────────────────────────────────────────────┐
array set synth {
    output,save_ddc "true"
    output,save_verilog "true"
    output,save_sdf "false"
    output,save_constraints "true"
    output,save_svf "false"
    output,save_spef "false"
    output,save_sdc "true"
    output,netlist_format "verilog"
}

# ┌─ Design Variables ─────────────────────────────────────────────────────┐
array set synth {
    design,top_module          ""
    design,target_library      ""
    design,link_library        ""
}

# ┌─ Synthesis Control Variables ──────────────────────────────────────────┐
array set synth {
    synthesis,timing_driven    true
    synthesis,area_recovery    true
    synthesis,clock_gating     true
    synthesis,scan_insertion   false
    synthesis,boundary_opt     true
    synthesis,max_fanout       32
    synthesis,max_transition   "0.5"
    synthesis,max_capacitance  "0.5"
    synthesis,max_cores        4
}

# ┌─ Output Path Variables ────────────────────────────────────────────────┐
array set synth {
    output,netlist_dir         "results/synth"
    output,report_dir          "reports/synth"
    output,work_dir            "work/SYNTH"
}

# ┌─ FC-RM Compile/Synthesis Control (values aligned with FC-RM Y-2026.03) ─┐
array set synth {
    compile,unified_flow          true
    compile,qor_metric            "timing"
    compile,qor_mode              "balanced"
    compile,qor_version           ""
    compile,congestion_effort     "medium"
    compile,enable_spg            false
    compile,high_effort_timing    true
    compile,reduced_effort        false
    compile,enable_irdp           false
    dft_insert_enable             false
    upf_mode                      "none"
    output,block_labeling         true
}

# ┌─ Design Style ─────────────────────────────────────────────────────────┐
array set synth {
    chip_type                     "flat"
    input,rtl_format              "sverilog"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::synth_config_loaded]} {
    puts "INFO: SYNTH configuration loaded successfully - [llength $synth(stages)] stages, [expr {[llength $synth(subnodes,inputs1)] + [llength $synth(subnodes,init_design1)] + [llength $synth(subnodes,synthesis1)] + [llength $synth(subnodes,export_data1)] + [llength $synth(subnodes,release_data1)]}] total subnodes"
    set ::synth_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF SYNTH CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
