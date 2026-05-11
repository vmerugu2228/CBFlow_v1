#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    LOGIC EQUIVALENCE CHECKING FLOW CONFIGURATION            ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all LEC flow specific configurations organized
# under a single lec() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/LEC_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         LEC CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
# Merge metadata
array set lec {
    stages {netlist_golden1 netlist_revised1 constraints1 setup1 compare1 analyze1}

    merge_entry_stage     netlist_golden1
    merge_handoff_stage   analyze1
    merge_parallel_stages {}
    subnodes,setup1 {setup run validate finish}
    subnodes,compare1 {setup run validate finish}
    subnodes,analyze1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set lec {
    dependencies,netlist_golden1 {}
    dependencies,netlist_revised1 {}
    dependencies,constraints1 {}
    dependencies,setup1 {netlist_golden1 netlist_revised1 constraints1}
    dependencies,compare1 {setup1}
    dependencies,analyze1 {compare1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# setup stage subnodes
# compare stage subnodes
# analyze stage subnodes
array set lec {

    subnode_dependencies,setup1,setup {}
    subnode_dependencies,setup1,run {setup}
    subnode_dependencies,setup1,validate {run}
    subnode_dependencies,setup1,finish {validate}

    subnode_dependencies,compare1,setup {}
    subnode_dependencies,compare1,run {setup}
    subnode_dependencies,compare1,validate {run}
    subnode_dependencies,compare1,finish {validate}

    subnode_dependencies,analyze1,setup {}
    subnode_dependencies,analyze1,run {setup}
    subnode_dependencies,analyze1,validate {run}
    subnode_dependencies,analyze1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set lec {
    tool,vendor "synopsys"
    tool,name "formality"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {formality conformal}
    default_tool "formality"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set lec {
    runtime,timeout,netlist_golden1 10
    runtime,timeout,netlist_revised1 10
    runtime,timeout,constraints1 10
    runtime,timeout,setup1 30
    runtime,timeout,compare1 60
    runtime,timeout,analyze1 30
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set lec {
    stage_types,netlist_golden1 "inputs"
    stage_types,netlist_revised1 "inputs"
    stage_types,constraints1 "inputs"
    stage_types,setup1 "setup"
    stage_types,compare1 "execution"
    stage_types,analyze1 "execution"

    node_types,netlist_golden1 "inputs"
    node_types,netlist_revised1 "inputs"
    node_types,constraints1 "inputs"
    node_types,setup1 "setup"
    node_types,compare1 "compare"
    node_types,analyze1 "analyze"

    node_descriptions,netlist_golden1 "Golden reference netlist input"
    node_descriptions,netlist_revised1 "Revised netlist input"
    node_descriptions,constraints1 "LEC constraints input"
    node_descriptions,setup1 "Logic equivalence setup and configuration (4 subnodes: setup, run, validate, finish)"
    node_descriptions,compare1 "Design comparison between golden and revised netlists (4 subnodes: setup, run, validate, finish)"
    node_descriptions,analyze1 "Equivalence analysis and reporting (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set lec {
    critical_files,setup1 {lec(input,netlist_golden) lec(input,netlist_revised)}

    mandatory_outputs,compare1 {results/lec/comparison.rpt}
    mandatory_outputs,analyze1 {results/lec/equivalence.rpt results/lec/analysis.log}

}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set lec {
    mandatory_input_groups {
        netlist_golden_inputs {lec(input,netlist_golden)}
        netlist_revised_inputs {lec(input,netlist_revised)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set lec {
    release_types,equivalence,description "Logic equivalence checking results and reports"
    release_types,equivalence,files {
        "results/lec/comparison.rpt" "reports/lec_comparison.rpt"
        "results/lec/equivalence.rpt" "reports/lec_equivalence.rpt"
        "results/lec/analysis.log" "logs/lec_analysis.log"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::lec_config_loaded]} {
    puts "INFO: LEC configuration loaded successfully - [llength $lec(stages)] stages, [expr {[llength $lec(subnodes,netlist_golden1)] + [llength $lec(subnodes,netlist_revised1)] + [llength $lec(subnodes,constraints1)] + [llength $lec(subnodes,setup1)] + [llength $lec(subnodes,compare1)] + [llength $lec(subnodes,analyze1)]}] total subnodes"
    set ::lec_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF LEC CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════