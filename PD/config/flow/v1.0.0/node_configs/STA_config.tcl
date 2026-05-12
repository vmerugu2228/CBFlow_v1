#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                 STATIC TIMING ANALYSIS FLOW CONFIGURATION                   ║
# ║                    MMMC-Aware Multi-Stage Pipeline                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Enhanced STA flow with MMMC automation, split setup/hold analysis,
# and dual tool support (Synopsys PrimeTime + Cadence Tempus).
#
# Pipeline:
#   inputs1 -> extraction1 -> timing1 (per-corner) -> reporting1 -> release_data1
#
# Usage: source config/flow/v1.0.0/node_configs/STA_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         STA CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set sta {
    stages {netlist1 sdc1 spef1 library1 extraction1 timing1 reporting1 release_data1}
    subnodes,extraction1    {setup run validate finish}
    subnodes,timing1        {dynamic}
    subnodes,reporting1     {setup run validate finish}
    subnodes,release_data1  {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
# Note: timing1 uses dynamic subnodes (per-scenario), enabling parallel
#       execution for different MMMC scenarios.
array set sta {
    dependencies,netlist1       {}
    dependencies,sdc1           {}
    dependencies,spef1          {}
    dependencies,library1       {}
    dependencies,extraction1    {netlist1 sdc1 spef1 library1}
    dependencies,timing1        {extraction1}
    dependencies,reporting1     {timing1}
    dependencies,release_data1  {reporting1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
array set sta {

    subnode_dependencies,extraction1,setup {}
    subnode_dependencies,extraction1,run {setup}
    subnode_dependencies,extraction1,validate {run}
    subnode_dependencies,extraction1,finish {validate}

    subnode_dependencies,timing1,dynamic {}

    subnode_dependencies,reporting1,setup {}
    subnode_dependencies,reporting1,run {setup}
    subnode_dependencies,reporting1,validate {run}
    subnode_dependencies,reporting1,finish {validate}


    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
}

# ┌─ Tool Configuration ────────────────────────────────────────────────────┐
array set sta {
    tool,vendor "synopsys"
    tool,name "pt"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {pt tempus}
    default_tool "pt"
}

# ┌─ MMMC Configuration ────────────────────────────────────────────────────┐
# Controls which MMMC scenarios are used for timing analysis.
# scenario_set references mmmc_config.tcl scenario sets.
array set sta {
    mmmc,enabled            true
    mmmc,enabled_stages     {extraction1 timing1 reporting1}
    mmmc,default_scenario_set "signoff"
    mmmc,scenario_set       "signoff"
    mmmc,dynamic_scenarios  true
    mmmc,parallel_scenarios true
}

# ┌─ Runtime Settings ───────────────────────────────────────────────────────┐
array set sta {
    runtime,timeout,netlist1       10
    runtime,timeout,sdc1           10
    runtime,timeout,spef1          10
    runtime,timeout,library1       10
    runtime,timeout,extraction1    30
    runtime,timeout,timing1        60
    runtime,timeout,reporting1     20
    runtime,timeout,release_data1  10
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set sta {
    stage_types,netlist1       "inputs"
    stage_types,sdc1           "inputs"
    stage_types,spef1          "inputs"
    stage_types,library1       "inputs"
    stage_types,extraction1    "execution"
    stage_types,timing1        "execution"
    stage_types,reporting1     "execution"
    stage_types,release_data1  "release_data"

    node_types,netlist1       "inputs"
    node_types,sdc1           "inputs"
    node_types,spef1          "inputs"
    node_types,library1       "inputs"
    node_types,extraction1    "extraction"
    node_types,timing1        "timing"
    node_types,reporting1     "reporting"
    node_types,release_data1  "release_data"

    node_descriptions,netlist1       "Gate-level netlist input"
    node_descriptions,sdc1           "SDC timing constraints input"
    node_descriptions,spef1          "SPEF parasitic data input"
    node_descriptions,library1       "Technology library input"
    node_descriptions,extraction1    "Parasitic extraction for accurate timing models (4 subnodes)"
    node_descriptions,timing1        "Dynamic per-scenario timing analysis - each scenario runs setup+hold (parallelizable via make -j)"
    node_descriptions,reporting1     "Cross-corner aggregation - worst-case analysis, MMMC timing summary (4 subnodes)"
    node_descriptions,release_data1  "Package and release final timing sign-off deliverables (4 subnodes)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set sta {
    critical_files,extraction1    {sta(input,netlist) sta(input,sdc_func_file)}
    critical_files,timing1        {sta(input,netlist) sta(input,spef) sta(input,sdc_func_file)}
    critical_files,reporting1     {}
    critical_files,release_data1  {}

    mandatory_outputs,extraction1    {results/extraction/parasitic.spef}
    mandatory_outputs,timing1        {}
    mandatory_outputs,reporting1     {reports/sta/mmmc_timing_summary.rpt}

}

# ┌─ Mandatory Input Groups ──────────────────────────────────────────────────┐
array set sta {
    mandatory_input_groups {
        netlist_inputs {sta(input,netlist)}
        sdc_inputs {sta(input,sdc_release_tag) sta(input,sdc_release_dir) sta(input,sdc_func_file)}
        spef_inputs {sta(input,spef)}
    }
}

# ┌─ MMMC Report Expectations ────────────────────────────────────────────────┐
array set sta {
    mmmc_reports,base              {mmmc_timing mmmc_scenarios}
    mmmc_reports,timing1           {mmmc_hold_timing mmmc_hold_violations}
    mmmc_reports,reporting1        {mmmc_final_summary mmmc_cross_corner}
}

# ┌─ Merge Configuration (for merged/flat mode) ─────────────────────────────┐
array set sta {
    merge_parallel_stages {release_data1}
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set sta {
    release_types,timing,description "MMMC timing analysis reports and sign-off data"
    release_types,timing,files {
        "reports/sta/mmmc_timing_summary.rpt"     "reports/final_mmmc_timing.rpt"
        "reports/sta/mmmc_hold_summary.rpt"         "reports/hold_timing_summary.rpt"
        "results/extraction/parasitic.spef"         "spef/final_parasitic.spef"
    }
}

# ┌─ Analysis Control ─────────────────────────────────────────────────────┐
array set sta {
    analysis,setup_margin      "0.0"
    analysis,hold_margin       "0.0"
    analysis,max_paths         100
    analysis,significant_digits 4
    analysis,ocv_mode          "aocv"
    analysis,si_aware          true
    analysis,derating_file     ""
}

# ┌─ Reporting Control ────────────────────────────────────────────────────┐
array set sta {
    reporting,top_violations   50
    reporting,include_input_pins true
    reporting,include_nets     true
    reporting,report_format    "rpt"
}

# ┌─ Output Paths ─────────────────────────────────────────────────────────┐
array set sta {
    output,report_dir          "reports/sta"
    output,results_dir         "results/sta"
    output,work_dir            "work/STA"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if {![info exists ::sta_config_loaded]} {
    set _total_subnodes 0
    foreach _stage $sta(stages) {
        if {[info exists sta(subnodes,$_stage)]} {
            incr _total_subnodes [llength $sta(subnodes,$_stage)]
        } else {
            incr _total_subnodes 1 ;# leaf node counts as 1
        }
    }
    puts "INFO: STA configuration loaded - [llength $sta(stages)] stages, $_total_subnodes total subnodes"
    puts "INFO: MMMC enabled=$sta(mmmc,enabled), scenario_set=$sta(mmmc,scenario_set)"
    puts "INFO: Tools: $sta(supported_tools) (default: $sta(default_tool))"
    puts "INFO: Dynamic timing stage: per-scenario parallelism via make -j"
    set ::sta_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF STA CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ PT-RM W-2024.09 Analysis Variables ───────────────────────────────────────┐
array set sta {
    analysis,nworst            1
    analysis,report_power      "true"
    analysis,pba_mode          "exhaustive"
    extract_etm                "false"
}
