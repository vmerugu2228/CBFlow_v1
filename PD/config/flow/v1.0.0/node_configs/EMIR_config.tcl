#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      POWER AND THERMAL ANALYSIS FLOW CONFIGURATION          ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all EMIR flow specific configurations organized
# under a single emir() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/EMIR_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         EMIR CONFIGURATION ARRAY                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set emir {
    stages {netlist1 def1 spef1 library1 power_analysis1 ir_drop1 thermal_analysis1}
    subnodes,power_analysis1 {setup run validate finish}
    subnodes,ir_drop1 {setup run validate finish}
    subnodes,thermal_analysis1 {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
array set emir {
    dependencies,netlist1 {}
    dependencies,def1 {}
    dependencies,spef1 {}
    dependencies,library1 {}
    dependencies,power_analysis1 {netlist1 def1 spef1 library1}
    dependencies,ir_drop1 {power_analysis1}
    dependencies,thermal_analysis1 {ir_drop1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
# inputs stage subnodes
# power_analysis stage subnodes
# ir_drop stage subnodes
# thermal_analysis stage subnodes
array set emir {

    subnode_dependencies,power_analysis1,setup {}
    subnode_dependencies,power_analysis1,run {setup}
    subnode_dependencies,power_analysis1,validate {run}
    subnode_dependencies,power_analysis1,finish {validate}

    subnode_dependencies,ir_drop1,setup {}
    subnode_dependencies,ir_drop1,run {setup}
    subnode_dependencies,ir_drop1,validate {run}
    subnode_dependencies,ir_drop1,finish {validate}

    subnode_dependencies,thermal_analysis1,setup {}
    subnode_dependencies,thermal_analysis1,run {setup}
    subnode_dependencies,thermal_analysis1,validate {run}
    subnode_dependencies,thermal_analysis1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set emir {
    tool,vendor "synopsys"
    tool,name "redhawk"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {redhawk voltus}
    default_tool "redhawk"
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set emir {
    runtime,timeout,netlist1 10
    runtime,timeout,def1 10
    runtime,timeout,spef1 10
    runtime,timeout,library1 10
    runtime,timeout,power_analysis1 60
    runtime,timeout,ir_drop1 45
    runtime,timeout,thermal_analysis1 30
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set emir {
    stage_types,netlist1 "inputs"
    stage_types,def1 "inputs"
    stage_types,spef1 "inputs"
    stage_types,library1 "inputs"
    stage_types,power_analysis1 "execution"
    stage_types,ir_drop1 "execution"
    stage_types,thermal_analysis1 "execution"

    node_types,netlist1 "inputs"
    node_types,def1 "inputs"
    node_types,spef1 "inputs"
    node_types,library1 "inputs"
    node_types,power_analysis1 "power_analysis"
    node_types,ir_drop1 "ir_drop"
    node_types,thermal_analysis1 "thermal_analysis"

    node_descriptions,netlist1 "Gate-level netlist input"
    node_descriptions,def1 "DEF floorplan input"
    node_descriptions,spef1 "SPEF parasitic data input"
    node_descriptions,library1 "Technology library input"
    node_descriptions,power_analysis1 "Power consumption analysis and vectorless estimation (4 subnodes: setup, run, validate, finish)"
    node_descriptions,ir_drop1 "IR drop analysis and voltage verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,thermal_analysis1 "Thermal analysis and hotspot identification (4 subnodes: setup, run, validate, finish)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set emir {
    critical_files,power_analysis1 {emir(input,netlist) emir(input,def)}
    critical_files,ir_drop1 {emir(input,netlist) emir(input,def) emir(input,spef)}
    critical_files,thermal_analysis1 {emir(input,netlist) emir(input,def)}

    mandatory_outputs,power_analysis1 {results/power/power.rpt}
    mandatory_outputs,ir_drop1 {results/ir_drop/ir_drop.rpt results/ir_drop/voltage_map.png}
    mandatory_outputs,thermal_analysis1 {results/thermal/thermal.rpt results/thermal/temperature_map.png}

}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set emir {
    mandatory_input_groups {
        netlist_inputs {emir(input,netlist)}
        def_inputs {emir(input,def)}
        spef_inputs {emir(input,spef)}
    }
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set emir {
    release_types,power,description "Power and thermal analysis reports and visualizations"
    release_types,power,files {
        "results/power/power.rpt" "reports/power_analysis.rpt"
        "results/ir_drop/ir_drop.rpt" "reports/ir_drop_analysis.rpt"
        "results/thermal/thermal.rpt" "reports/thermal_analysis.rpt"
        "results/ir_drop/voltage_map.png" "images/voltage_heatmap.png"
        "results/thermal/temperature_map.png" "images/thermal_heatmap.png"
    }
}

# ┌─ Analysis Control ─────────────────────────────────────────────────────┐
array set emir {
    input,power_activity_file  ""
    ir_drop,threshold          "30"
    ir_drop,enable             true
    thermal,enable             true
    thermal,max_temperature    "125"
    power,analysis_mode        "vectorless"
    output,report_dir          "reports/emir"
    output,results_dir         "results/emir"
    output,work_dir            "work/EMIR"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::emir_config_loaded]} {
    puts "INFO: EMIR configuration loaded successfully - [llength $emir(stages)] stages, [expr {[llength $emir(subnodes,netlist1)] + [llength $emir(subnodes,def1)] + [llength $emir(subnodes,spef1)] + [llength $emir(subnodes,library1)] + [llength $emir(subnodes,power_analysis1)] + [llength $emir(subnodes,ir_drop1)] + [llength $emir(subnodes,thermal_analysis1)]}] total subnodes"
    set ::emir_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF EMIR CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════