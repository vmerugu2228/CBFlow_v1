#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      POWER OPTIMIZATION FLOW CONFIGURATION                  ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all POPT flow specific configurations organized
# under a single popt() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/POPT_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         POPT CONFIGURATION ARRAY                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set popt {
    stages {netlist1 sdc1 upf1 merge_timing1 power_opt1 post_merge1 release_data1}
    subnodes,merge_timing1 {setup run validate finish}
    subnodes,power_opt1 {setup run validate finish}
    subnodes,post_merge1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set popt {
    dependencies,netlist1 {}
    dependencies,sdc1 {}
    dependencies,upf1 {}
    dependencies,merge_timing1 {netlist1 sdc1 upf1}
    dependencies,power_opt1 {merge_timing1}
    dependencies,post_merge1 {power_opt1}
    dependencies,release_data1 {post_merge1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# merge_timing stage subnodes
# power_opt stage subnodes
# post_merge stage subnodes
# release_data stage subnodes
array set popt {

    subnode_dependencies,merge_timing1,setup {}
    subnode_dependencies,merge_timing1,run {setup}
    subnode_dependencies,merge_timing1,validate {run}
    subnode_dependencies,merge_timing1,finish {validate}

    subnode_dependencies,power_opt1,setup {}
    subnode_dependencies,power_opt1,run {setup}
    subnode_dependencies,power_opt1,validate {run}
    subnode_dependencies,power_opt1,finish {validate}

    subnode_dependencies,post_merge1,setup {}
    subnode_dependencies,post_merge1,run {setup}
    subnode_dependencies,post_merge1,validate {run}
    subnode_dependencies,post_merge1,finish {validate}

    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set popt {
    tool,vendor "synopsys"
    tool,name "pt"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {power_compiler joules}
    default_tool "pt"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set popt {
    runtime,timeout,netlist1 10
    runtime,timeout,sdc1 10
    runtime,timeout,upf1 10
    runtime,timeout,merge_timing1 30
    runtime,timeout,power_opt1 90
    runtime,timeout,post_merge1 20
    runtime,timeout,release_data1 15
}

# ┌─ Subnode Input Type Mappings ───────────────────────────────────────────┐
array set popt {
    subnode_input_types,netlist1,netlist "netlist_inputs"
    subnode_input_types,sdc1,sdc "sdc_inputs"
    subnode_input_types,upf1,upf "upf_inputs"
}

# ┌─ Subnode Working Directories ────────────────────────────────────────────┐
# inputs stage directories
# merge_timing stage directories
# power_opt stage directories
# post_merge stage directories
# release_data stage directories
array set popt {

    subnode_work_dirs,merge_timing1,setup "work/merge_timing/setup"
    subnode_work_dirs,merge_timing1,run "work/merge_timing/run"
    subnode_work_dirs,merge_timing1,validate "work/merge_timing/validate"
    subnode_work_dirs,merge_timing1,finish "work/merge_timing/finish"

    subnode_work_dirs,power_opt1,setup "work/power_opt/setup"
    subnode_work_dirs,power_opt1,run "work/power_opt/run"
    subnode_work_dirs,power_opt1,validate "work/power_opt/validate"
    subnode_work_dirs,power_opt1,finish "work/power_opt/finish"

    subnode_work_dirs,post_merge1,setup "work/post_merge/setup"
    subnode_work_dirs,post_merge1,run "work/post_merge/run"
    subnode_work_dirs,post_merge1,validate "work/post_merge/validate"
    subnode_work_dirs,post_merge1,finish "work/post_merge/finish"

    subnode_work_dirs,release_data1,setup "work/release_data/setup"
    subnode_work_dirs,release_data1,run "work/release_data/run"
    subnode_work_dirs,release_data1,validate "work/release_data/validate"
    subnode_work_dirs,release_data1,finish "work/release_data/finish"
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set popt {
    stage_types,netlist1 "inputs"
    stage_types,sdc1 "inputs"
    stage_types,upf1 "inputs"
    stage_types,merge_timing1 "execution"
    stage_types,power_opt1 "execution"
    stage_types,post_merge1 "execution"
    stage_types,release_data1 "release_data"

    node_types,netlist1 "inputs"
    node_types,sdc1 "inputs"
    node_types,upf1 "inputs"
    node_types,merge_timing1 "merge_timing"
    node_types,power_opt1 "power_opt"
    node_types,post_merge1 "post_merge"
    node_types,release_data1 "release_data"

    node_descriptions,netlist1 "Gate-level netlist input"
    node_descriptions,sdc1 "SDC timing constraints input"
    node_descriptions,upf1 "UPF power intent input"
    node_descriptions,merge_timing1 "Merge timing data and constraints (4 subnodes: setup, run, validate, finish)"
    node_descriptions,power_opt1 "Power optimization and clock gating (4 subnodes: setup, run, validate, finish)"
    node_descriptions,post_merge1 "Post-optimization merging and cleanup (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release power optimization deliverables (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set popt {
    critical_files,merge_timing1 {popt(input,netlist) popt(input,sdc_func_file)}
    critical_files,power_opt1 {popt(input,netlist) popt(input,upf_file)}

    mandatory_outputs,power_opt1 {results/power_opt/optimized_netlist.v results/power_opt/power_report.rpt}
    mandatory_outputs,post_merge1 {results/merge/final_netlist.v}

}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set popt {
    mandatory_input_groups {
        netlist_inputs {popt(input,netlist)}
        sdc_inputs {popt(input,sdc_release_tag) popt(input,sdc_release_dir) popt(input,sdc_func_file)}
        upf_inputs {popt(input,upf_release_tag) popt(input,upf_release_dir) popt(input,upf_file)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set popt {
    release_types,optimization,description "Power optimization reports and optimized netlists"
    release_types,optimization,files {
        "results/power_opt/optimized_netlist.v" "netlist/power_optimized_netlist.v"
        "results/power_opt/power_report.rpt" "reports/power_optimization.rpt"
        "results/merge/final_netlist.v" "netlist/final_optimized_netlist.v"
    }
}

# ┌─ Power Optimization Control ───────────────────────────────────────────┐
array set popt {
    power,target_total         ""
    power,leakage_budget       ""
    power,dynamic_budget       ""
    optimization,clock_gating_min_bitwidth 4
    optimization,operand_isolation true
    optimization,multi_vt      true
    optimization,effort        "high"
    output,report_dir          "reports/popt"
    output,results_dir         "results/popt"
    output,work_dir            "work/POPT"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::popt_config_loaded]} {
    puts "INFO: POPT configuration loaded successfully - [llength $popt(stages)] stages, [expr {[llength $popt(subnodes,netlist1)] + [llength $popt(subnodes,sdc1)] + [llength $popt(subnodes,upf1)] + [llength $popt(subnodes,merge_timing1)] + [llength $popt(subnodes,power_opt1)] + [llength $popt(subnodes,post_merge1)] + [llength $popt(subnodes,release_data1)]}] total subnodes"
    set ::popt_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF POPT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════