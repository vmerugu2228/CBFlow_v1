#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    LOGIC EQUIVALENCE CHECKING FLOW CONFIGURATION            ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Flow: inputs → compare → validate
#   netlist_golden1, netlist_revised1, constraints1 (leaf inputs)
#   → compare1 (4 subnodes: setup, run, validate, finish)
#   → validate1 (4 subnodes: setup, run, validate, finish)
#
# Usage: source config/flow/v1.0.0/node_configs/LEC_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         LEC CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set lec {
    stages {netlist_golden1 netlist_revised1 constraints1 compare1 release_data1}

    merge_entry_stage     netlist_golden1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}
    subnodes,compare1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set lec {
    dependencies,netlist_golden1 {}
    dependencies,netlist_revised1 {}
    dependencies,constraints1 {}
    dependencies,compare1 {netlist_golden1 netlist_revised1 constraints1}
    dependencies,release_data1 {compare1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
array set lec {
    subnode_dependencies,compare1,setup {}
    subnode_dependencies,compare1,run {setup}
    subnode_dependencies,compare1,validate {run}
    subnode_dependencies,compare1,finish {validate}

    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
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
    runtime,timeout,compare1 60
    runtime,timeout,release_data1 10
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set lec {
    stage_types,netlist_golden1 "inputs"
    stage_types,netlist_revised1 "inputs"
    stage_types,constraints1 "inputs"
    stage_types,compare1 "execution"
    stage_types,release_data1 "release"

    node_types,netlist_golden1 "inputs"
    node_types,netlist_revised1 "inputs"
    node_types,constraints1 "inputs"
    node_types,compare1 "compare"
    node_types,release_data1 "release_data"

    node_descriptions,netlist_golden1 "Golden reference netlist input"
    node_descriptions,netlist_revised1 "Revised netlist input"
    node_descriptions,constraints1 "LEC constraints input"
    node_descriptions,compare1 "Design comparison between golden and revised netlists (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Release LEC results and reports"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set lec {
    critical_files,compare1 {lec(input,netlist_golden) lec(input,netlist_revised)}

    mandatory_outputs,compare1 {results/lec/comparison.rpt}
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

if {![info exists ::lec_config_loaded]} {
    puts "INFO: LEC configuration loaded — [llength $lec(stages)] stages"
    set ::lec_config_loaded true
}
