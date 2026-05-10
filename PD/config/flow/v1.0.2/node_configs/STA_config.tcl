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
#   inputs1 -> mmmc_setup1 -> extraction1 -> timing_setup1 ─┐
#                                             timing_hold1  ─┤-> reporting1 -> export_data1 -> release_data1
#
# Usage: source config/flow/v1.0.0/node_configs/STA_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         STA CONFIGURATION ARRAY                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Stage Definitions ──────────────────────────────────────────────┐
array set sta {
    stages {inputs1 mmmc_setup1 extraction1 timing1 reporting1 export_data1 release_data1}

    subnodes,inputs1        {setup netlist sdc spef library validate finish}
    subnodes,mmmc_setup1    {setup load_config resolve_scenarios validate finish}
    subnodes,extraction1    {setup run validate finish}
    subnodes,timing1        {dynamic}
    subnodes,reporting1     {setup run validate finish}
    subnodes,export_data1   {setup run validate finish}
    subnodes,release_data1  {setup run validate finish}
}

# ┌─ Stage Dependencies ────────────────────────────────────────────────────┐
# Note: timing_setup1 and timing_hold1 both depend only on extraction1,
#       enabling parallel execution for setup and hold analysis.
array set sta {
    dependencies,inputs1        {}
    dependencies,mmmc_setup1    {inputs1}
    dependencies,extraction1    {mmmc_setup1}
    dependencies,timing1        {extraction1}
    dependencies,reporting1     {timing1}
    dependencies,export_data1   {reporting1}
    dependencies,release_data1  {export_data1}
}

# ┌─ Subnode Dependencies ──────────────────────────────────────────────────┐
array set sta {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {setup}
    subnode_dependencies,inputs1,sdc {setup}
    subnode_dependencies,inputs1,spef {setup}
    subnode_dependencies,inputs1,library {setup}
    subnode_dependencies,inputs1,validate {netlist sdc spef library}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,mmmc_setup1,setup {}
    subnode_dependencies,mmmc_setup1,load_config {setup}
    subnode_dependencies,mmmc_setup1,resolve_scenarios {load_config}
    subnode_dependencies,mmmc_setup1,validate {resolve_scenarios}
    subnode_dependencies,mmmc_setup1,finish {validate}

    subnode_dependencies,extraction1,setup {}
    subnode_dependencies,extraction1,run {setup}
    subnode_dependencies,extraction1,validate {run}
    subnode_dependencies,extraction1,finish {validate}

    subnode_dependencies,timing1,dynamic {}

    subnode_dependencies,reporting1,setup {}
    subnode_dependencies,reporting1,run {setup}
    subnode_dependencies,reporting1,validate {run}
    subnode_dependencies,reporting1,finish {validate}

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
    runtime,timeout,inputs1        15
    runtime,timeout,mmmc_setup1    10
    runtime,timeout,extraction1    30
    runtime,timeout,timing1        60
    runtime,timeout,reporting1     20
    runtime,timeout,export_data1   15
    runtime,timeout,release_data1  10
}

# ┌─ Stage Type Mappings and Descriptions ───────────────────────────────────┐
array set sta {
    stage_types,inputs1        "inputs"
    stage_types,mmmc_setup1    "execution"
    stage_types,extraction1    "execution"
    stage_types,timing1        "execution"
    stage_types,reporting1     "execution"
    stage_types,export_data1   "export_data"
    stage_types,release_data1  "release_data"

    node_types,inputs1        "inputs"
    node_types,mmmc_setup1    "mmmc_setup"
    node_types,extraction1    "extraction"
    node_types,timing1        "timing"
    node_types,reporting1     "reporting"
    node_types,export_data1   "export_data"
    node_types,release_data1  "release_data"

    node_descriptions,inputs1        "Input file validation and preparation for timing analysis (7 subnodes)"
    node_descriptions,mmmc_setup1    "MMMC scenario resolution - resolves scenarios, generates dynamic per-scenario Make targets (5 subnodes)"
    node_descriptions,extraction1    "Parasitic extraction for accurate timing models (4 subnodes)"
    node_descriptions,timing1        "Dynamic per-scenario timing analysis - each scenario runs setup+hold (parallelizable via make -j)"
    node_descriptions,reporting1     "Cross-corner aggregation - worst-case analysis, MMMC timing summary (4 subnodes)"
    node_descriptions,export_data1   "Collect all STA results, timing reports, and SPEF files for downstream (4 subnodes)"
    node_descriptions,release_data1  "Package and release final timing sign-off deliverables (4 subnodes)"
}

# ┌─ File Requirements ───────────────────────────────────────────────────────┐
array set sta {
    critical_files,inputs1        {sta(input,netlist) sta(input,spef)}
    critical_files,mmmc_setup1    {}
    critical_files,extraction1    {sta(input,netlist) sta(input,sdc_func_file)}
    critical_files,timing1        {sta(input,netlist) sta(input,spef) sta(input,sdc_func_file)}
    critical_files,reporting1     {}
    critical_files,export_data1   {}
    critical_files,release_data1  {}

    mandatory_outputs,extraction1    {results/extraction/parasitic.spef}
    mandatory_outputs,mmmc_setup1    {work/STA/mmmc_setup/run/active_scenarios.tcl}
    mandatory_outputs,timing1        {}
    mandatory_outputs,reporting1     {reports/sta/mmmc_timing_summary.rpt}

    optional_files,inputs1 {sta(input,lib_files)}
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
    mmmc_reports,mmmc_setup1       {mmmc_active_scenarios}
    mmmc_reports,timing_setup1     {mmmc_setup_timing mmmc_setup_violations}
    mmmc_reports,timing_hold1      {mmmc_hold_timing mmmc_hold_violations}
    mmmc_reports,reporting1        {mmmc_final_summary mmmc_cross_corner}
}

# ┌─ Merge Configuration (for merged/flat mode) ─────────────────────────────┐
array set sta {
    merge_entry_stage     "mmmc_setup1"
    merge_handoff_stage   "export_data1"
    merge_parallel_stages {timing_setup1 timing_hold1}
}

# ┌─ Release Configuration ────────────────────────────────────────────────────┐
array set sta {
    release_types,timing,description "MMMC timing analysis reports and sign-off data"
    release_types,timing,files {
        "reports/sta/mmmc_timing_summary.rpt"     "reports/final_mmmc_timing.rpt"
        "reports/sta/mmmc_setup_summary.rpt"       "reports/setup_timing_summary.rpt"
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
        incr _total_subnodes [llength $sta(subnodes,$_stage)]
    }
    puts "INFO: STA configuration loaded - [llength $sta(stages)] stages, $_total_subnodes total subnodes"
    puts "INFO: MMMC enabled=$sta(mmmc,enabled), scenario_set=$sta(mmmc,scenario_set)"
    puts "INFO: Tools: $sta(supported_tools) (default: $sta(default_tool))"
    puts "INFO: Parallel stages: timing_setup1 || timing_hold1"
    set ::sta_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF STA CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
