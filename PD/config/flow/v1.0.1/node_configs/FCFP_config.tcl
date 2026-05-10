#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    FULLCHIP FLOORPLANNING FLOW CONFIGURATION                ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all FCFP flow specific configurations organized
# under a single fcfp() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/FCFP_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         FCFP CONFIGURATION ARRAY                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set fcfp {
    stages {inputs1 fc_floorplan1 fc_powerplan1 fc_post_floorplan1 export_data1 release_data1}

    subnodes,inputs1 {setup netlist sdc def upf library validate finish}
    subnodes,fc_floorplan1 {setup run validate finish}
    subnodes,fc_powerplan1 {setup run validate finish}
    subnodes,fc_post_floorplan1 {setup run validate finish}
    subnodes,export_data1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set fcfp {
    dependencies,inputs1 {}
    dependencies,fc_floorplan1 {inputs1}
    dependencies,fc_powerplan1 {fc_floorplan1}
    dependencies,fc_post_floorplan1 {fc_powerplan1}
    dependencies,export_data1 {fc_post_floorplan1}
    dependencies,release_data1 {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# fc_floorplan stage subnodes
# fc_powerplan stage subnodes
# fc_post_floorplan stage subnodes
# export_data stage subnodes
# release_data stage subnodes
array set fcfp {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {setup}
    subnode_dependencies,inputs1,sdc {setup}
    subnode_dependencies,inputs1,def {setup}
    subnode_dependencies,inputs1,upf {setup}
    subnode_dependencies,inputs1,library {setup}
    subnode_dependencies,inputs1,validate {netlist sdc def upf library}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,fc_floorplan1,setup {}
    subnode_dependencies,fc_floorplan1,run {setup}
    subnode_dependencies,fc_floorplan1,validate {run}
    subnode_dependencies,fc_floorplan1,finish {validate}

    subnode_dependencies,fc_powerplan1,setup {}
    subnode_dependencies,fc_powerplan1,run {setup}
    subnode_dependencies,fc_powerplan1,validate {run}
    subnode_dependencies,fc_powerplan1,finish {validate}

    subnode_dependencies,fc_post_floorplan1,setup {}
    subnode_dependencies,fc_post_floorplan1,run {setup}
    subnode_dependencies,fc_post_floorplan1,validate {run}
    subnode_dependencies,fc_post_floorplan1,finish {validate}

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
array set fcfp {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {fc innovus}
    default_tool "fc"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set fcfp {
    runtime,timeout,inputs1 25
    runtime,timeout,fc_floorplan1 120
    runtime,timeout,fc_powerplan1 90
    runtime,timeout,fc_post_floorplan1 60
    runtime,timeout,export_data1 20
    runtime,timeout,release_data1 15
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set fcfp {
    subnode_input_types,inputs1,netlist "netlist_inputs"
    subnode_input_types,inputs1,sdc "sdc_inputs"
    subnode_input_types,inputs1,def "def_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
    subnode_input_types,inputs1,library "library_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs stage directories
# fc_floorplan stage directories
# fc_powerplan stage directories
# fc_post_floorplan stage directories
# export_data stage directories
# release_data stage directories
array set fcfp {
    subnode_work_dirs,inputs1,setup "work/inputs/setup"
    subnode_work_dirs,inputs1,netlist "work/inputs/netlist"
    subnode_work_dirs,inputs1,sdc "work/inputs/sdc"
    subnode_work_dirs,inputs1,def "work/inputs/def"
    subnode_work_dirs,inputs1,upf "work/inputs/upf"
    subnode_work_dirs,inputs1,library "work/inputs/library"
    subnode_work_dirs,inputs1,validate "work/inputs/validate"
    subnode_work_dirs,inputs1,finish "work/inputs/finish"

    subnode_work_dirs,fc_floorplan1,setup "work/fc_floorplan/setup"
    subnode_work_dirs,fc_floorplan1,run "work/fc_floorplan/run"
    subnode_work_dirs,fc_floorplan1,validate "work/fc_floorplan/validate"
    subnode_work_dirs,fc_floorplan1,finish "work/fc_floorplan/finish"

    subnode_work_dirs,fc_powerplan1,setup "work/fc_powerplan/setup"
    subnode_work_dirs,fc_powerplan1,run "work/fc_powerplan/run"
    subnode_work_dirs,fc_powerplan1,validate "work/fc_powerplan/validate"
    subnode_work_dirs,fc_powerplan1,finish "work/fc_powerplan/finish"

    subnode_work_dirs,fc_post_floorplan1,setup "work/fc_post_floorplan/setup"
    subnode_work_dirs,fc_post_floorplan1,run "work/fc_post_floorplan/run"
    subnode_work_dirs,fc_post_floorplan1,validate "work/fc_post_floorplan/validate"
    subnode_work_dirs,fc_post_floorplan1,finish "work/fc_post_floorplan/finish"

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
array set fcfp {
    stage_types,inputs1 "inputs"
    stage_types,fc_floorplan1 "execution"
    stage_types,fc_powerplan1 "execution"
    stage_types,fc_post_floorplan1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,fc_floorplan1 "fc_floorplan"
    node_types,fc_powerplan1 "fc_powerplan"
    node_types,fc_post_floorplan1 "fc_post_floorplan"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (8 subnodes: setup, netlist, sdc, def, upf, library, validate, finish)"
    node_descriptions,fc_floorplan1 "Fullchip floorplan creation and macro placement (4 subnodes: setup, run, validate, finish)"
    node_descriptions,fc_powerplan1 "Fullchip power grid design and planning (4 subnodes: setup, run, validate, finish)"
    node_descriptions,fc_post_floorplan1 "Post-floorplan optimization and cleanup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Export fullchip floorplan data (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release fullchip floorplan deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set fcfp {
    critical_files,inputs1 {fcfp(input,netlist) fcfp(input,sdc_func_file) fcfp(input,def_file)}
    critical_files,fc_floorplan1 {fcfp(input,netlist) fcfp(input,def_file)}
    critical_files,fc_powerplan1 {fcfp(input,upf_file)}

    mandatory_outputs,fc_floorplan1 {results/floorplan/floorplan.def results/floorplan/macro_placement.rpt}
    mandatory_outputs,fc_powerplan1 {results/powerplan/power_grid.def results/powerplan/power_analysis.rpt}
    mandatory_outputs,fc_post_floorplan1 {results/post_fp/final_floorplan.def}

    optional_files,inputs1 {fcfp(input,floorplan_scripts)}
}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set fcfp {
    mandatory_input_groups {
        netlist_inputs {fcfp(input,netlist)}
        sdc_inputs {fcfp(input,sdc_release_tag) fcfp(input,sdc_release_dir) fcfp(input,sdc_func_file)}
        def_inputs {fcfp(input,def_file)}
        upf_inputs {fcfp(input,upf_release_tag) fcfp(input,upf_release_dir) fcfp(input,upf_file)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set fcfp {
    release_types,floorplan,description "Fullchip floorplan deliverables for implementation"
    release_types,floorplan,files {
        "results/floorplan/floorplan.def" "def/fullchip_floorplan.def"
        "results/powerplan/power_grid.def" "def/fullchip_powerplan.def"
        "results/post_fp/final_floorplan.def" "def/final_fullchip_floorplan.def"
        "results/floorplan/macro_placement.rpt" "reports/macro_placement.rpt"
        "results/powerplan/power_analysis.rpt" "reports/power_grid_analysis.rpt"
    }
}

# ┌─ Fullchip Floorplan Control ───────────────────────────────────────────┐
array set fcfp {
    input,partition_list       ""
    input,macro_placement_file ""
    input,io_pad_file          ""
    floorplan,die_width        ""
    floorplan,die_height       ""
    floorplan,core_utilization 0.65
    floorplan,macro_spacing    "5.0"
    floorplan,partition_spacing "10.0"
    power,net_names            "VDD VSS"
    power,ring_width           "3.0"
    power,mesh_layers          "M8 M9 M10"
    output,report_dir          "reports/fcfp"
    output,results_dir         "results/fcfp"
    output,work_dir            "work/FCFP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::fcfp_config_loaded]} {
    puts "INFO: FCFP configuration loaded successfully - [llength $fcfp(stages)] stages, [expr {[llength $fcfp(subnodes,inputs1)] + [llength $fcfp(subnodes,fc_floorplan1)] + [llength $fcfp(subnodes,fc_powerplan1)] + [llength $fcfp(subnodes,fc_post_floorplan1)] + [llength $fcfp(subnodes,export_data1)] + [llength $fcfp(subnodes,release_data1)]}] total subnodes"
    set ::fcfp_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF FCFP CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════