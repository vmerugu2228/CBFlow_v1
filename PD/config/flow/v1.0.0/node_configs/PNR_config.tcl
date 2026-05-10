#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       PLACE AND ROUTE FLOW CONFIGURATION                    ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all PNR flow specific configurations organized
# under a single pnr() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/PNR_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         PNR CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# NOTE: Stage names use numeric suffix (place1, cts1) to distinguish from node types (place, cts)
#       This allows multiple instances: place1, place2, etc.
# Merge metadata - used when PNR is part of a merged flow (e.g., FP_PNR, SYNTH_FP_PNR)
array set pnr {
    stages {inputs1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}

    merge_entry_stage     inputs1
    merge_handoff_stage   export_data1
    merge_parallel_stages {release_data1}

    subnodes,inputs1       {setup netlist sdc def upf validate finish}
    subnodes,init_design1  {setup run validate finish}
    subnodes,place1 {setup run validate finish}
    subnodes,cts1 {setup run validate finish}
    subnodes,cts_opt1 {setup run validate finish}
    subnodes,route1 {setup run validate finish}
    subnodes,pro1 {setup run validate finish}
    subnodes,signoff1 {setup run validate finish}
    subnodes,export_data1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set pnr {
    dependencies,inputs1       {}
    dependencies,init_design1  {inputs1}
    dependencies,place1 {init_design1}
    dependencies,cts1 {place1}
    dependencies,cts_opt1 {cts1}
    dependencies,route1 {cts_opt1}
    dependencies,pro1 {route1}
    dependencies,signoff1 {pro1}
    dependencies,export_data1 {signoff1}
    dependencies,release_data1 {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# place1 stage subnodes
# cts1 stage subnodes
# cts_opt1 stage subnodes
# route1 stage subnodes
# pro1 stage subnodes
# signoff1 stage subnodes
# export_data1 stage subnodes
# release_data1 stage subnodes
array set pnr {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {}
    subnode_dependencies,inputs1,sdc {}
    subnode_dependencies,inputs1,def {}
    subnode_dependencies,inputs1,upf {}
    subnode_dependencies,inputs1,validate {setup netlist sdc def upf}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,init_design1,setup {}
    subnode_dependencies,init_design1,run {setup}
    subnode_dependencies,init_design1,validate {run}
    subnode_dependencies,init_design1,finish {validate}

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
array set pnr {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {innovus icc fc aprisa}
    default_tool "fc"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set pnr {
    runtime,timeout,inputs1 30
    runtime,timeout,init_design1 30
    runtime,timeout,place1 180
    runtime,timeout,cts1 60
    runtime,timeout,cts_opt1 45
    runtime,timeout,route1 240
    runtime,timeout,pro1 90
    runtime,timeout,signoff1 30
    runtime,timeout,export_data1 25
    runtime,timeout,release_data1 20
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set pnr {
    subnode_input_types,inputs1,netlist "netlist_inputs"
    subnode_input_types,inputs1,sdc "sdc_inputs"
    subnode_input_types,inputs1,def "def_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
    subnode_input_types,inputs1,library "library_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs1 stage directories
# place1 stage directories
# cts1 stage directories
# cts_opt1 stage directories
# route1 stage directories
# pro1 stage directories
# signoff1 stage directories
# export_data1 stage directories
# release_data1 stage directories
array set pnr {
    subnode_work_dirs,inputs1,setup "work/inputs1/setup"
    subnode_work_dirs,inputs1,netlist "work/inputs1/netlist"
    subnode_work_dirs,inputs1,sdc "work/inputs1/sdc"
    subnode_work_dirs,inputs1,def "work/inputs1/def"
    subnode_work_dirs,inputs1,upf "work/inputs1/upf"
    subnode_work_dirs,inputs1,library "work/inputs1/library"
    subnode_work_dirs,inputs1,validate "work/inputs1/validate"
    subnode_work_dirs,inputs1,finish "work/inputs1/finish"

    subnode_work_dirs,init_design1,setup "work/init_design1/setup"
    subnode_work_dirs,init_design1,run "work/init_design1/run"
    subnode_work_dirs,init_design1,validate "work/init_design1/validate"
    subnode_work_dirs,init_design1,finish "work/init_design1/finish"

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
array set pnr {
    stage_types,inputs1 "inputs"
    stage_types,init_design1 "execution"
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
    node_types,place1 "place"
    node_types,cts1 "cts"
    node_types,cts_opt1 "cts_opt"
    node_types,route1 "route"
    node_types,pro1 "pro"
    node_types,signoff1 "signoff"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (8 subnodes: setup, netlist, sdc, def, upf, library, validate, finish)"
    node_descriptions,init_design1 "Design library creation, floorplan loading, technology setup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,place1 "Standard cell placement (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts1 "Clock tree synthesis (4 subnodes: setup, run, validate, finish)"
    node_descriptions,cts_opt1 "Clock tree optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,route1 "Global and detailed routing (4 subnodes: setup, run, validate, finish)"
    node_descriptions,pro1 "Post-route optimization (4 subnodes: setup, run, validate, finish)"
    node_descriptions,signoff1 "Final design sign-off (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Export PNR database (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release PNR deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set pnr {
    critical_files,inputs1 {pnr(input,netlist) pnr(input,sdc_func_file) pnr(input,def_file)}
    critical_files,place1 {pnr(input,netlist) pnr(input,sdc_func_file) pnr(input,def_file)}
    critical_files,cts1 {pnr(input,netlist) pnr(input,sdc_func_file)}
    critical_files,route1 {pnr(input,netlist) pnr(input,def_file)}

    mandatory_outputs,place1 {results/place1/place.enc results/place1/place.rpt}
    mandatory_outputs,cts1 {results/cts1/cts.enc results/cts1/cts.rpt}
    mandatory_outputs,route1 {results/route1/route.enc results/route1/route.rpt}
    mandatory_outputs,signoff1 {results/gds/final.gds results/netlist/final.v results/def/final.def}

    optional_files,inputs1 {pnr(input,upf_file) pnr(input,tcl_scripts)}
    optional_files,place1 {pnr(place,scripts)}
}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set pnr {
    mandatory_input_groups {
        netlist_inputs {pnr(input,netlist)}
        sdc_inputs {pnr(input,sdc_release_tag) pnr(input,sdc_release_dir) pnr(input,sdc_func_file)}
        def_inputs {pnr(input,def_file)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set pnr {
    release_types,signoff1,description "PNR signoff deliverables for tapeout"
    release_types,signoff1,files {
        "results/gds/final.gds" "gds/final_layout.gds"
        "results/netlist/final.v" "netlist/final_netlist.v"
        "results/def/final.def" "def/final_design.def"
        "results/spef/final.spef" "spef/final_parasitic.spef"
        "results/timing/final_timing.rpt" "reports/final_timing.rpt"
    }
}

# ┌─ Advanced Configuration ──────────────────────────────────────────────────┐
array set pnr {
    mmmc,enabled_stages {cts1 route1 pro1 signoff1}
    parallel_stages {place1 cts1}
}

# ┌─ MMMC Report Expectations ─────────────────────────────────────────────────┐
# Defines which MMMC reports are expected for each stage
# Base MMMC reports expected for all MMMC-enabled stages
# Stage-specific additional MMMC reports
array set pnr {
    mmmc_reports,base {mmmc_timing mmmc_scenarios}
    mmmc_reports,base_files {mmmc_setup}
    mmmc_reports,route1 {mmmc_power}
    mmmc_reports,pro1 {mmmc_power mmmc_crosstalk}
    mmmc_reports,signoff1 {mmmc_power mmmc_crosstalk mmmc_final_summary mmmc_noise mmmc_si}
}

# ┌─ Analysis & Reporting Control ─────────────────────────────────────────────┐
array set pnr {
    analysis,max_paths         100
    analysis,significant_digits 4
}

# ┌─ Placement Control ────────────────────────────────────────────────────────┐
array set pnr {
    place,effort               "high"
    place,congestion_aware     true
    place,timing_driven        true
    place,max_density          0.85
    place,high_utilization_flow false
}

# ┌─ CTS Control ──────────────────────────────────────────────────────────┐
array set pnr {
    cts,target_skew            "50"
    cts,max_transition         "100"
    cts,buffer_cells           ""
    cts,inverter_cells         ""
}

# ┌─ Routing Control ──────────────────────────────────────────────────────┐
array set pnr {
    route,min_layer            "M2"
    route,max_layer            "M8"
    route,antenna_fix          true
    route,metal_fill           true
    route,si_aware             true
}

# ┌─ FC-RM Endpoint Optimization Control ───────────────────────────────────┐
array set pnr {
    route_opt,enable_endpoint_opt   false
    endpoint_opt,auto_metric        "timing"
    endpoint_opt,max_paths          10000
    endpoint_opt,slack_threshold    -0.001
    endpoint_opt,target_scenarios   ""
    endpoint_opt,path_group_filter  ""
    endpoint_opt,loop_count         1
}

# ┌─ Design Style ─────────────────────────────────────────────────────────┐
array set pnr {
    chip_type                       "flat"
}

# ┌─ Output Paths ─────────────────────────────────────────────────────────┐
array set pnr {
    output,netlist_dir         "results/pnr"
    output,report_dir          "reports/pnr"
    output,work_dir            "work/PNR"
    output,gds_file            "results/pnr/final.gds"
    output,final_netlist       "results/pnr/final.v"
    output,final_def           "results/pnr/final.def"
    output,final_spef          "results/pnr/final.spef"
}

# ┌─ FC-RM Compile Control (values aligned with FC-RM Y-2026.03) ──────────┐
array set pnr {
    compile,unified_flow        true
    compile,qor_metric          "timing"
    compile,qor_mode            "balanced"
    compile,qor_version         ""
    compile,congestion_effort   "medium"
    compile,high_effort_timing  true
    compile,reduced_effort      false
    compile,enable_spg          false
    compile,enable_irdp         false
}

# ┌─ FC-RM CTS Control ────────────────────────────────────────────────────┐
array set pnr {
    cts,style                   "standard"
    cts_primary_corner          ""
    clock_opt_cts,redundant_via false
    clock_opt_cts,enable_aocv   true
}

# ┌─ FC-RM Route Optimization Control ─────────────────────────────────────┐
array set pnr {
    route_opt,enable_hyper          false
    route_opt,extraction_mode       "fusion_adv"
    route_opt,pba_mode              "path"
    route_opt,redundant_via         true
    route_opt,incr_route_detail_mode "auto"
    route_opt,enable_irdccd         false
}

# ┌─ FC-RM Signoff Control ────────────────────────────────────────────────┐
array set pnr {
    signoff,insert_filler       true
    signoff,insert_decap        true
    signoff,drc_check           true
    signoff,fix_drc             true
    signoff,metal_fill          true
    signoff,metal_fill_track_based "off"
}

# ┌─ FC-RM Output Control ─────────────────────────────────────────────────┐
array set pnr {
    output,write_gds            true
    output,write_oasis          false
    output,block_labeling       true
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::pnr_config_loaded]} {
    puts "INFO: PNR configuration loaded successfully - [llength $pnr(stages)] stages, [expr {[llength $pnr(subnodes,inputs1)] + [llength $pnr(subnodes,init_design1)] + [llength $pnr(subnodes,place1)] + [llength $pnr(subnodes,cts1)] + [llength $pnr(subnodes,cts_opt1)] + [llength $pnr(subnodes,route1)] + [llength $pnr(subnodes,pro1)] + [llength $pnr(subnodes,signoff1)] + [llength $pnr(subnodes,export_data1)] + [llength $pnr(subnodes,release_data1)]}] total subnodes"
    set ::pnr_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF PNR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════