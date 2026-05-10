#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        FLOORPLAN FLOW CONFIGURATION                         ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all FP flow specific configurations organized
# under a single fp() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/FP_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         FP CONFIGURATION ARRAY                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# Entry stage - first stage that receives data from previous flow (in merged flows)
# Handoff stage - the stage that connects to next flow's inputs (in merged flows)
# Parallel stages - stages that branch off and don't block next flow (in merged flows)
array set fp {
    stages {inputs1 import_design1 floorplan1 powerplan1 export_data1 release_data1}

    merge_entry_stage    inputs1

    merge_handoff_stage  export_data1

    merge_parallel_stages {release_data1}

    subnodes,inputs1 {netlist sdc def upf library validate finish}
    subnodes,import_design1 {setup run validate finish}
    subnodes,floorplan1 {setup run validate finish}
    subnodes,powerplan1 {setup run validate finish}
    subnodes,export_data1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set fp {
    dependencies,inputs1 {}
    dependencies,import_design1 {inputs1}
    dependencies,floorplan1 {import_design1}
    dependencies,powerplan1 {floorplan1}
    dependencies,export_data1 {powerplan1}
    dependencies,release_data1 {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# import_design stage subnodes
# floorplan stage subnodes
# powerplan stage subnodes
# export_data stage subnodes
# release_data stage subnodes
array set fp {
    subnode_dependencies,inputs1,netlist {}
    subnode_dependencies,inputs1,sdc {}
    subnode_dependencies,inputs1,def {}
    subnode_dependencies,inputs1,upf {}
    subnode_dependencies,inputs1,library {}
    subnode_dependencies,inputs1,validate {netlist sdc def upf library}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,import_design1,setup {}
    subnode_dependencies,import_design1,run {setup}
    subnode_dependencies,import_design1,validate {run}
    subnode_dependencies,import_design1,finish {validate}

    subnode_dependencies,floorplan1,setup {}
    subnode_dependencies,floorplan1,run {setup}
    subnode_dependencies,floorplan1,validate {run}
    subnode_dependencies,floorplan1,finish {validate}

    subnode_dependencies,powerplan1,setup {}
    subnode_dependencies,powerplan1,run {setup}
    subnode_dependencies,powerplan1,validate {run}
    subnode_dependencies,powerplan1,finish {validate}

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
array set fp {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {innovus icc2}
    default_tool "fc"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set fp {
    runtime,timeout,inputs1 25
    runtime,timeout,import_design1 30
    runtime,timeout,floorplan1 90
    runtime,timeout,powerplan1 60
    runtime,timeout,post_floorplan1 45
    runtime,timeout,export_data1 20
    runtime,timeout,release_data1 15
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set fp {
    subnode_input_types,inputs1,netlist "netlist_inputs"
    subnode_input_types,inputs1,sdc "sdc_inputs"
    subnode_input_types,inputs1,def "def_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
    subnode_input_types,inputs1,library "library_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs stage directories
# import_design stage directories
# floorplan stage directories
# powerplan stage directories
# post_floorplan stage directories
# export_data stage directories
# release_data stage directories
array set fp {
    subnode_work_dirs,inputs1,setup "work/inputs/setup"
    subnode_work_dirs,inputs1,netlist "work/inputs/netlist"
    subnode_work_dirs,inputs1,sdc "work/inputs/sdc"
    subnode_work_dirs,inputs1,def "work/inputs/def"
    subnode_work_dirs,inputs1,upf "work/inputs/upf"
    subnode_work_dirs,inputs1,library "work/inputs/library"
    subnode_work_dirs,inputs1,validate "work/inputs/validate"
    subnode_work_dirs,inputs1,finish "work/inputs/finish"

    subnode_work_dirs,import_design1,setup "work/import_design/setup"
    subnode_work_dirs,import_design1,run "work/import_design/run"
    subnode_work_dirs,import_design1,validate "work/import_design/validate"
    subnode_work_dirs,import_design1,finish "work/import_design/finish"

    subnode_work_dirs,floorplan1,setup "work/floorplan/setup"
    subnode_work_dirs,floorplan1,run "work/floorplan/run"
    subnode_work_dirs,floorplan1,validate "work/floorplan/validate"
    subnode_work_dirs,floorplan1,finish "work/floorplan/finish"

    subnode_work_dirs,powerplan1,setup "work/powerplan/setup"
    subnode_work_dirs,powerplan1,run "work/powerplan/run"
    subnode_work_dirs,powerplan1,validate "work/powerplan/validate"
    subnode_work_dirs,powerplan1,finish "work/powerplan/finish"

    subnode_work_dirs,post_floorplan1,setup "work/post_floorplan/setup"
    subnode_work_dirs,post_floorplan1,run "work/post_floorplan/run"
    subnode_work_dirs,post_floorplan1,validate "work/post_floorplan/validate"
    subnode_work_dirs,post_floorplan1,finish "work/post_floorplan/finish"

    subnode_work_dirs,export_data1,setup "work/export_data/setup"
    subnode_work_dirs,export_data1,run "work/export_data/run"
    subnode_work_dirs,export_data1,validate "work/export_data/validate"
    subnode_work_dirs,export_data1,finish "work/export_data/finish"

    subnode_work_dirs,release_data1,setup "work/release_data/setup"
    subnode_work_dirs,release_data1,run "work/release_data/run"
    subnode_work_dirs,release_data1,validate "work/release_data/validate"
    subnode_work_dirs,release_data1,finish "work/release_data/finish"
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set fp {
    stage_types,inputs1 "inputs"
    stage_types,import_design1 "execution"
    stage_types,floorplan1 "execution"
    stage_types,powerplan1 "execution"
    stage_types,post_floorplan1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,import_design1 "import_design"
    node_types,floorplan1 "floorplan"
    node_types,powerplan1 "powerplan"
    node_types,post_floorplan1 "post_floorplan"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (8 subnodes: setup, netlist, sdc, def, upf, library, validate, finish)"
    node_descriptions,import_design1 "Design initialization and import (4 subnodes: setup, run, validate, finish)"
    node_descriptions,floorplan1 "Floorplan creation and I/O placement (4 subnodes: setup, run, validate, finish)"
    node_descriptions,powerplan1 "Power grid design and planning (4 subnodes: setup, run, validate, finish)"
    node_descriptions,post_floorplan1 "Post-floorplan optimization and cleanup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Export floorplan database (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release floorplan deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set fp {
    critical_files,inputs1 {fp(input,netlist) fp(input,sdc_func_file) fp(input,def_file)}
    critical_files,import_design1 {fp(input,netlist)}
    critical_files,floorplan1 {fp(input,netlist) fp(input,def_file)}
    critical_files,powerplan1 {fp(input,upf_file)}

    mandatory_outputs,import_design1 {results/design/design_imported.def}
    mandatory_outputs,floorplan1 {results/floorplan/floorplan.def results/floorplan/io_placement.rpt}
    mandatory_outputs,powerplan1 {results/powerplan/power_grid.def results/powerplan/power_analysis.rpt}
    mandatory_outputs,post_floorplan1 {results/post_fp/final_floorplan.def}

    optional_files,inputs1 {fp(input,upf_file) fp(input,tcl_scripts)}
}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set fp {
    mandatory_input_groups {
        netlist_inputs {fp(input,netlist)}
        sdc_inputs {fp(input,sdc_release_tag) fp(input,sdc_release_dir) fp(input,sdc_func_file)}
        def_inputs {fp(input,def_file)}
        upf_inputs {fp(input,upf_release_tag) fp(input,upf_release_dir) fp(input,upf_file)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set fp {
    release_types,floorplan,description "Floorplan deliverables for place and route"
    release_types,floorplan,files {
        "results/floorplan/floorplan.def" "def/floorplan.def"
        "results/powerplan/power_grid.def" "def/powerplan.def"
        "results/post_fp/final_floorplan.def" "def/final_floorplan.def"
        "results/floorplan/io_placement.rpt" "reports/io_placement.rpt"
        "results/powerplan/power_analysis.rpt" "reports/power_analysis.rpt"
    }
}

# ┌─ Floorplan Control Variables ──────────────────────────────────────────────┐
array set fp {
    floorplan,die_width        ""
    floorplan,die_height       ""
    floorplan,core_utilization 0.70
    floorplan,core_offset_x    "5.0"
    floorplan,core_offset_y    "5.0"
    floorplan,macro_spacing    "2.0"
    floorplan,macro_channel    "5.0"
    power,net_names            "VDD VSS"
    power,ring_width           "2.0"
    power,ring_spacing         "1.0"
    power,strap_width          "0.8"
    power,strap_pitch          "20.0"
    power,mesh_layers          "M8 M9"
    input,macro_placement_file ""
    input,io_constraint_file   ""
    output,floorplan_dir       "results/fp"
    output,report_dir          "reports/fp"
    output,work_dir            "work/FP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::fp_config_loaded]} {
    puts "INFO: FP configuration loaded successfully - [llength $fp(stages)] stages, [expr {[llength $fp(subnodes,inputs1)] + [llength $fp(subnodes,import_design1)] + [llength $fp(subnodes,floorplan1)] + [llength $fp(subnodes,powerplan1)] + [llength $fp(subnodes,export_data1)] + [llength $fp(subnodes,release_data1)]}] total subnodes"
    set ::fp_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF FP CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════