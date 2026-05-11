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
    stages {netlist1 upf1 power_spec1 clp1 release_data1}

    merge_entry_stage     netlist1
    merge_handoff_stage   clp1
    merge_parallel_stages {release_data1}
    subnodes,clp1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set clp {
    dependencies,netlist1 {}
    dependencies,upf1 {}
    dependencies,power_spec1 {}
    dependencies,clp1 {netlist1 upf1 power_spec1}
    dependencies,release_data1 {clp1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# clp stage subnodes
# release_data stage subnodes
array set clp {

    subnode_dependencies,clp1,setup {}
    subnode_dependencies,clp1,run {setup}
    subnode_dependencies,clp1,validate {run}
    subnode_dependencies,clp1,finish {validate}

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
    runtime,timeout,netlist1 10
    runtime,timeout,upf1 10
    runtime,timeout,power_spec1 10
    runtime,timeout,clp1 60
    runtime,timeout,release_data1 10
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set clp {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,upf1,upf "upf_inputs"
    subnode_input_types,power_spec1,power_spec "power_spec_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs stage directories
# clp stage directories
# release_data stage directories
array set clp {

    subnode_work_dirs,clp1,setup "work/clp/setup"
    subnode_work_dirs,clp1,run "work/clp/run"
    subnode_work_dirs,clp1,validate "work/clp/validate"
    subnode_work_dirs,clp1,finish "work/clp/finish"

    subnode_work_dirs,release_data1,setup "work/release_data/setup"
    subnode_work_dirs,release_data1,run "work/release_data/run"
    subnode_work_dirs,release_data1,validate "work/release_data/validate"
    subnode_work_dirs,release_data1,finish "work/release_data/finish"
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set clp {
    stage_types,netlist1 "inputs"
    stage_types,upf1 "inputs"
    stage_types,power_spec1 "inputs"
    stage_types,clp1 "execution"
    stage_types,release_data1 "release_data"

    node_types,netlist1 "inputs"
    node_types,upf1 "inputs"
    node_types,power_spec1 "inputs"
    node_types,clp1 "clp"
    node_types,release_data1 "release_data"

    node_descriptions,netlist1 "Gate-level netlist input"
    node_descriptions,upf1 "UPF power intent input"
    node_descriptions,power_spec1 "Power specification input"
    node_descriptions,clp1 "Conformal low power verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release CLP deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set clp {
    critical_files,clp1 {clp(input,netlist) clp(input,upf_file)}

    mandatory_outputs,clp1 {results/clp/power_verification.rpt}

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

# ┌─ FC-RM VC LP App Var Control ───────────────────────────────────────────┐
array set clp {
    check,continue_on_error    true
    check,hanging_crossover    true
    check,multi_driver         true
    check,verdi_debug          true
    upf_mode                   "prime"
}

# ┌─ Low Power Check Control ──────────────────────────────────────────────┐
array set clp {
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
    puts "INFO: CLP configuration loaded successfully - [llength $clp(stages)] stages, [expr {[llength $clp(subnodes,netlist1)] + [llength $clp(subnodes,upf1)] + [llength $clp(subnodes,power_spec1)] + [llength $clp(subnodes,clp1)] + [llength $clp(subnodes,release_data1)]}] total subnodes"
    set ::clp_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF CLP CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════