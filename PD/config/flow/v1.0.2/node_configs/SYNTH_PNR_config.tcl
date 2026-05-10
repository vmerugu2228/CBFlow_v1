#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                   SYNTHESIS + PLACE AND ROUTE FLOW CONFIGURATION            ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all SYNTH_PNR flow specific configurations organized
# under a single synth_pnr() array structure for clean configuration management.
# SYNTH_PNR is a first-class flow type with FC-RM aligned stage names.
#
# Usage: source config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      SYNTH_PNR CONFIGURATION ARRAY                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# NOTE: Stage names use numeric suffix (synthesis1, place1) to distinguish from node types
#       This allows multiple instances: synthesis1, compile2, etc.
# FC-RM aligned stage names for unified synthesis + place-and-route flow
array set synth_pnr {
    stages {inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}

    subnodes,inputs1          {setup rtl sdc upf validate finish}
    subnodes,init_design1     {setup run validate finish}
    subnodes,synthesis1         {setup run validate finish}
    subnodes,place1       {setup run validate finish}
    subnodes,cts1   {setup run validate finish}
    subnodes,cts_opt1  {setup run validate finish}
    subnodes,route1      {setup run validate finish}
    subnodes,pro1       {setup run validate finish}
    subnodes,signoff1     {setup run validate finish}
    subnodes,export_data1      {setup run validate finish}
    subnodes,release_data1    {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set synth_pnr {
    dependencies,inputs1          {}
    dependencies,init_design1     {inputs1}
    dependencies,synthesis1         {init_design1}
    dependencies,place1       {synthesis1}
    dependencies,cts1   {place1}
    dependencies,cts_opt1  {cts1}
    dependencies,route1      {cts_opt1}
    dependencies,pro1       {route1}
    dependencies,signoff1     {pro1}
    dependencies,export_data1     {signoff1}
    dependencies,release_data1    {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs1 stage subnodes
# synthesis1 stage subnodes
# place1 stage subnodes
# cts1 stage subnodes
# cts_opt1 stage subnodes
# route1 stage subnodes
# pro1 stage subnodes
# signoff1 stage subnodes
# export_data1 stage subnodes
# release_data1 stage subnodes
array set synth_pnr {
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

    subnode_dependencies,place1,setup {}
    subnode_dependencies,place1,run {setup}
    subnode_dependencies,place1,validate {run}
    subnode_dependencies,place1,finish {validate}

    subnode_dependencies,cts1,setup {}
    subnode_dependencies,cts1,run {setup}
    subnode_dependencies,cts1,validate {run}
    subnode_dependencies,cts1,finish {validate}

    subnode_dependencies,cts_opt1,setup {}
    subnode_dependencies,cts_opt1,run {setup}
    subnode_dependencies,cts_opt1,validate {run}
    subnode_dependencies,cts_opt1,finish {validate}

    subnode_dependencies,route1,setup {}
    subnode_dependencies,route1,run {setup}
    subnode_dependencies,route1,validate {run}
    subnode_dependencies,route1,finish {validate}

    subnode_dependencies,pro1,setup {}
    subnode_dependencies,pro1,run {setup}
    subnode_dependencies,pro1,validate {run}
    subnode_dependencies,pro1,finish {validate}

    subnode_dependencies,signoff1,setup {}
    subnode_dependencies,signoff1,run {setup}
    subnode_dependencies,signoff1,validate {run}
    subnode_dependencies,signoff1,finish {validate}


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
array set synth_pnr {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {fc}
    default_tool "fc"
}

# ┌─ MMMC Configuration ────────────────────────────────────────────────────┐
array set synth_pnr {
    mmmc,enabled              true
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set         "signoff"
    mmmc,multi_corner_compile true
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set synth_pnr {
    runtime,timeout,inputs1          30
    runtime,timeout,init_design1     30
    runtime,timeout,synthesis1         180
    runtime,timeout,place1       180
    runtime,timeout,cts1   120
    runtime,timeout,cts_opt1  120
    runtime,timeout,route1      240
    runtime,timeout,pro1       180
    runtime,timeout,signoff1     90
    runtime,timeout,export_data1      30
    runtime,timeout,release_data1    20
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set synth_pnr {
    subnode_input_types,inputs1,rtl "rtl_inputs"
    subnode_input_types,inputs1,sdc "sdc_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs1 stage directories
# synthesis1 stage directories
# place1 stage directories
# cts1 stage directories
# cts_opt1 stage directories
# route1 stage directories
# pro1 stage directories
# signoff1 stage directories
# export_data1 stage directories
# release_data1 stage directories
array set synth_pnr {
    subnode_work_dirs,inputs1,setup "work/inputs1/setup"
    subnode_work_dirs,inputs1,rtl "work/inputs1/rtl"
    subnode_work_dirs,inputs1,sdc "work/inputs1/sdc"
    subnode_work_dirs,inputs1,upf "work/inputs1/upf"
    subnode_work_dirs,inputs1,validate "work/inputs1/validate"
    subnode_work_dirs,inputs1,finish "work/inputs1/finish"

    subnode_work_dirs,synthesis1,setup "work/synthesis1/setup"
    subnode_work_dirs,synthesis1,run "work/synthesis1/run"
    subnode_work_dirs,synthesis1,validate "work/synthesis1/validate"
    subnode_work_dirs,synthesis1,finish "work/synthesis1/finish"

    subnode_work_dirs,place1,setup "work/place1/setup"
    subnode_work_dirs,place1,run "work/place1/run"
    subnode_work_dirs,place1,validate "work/place1/validate"
    subnode_work_dirs,place1,finish "work/place1/finish"

    subnode_work_dirs,cts1,setup "work/cts1/setup"
    subnode_work_dirs,cts1,run "work/cts1/run"
    subnode_work_dirs,cts1,validate "work/cts1/validate"
    subnode_work_dirs,cts1,finish "work/cts1/finish"

    subnode_work_dirs,cts_opt1,setup "work/cts_opt1/setup"
    subnode_work_dirs,cts_opt1,run "work/cts_opt1/run"
    subnode_work_dirs,cts_opt1,validate "work/cts_opt1/validate"
    subnode_work_dirs,cts_opt1,finish "work/cts_opt1/finish"

    subnode_work_dirs,route1,setup "work/route1/setup"
    subnode_work_dirs,route1,run "work/route1/run"
    subnode_work_dirs,route1,validate "work/route1/validate"
    subnode_work_dirs,route1,finish "work/route1/finish"

    subnode_work_dirs,pro1,setup "work/pro1/setup"
    subnode_work_dirs,pro1,run "work/pro1/run"
    subnode_work_dirs,pro1,validate "work/pro1/validate"
    subnode_work_dirs,pro1,finish "work/pro1/finish"

    subnode_work_dirs,signoff1,setup "work/signoff1/setup"
    subnode_work_dirs,signoff1,run "work/signoff1/run"
    subnode_work_dirs,signoff1,validate "work/signoff1/validate"
    subnode_work_dirs,signoff1,finish "work/signoff1/finish"


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
array set synth_pnr {
    stage_types,inputs1 "inputs"
    stage_types,init_design1 "execution"
    stage_types,synthesis1 "execution"
    stage_types,place1 "execution"
    stage_types,cts1 "execution"
    stage_types,cts_opt1 "execution"
    stage_types,route1 "execution"
    stage_types,pro1 "execution"
    stage_types,signoff1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,init_design1 "init_design"
    node_types,synthesis1 "synthesis"
    node_types,place1 "place"
    node_types,cts1 "cts"
    node_types,cts_opt1 "cts_opt"
    node_types,route1 "route"
    node_types,pro1 "pro"
    node_types,signoff1 "signoff"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (8 subnodes: setup, netlist, sdc, def, library, upf, validate, finish)"
    node_descriptions,init_design1 "Design library creation, floorplan loading, parasitic tech setup, QoR strategy init (FC-RM init_design)"
    node_descriptions,synthesis1 "Logic synthesis and compile (FC-RM compile_fusion)"
    node_descriptions,place1 "Placement and placement optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts1 "Clock tree synthesis optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts_opt1 "Post-CTS timing optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,route1 "Global and detailed routing (4 subnodes: setup, run, validate, finish)"
    node_descriptions,pro1 "Route optimization and timing closure (4 subnodes: setup, run, validate, finish)"
    node_descriptions,signoff1 "Chip finishing and filler insertion (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Write final design data and reports (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release SYNTH_PNR deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set synth_pnr {
    critical_files,inputs1 {synth_pnr(input,netlist) synth_pnr(input,sdc_func_file) synth_pnr(input,def_file)}
    critical_files,synthesis1 {synth_pnr(input,netlist) synth_pnr(input,sdc_func_file)}
    critical_files,place1 {synth_pnr(input,netlist) synth_pnr(input,sdc_func_file) synth_pnr(input,def_file)}
    critical_files,route1 {synth_pnr(input,netlist) synth_pnr(input,def_file)}

    mandatory_outputs,synthesis1 {results/synthesis1/compile.ddc results/synthesis1/compile.rpt}
    mandatory_outputs,place1 {results/place1/place_opt.enc results/place1/place_opt.rpt}
    mandatory_outputs,cts1 {results/cts1/clock_opt_cts.enc results/cts1/clock_opt_cts.rpt}
    mandatory_outputs,route1 {results/route1/route_auto.enc results/route1/route_auto.rpt}
    mandatory_outputs,export_data1 {results/gds/final.gds results/netlist/final.v results/def/final.def}

    optional_files,inputs1 {synth_pnr(input,upf_file) synth_pnr(input,tcl_scripts)}
    optional_files,synthesis1 {synth_pnr(synthesis,scripts)}
}

# ┌─ Mandatory User Inputs (validated at run creation) ─────────────────────────┐
# These variables MUST be set (non-empty) in user_config.tcl before creating a run.
# To add/remove mandatory inputs, edit this list.
array set synth_pnr {
    mandatory_user_inputs {
        synth_pnr(input,rtl_filelist)
        synth_pnr(input,rtl_format)
        synth_pnr(input,sdc_func_file)
        synth_pnr(input,upf_file)
    }
}

# ┌─ Mandatory Input Groups (stage-level validation) ──────────────────────────┐
array set synth_pnr {
    mandatory_input_groups {
        netlist_inputs {synth_pnr(input,netlist)}
        sdc_inputs {synth_pnr(input,sdc_release_tag) synth_pnr(input,sdc_release_dir) synth_pnr(input,sdc_func_file)}
        def_inputs {synth_pnr(input,def_file)}
    }
}

# ┌─ Design Style ──────────────────────────────────────────────────────────────┐
array set synth_pnr {
    chip_type                  "flat"
}

# ┌─ Analysis & Reporting Control ─────────────────────────────────────────────┐
array set synth_pnr {
    analysis,max_paths         100
    analysis,significant_digits 4
}

# ┌─ Placement Control ────────────────────────────────────────────────────────┐
array set synth_pnr {
    place,effort               "high"
    place,congestion_aware     true
    place,timing_driven        true
    place,max_density          0.85
    place,high_utilization_flow false
}

# ┌─ CTS Control ──────────────────────────────────────────────────────────┐
array set synth_pnr {
    cts,target_skew            "50"
    cts,max_transition         "100"
    cts,buffer_cells           ""
    cts,inverter_cells         ""
}

# ┌─ Routing Control ──────────────────────────────────────────────────────┐
array set synth_pnr {
    route,min_layer            "M2"
    route,max_layer            "M8"
    route,antenna_fix          true
    route,metal_fill           true
    route,si_aware             true
}

# ┌─ RTL Input Format — set in user_config.tcl ─────────────────────────────┐
# synth_pnr(input,rtl_format) is mandatory in user_config (sverilog|verilog|vhdl)

# ┌─ FC-RM Compile/Synthesis Control (values aligned with FC-RM Y-2026.03) ─┐
array set synth_pnr {
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
}

# ┌─ FC-RM CTS Control ────────────────────────────────────────────────────┐
array set synth_pnr {
    cts,style                     "standard"
    cts_primary_corner            ""
    clock_opt_cts,redundant_via   false
    clock_opt_cts,enable_aocv     true
}

# ┌─ FC-RM Route Control ──────────────────────────────────────────────────┐
array set synth_pnr {
    route_auto,enable_redundant_via  true
    route_auto,enable_shields        false
}

# ┌─ FC-RM Route Optimization Control ─────────────────────────────────────┐
array set synth_pnr {
    route_opt,enable_hyper          false
    route_opt,extraction_mode       "fusion_adv"
    route_opt,pba_mode              "path"
    route_opt,redundant_via         true
    route_opt,incr_route_detail_mode "auto"
    route_opt,enable_irdccd         false
}

# ┌─ FC-RM Endpoint Optimization Control (in route_opt/pro stage) ──────────┐
array set synth_pnr {
    route_opt,enable_endpoint_opt   false
    endpoint_opt,auto_metric        "timing"
    endpoint_opt,max_paths          10000
    endpoint_opt,slack_threshold    -0.001
    endpoint_opt,target_scenarios   ""
    endpoint_opt,path_group_filter  ""
    endpoint_opt,loop_count         1
}

# ┌─ FC-RM Signoff/Chip Finish Control ─────────────────────────────────────┐
array set synth_pnr {
    signoff,insert_filler     true
    signoff,insert_decap      true
    signoff,drc_check             true
    signoff,fix_drc               true
    signoff,metal_fill            true
    signoff,metal_fill_track_based "off"
}

# ┌─ Output Paths ─────────────────────────────────────────────────────────┐
array set synth_pnr {
    output,netlist_dir         "results/synth_pnr"
    output,report_dir          "reports/synth_pnr"
    output,work_dir            "work/SYNTH_PNR"
    output,gds_file            "results/synth_pnr/final.gds"
    output,final_netlist       "results/synth_pnr/final.v"
    output,final_def           "results/synth_pnr/final.def"
    output,final_spef          "results/synth_pnr/final.spef"
    output,write_gds            true
    output,write_oasis          false
    output,block_labeling       true
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set synth_pnr {
    release_types,export_data1,description "SYNTH_PNR signoff deliverables for tapeout"
    release_types,export_data1,files {
        "results/gds/final.gds" "gds/final_layout.gds"
        "results/netlist/final.v" "netlist/final_netlist.v"
        "results/def/final.def" "def/final_design.def"
        "results/spef/final.spef" "spef/final_parasitic.spef"
        "results/timing/final_timing.rpt" "reports/final_timing.rpt"
    }
}

# ┌─ MMMC Report Expectations ─────────────────────────────────────────────────┐
# Defines which MMMC reports are expected for each stage
# Base MMMC reports expected for all MMMC-enabled stages
# Stage-specific additional MMMC reports
array set synth_pnr {
    mmmc_reports,base {mmmc_timing mmmc_scenarios}
    mmmc_reports,base_files {mmmc_setup}
    mmmc_reports,synthesis1 {mmmc_power}
    mmmc_reports,route1 {mmmc_power}
    mmmc_reports,pro1 {mmmc_power mmmc_crosstalk}
    mmmc_reports,signoff1 {mmmc_power mmmc_crosstalk mmmc_final_summary}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::synth_pnr_config_loaded]} {
    set ::synth_pnr_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF SYNTH_PNR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
