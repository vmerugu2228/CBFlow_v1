#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    ENGINEERING CHANGE ORDERS FLOW CONFIGURATION             ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all ECO flow specific configurations organized
# under a single eco() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/ECO_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         ECO CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# Merge metadata
array set eco {
    stages {netlist1 def1 sdc1 library1 eco1 export_db1}

    merge_entry_stage     netlist1
    merge_handoff_stage   export_db1
    merge_parallel_stages {}
    subnodes,eco1 {setup run validate finish}
    subnodes,export_db1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set eco {
    dependencies,netlist1 {}
    dependencies,def1 {}
    dependencies,sdc1 {}
    dependencies,library1 {}
    dependencies,eco1 {netlist1 def1 sdc1 library1}
    dependencies,export_db1 {eco1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# eco stage subnodes
# export_db stage subnodes
array set eco {

    subnode_dependencies,eco1,setup {}
    subnode_dependencies,eco1,run {setup}
    subnode_dependencies,eco1,validate {run}
    subnode_dependencies,eco1,finish {validate}

    subnode_dependencies,export_db1,setup {}
    subnode_dependencies,export_db1,run {setup}
    subnode_dependencies,export_db1,validate {run}
    subnode_dependencies,export_db1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set eco {
    tool,vendor "synopsys"
    tool,name "fc"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {fc icc2}
    default_tool "fc"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set eco {
    runtime,timeout,netlist1 10
    runtime,timeout,def1 10
    runtime,timeout,sdc1 10
    runtime,timeout,library1 10
    runtime,timeout,eco1 45
    runtime,timeout,export_db1 20
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set eco {
    stage_types,netlist1 "inputs"
    stage_types,def1 "inputs"
    stage_types,sdc1 "inputs"
    stage_types,library1 "inputs"
    stage_types,eco1 "execution"
    stage_types,export_db1 "export_data"

    node_types,netlist1 "inputs"
    node_types,def1 "inputs"
    node_types,sdc1 "inputs"
    node_types,library1 "inputs"
    node_types,eco1 "eco"
    node_types,export_db1 "export_db"

    node_descriptions,netlist1 "Gate-level netlist input"
    node_descriptions,def1 "DEF floorplan input"
    node_descriptions,sdc1 "SDC timing constraints input"
    node_descriptions,library1 "Technology library input"
    node_descriptions,eco1 "Engineering change orders implementation and validation (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_db1 "Export ECO database and deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set eco {
    critical_files,eco1 {eco(input,netlist) eco(input,def) eco(input,sdc_func_file)}

    mandatory_outputs,eco1 {results/eco/eco_netlist.v results/eco/eco_changes.rpt}
    mandatory_outputs,export_db1 {results/db/eco.db}

}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set eco {
    mandatory_input_groups {
        netlist_inputs {eco(input,netlist)}
        sdc_inputs {eco(input,sdc_release_tag) eco(input,sdc_release_dir) eco(input,sdc_func_file)}
        def_inputs {eco(input,def)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set eco {
    release_types,eco,description "ECO deliverables for design implementation"
    release_types,eco,files {
        "results/eco/eco_netlist.v" "netlist/eco_netlist.v"
        "results/eco/eco_changes.rpt" "reports/eco_changes.rpt"
        "results/db/eco.db" "db/eco_database.db"
    }
}

# ┌─ ECO Control Variables ────────────────────────────────────────────────┐
array set eco {
    input,change_file          ""
    input,reference_database   ""
    eco,type                   "functional"
    eco,metal_eco              true
    eco,cell_replacement       true
    eco,spare_cell_prefix      "SPARE_"
    eco,legalize_placement     true
    eco,reroute_modified       true
    eco,incr_route_post        true
    output,block_labeling      true
    output,report_dir          "reports/eco"
    output,results_dir         "results/eco"
    output,work_dir            "work/ECO"
}

# ┌─ FC-RM Timing ECO Control ─────────────────────────────────────────────────┐
array set eco {
    eco,engine                  "smsa"
    eco,pba_mode                "path"
    eco,extraction_mode         "fusion_adv"
    eco,filler_cell_prefix      "FILL"
}

# ┌─ FC-RM Functional ECO Control ─────────────────────────────────────────────┐
array set eco {
    eco,mode                    "mpi"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::eco_config_loaded]} {
    puts "INFO: ECO configuration loaded successfully - [llength $eco(stages)] stages, [expr {[llength $eco(subnodes,netlist1)] + [llength $eco(subnodes,def1)] + [llength $eco(subnodes,sdc1)] + [llength $eco(subnodes,library1)] + [llength $eco(subnodes,eco1)] + [llength $eco(subnodes,export_db1)]}] total subnodes"
    set ::eco_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF ECO CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════