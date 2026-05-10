#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    CONFORMAL LOW POWER FLOW CONFIGURATION                   ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all CLP flow specific configurations organized
# under a single clp() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/CLP_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         CLP CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# Merge metadata
array set clp {
    stages {inputs1 clp1 export_data1 release_data1}

    merge_entry_stage     inputs1
    merge_handoff_stage   export_data1
    merge_parallel_stages {release_data1}

    subnodes,inputs1 {setup netlist upf power_spec validate finish}
    subnodes,clp1 {setup run validate finish}
    subnodes,export_data1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set clp {
    dependencies,inputs1 {}
    dependencies,clp1 {inputs1}
    dependencies,export_data1 {clp1}
    dependencies,release_data1 {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# clp stage subnodes
# export_data stage subnodes
# release_data stage subnodes
array set clp {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {setup}
    subnode_dependencies,inputs1,upf {setup}
    subnode_dependencies,inputs1,power_spec {setup}
    subnode_dependencies,inputs1,validate {netlist upf power_spec}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,clp1,setup {}
    subnode_dependencies,clp1,run {setup}
    subnode_dependencies,clp1,validate {run}
    subnode_dependencies,clp1,finish {validate}

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
array set clp {
    tool,vendor "synopsys"
    tool,name "vc_lp"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {vc_lp conformal_lp}
    default_tool "vc_lp"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set clp {
    runtime,timeout,inputs1 20
    runtime,timeout,clp1 60
    runtime,timeout,export_data1 15
    runtime,timeout,release_data1 10
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set clp {
    subnode_input_types,inputs1,netlist "netlist_inputs"
    subnode_input_types,inputs1,upf "upf_inputs"
    subnode_input_types,inputs1,power_spec "power_spec_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs stage directories
# clp stage directories
# export_data stage directories
# release_data stage directories
array set clp {
    subnode_work_dirs,inputs1,setup "work/inputs/setup"
    subnode_work_dirs,inputs1,netlist "work/inputs/netlist"
    subnode_work_dirs,inputs1,upf "work/inputs/upf"
    subnode_work_dirs,inputs1,power_spec "work/inputs/power_spec"
    subnode_work_dirs,inputs1,validate "work/inputs/validate"
    subnode_work_dirs,inputs1,finish "work/inputs/finish"

    subnode_work_dirs,clp1,setup "work/clp/setup"
    subnode_work_dirs,clp1,run "work/clp/run"
    subnode_work_dirs,clp1,validate "work/clp/validate"
    subnode_work_dirs,clp1,finish "work/clp/finish"

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
array set clp {
    stage_types,inputs1 "inputs"
    stage_types,clp1 "execution"
    stage_types,export_data1 "export_data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,clp1 "clp"
    node_types,export_data1 "export_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (6 subnodes: setup, netlist, upf, power_spec, validate, finish)"
    node_descriptions,clp1 "Conformal low power verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,export_data1 "Export CLP verification results (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release CLP deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set clp {
    critical_files,inputs1 {clp(input,netlist) clp(input,upf_file) clp(input,power_spec)}
    critical_files,clp1 {clp(input,netlist) clp(input,upf_file)}

    mandatory_outputs,clp1 {results/clp/power_verification.rpt}
    mandatory_outputs,export_data1 {results/db/clp_verification.db}

    optional_files,inputs1 {clp(input,clp_scripts)}
}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set clp {
    mandatory_input_groups {
        netlist_inputs {clp(input,netlist)}
        upf_inputs {clp(input,upf_release_tag) clp(input,upf_release_dir) clp(input,upf_file)}
        power_spec_inputs {clp(input,power_spec)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set clp {
    release_types,verification,description "Conformal low power verification reports and database"
    release_types,verification,files {
        "results/clp/power_verification.rpt" "reports/clp_verification.rpt"
        "results/db/clp_verification.db" "db/clp_verification.db"
    }
}

# ┌─ Low Power Check Control ──────────────────────────────────────────────┐
array set clp {
    input,reference_netlist    ""
    check,isolation            true
    check,retention            true
    check,level_shifter        true
    check,power_domain         true
    check,always_on            true
    check,voltage_area         true
    output,report_dir          "reports/clp"
    output,results_dir         "results/clp"
    output,work_dir            "work/CLP"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::clp_config_loaded]} {
    puts "INFO: CLP configuration loaded successfully - [llength $clp(stages)] stages, [expr {[llength $clp(subnodes,inputs1)] + [llength $clp(subnodes,clp1)] + [llength $clp(subnodes,export_data1)] + [llength $clp(subnodes,release_data1)]}] total subnodes"
    set ::clp_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF CLP CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════