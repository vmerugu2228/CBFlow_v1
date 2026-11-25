#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DV_SIGNOFF — Open-source tool configuration (vendor opensource, tool verilator)
# Sourced from DV_SIGNOFF_config.tcl when dv_signoff(tool,name) = verilator.
# Command files: DV/cmds/DV_SIGNOFF/opensource/verilator/v1.0.0/
#
# DV sign-off of a block for the phase (open-source UVM flow):
#   inputs    metrics (the M4_EXEC release reports/metrics.json + plan.csv),
#             handshake DV_SIGNOFF,metrics
#   collect   every DV exit of the phase's plan (project(phase_exits,DV))
#             released (RELEASE_COMPLETE), their sign-off reports
#   signoff   all those exits PASS, M4 targets met, every vPlan feature
#             closed or waived -> dv_signoff.rpt
#   release   DV_SIGNOFF_EXIT: the sign-off report + every milestone's
#             sign-off reports and metrics
# ═══════════════════════════════════════════════════════════════════════════════

# The generic review-gate flow's keys go; this overlay defines the flow.
foreach _s $dv_signoff(stages) {
    foreach _k [array names dv_signoff *,$_s] { unset dv_signoff($_k) }
    foreach _k [array names dv_signoff *,$_s,*] { unset dv_signoff($_k) }
}
foreach _k {stages optional_stages input_types mandatory_input_groups mandatory_user_inputs
            reporting_stages merge_entry_stage merge_handoff_stage merge_parallel_stages} {
    unset -nocomplain dv_signoff($_k)
}
foreach _k [array names dv_signoff release_types,*] { unset dv_signoff($_k) }

array set dv_signoff {
    tool,vendor   "opensource"
    tool,name     "verilator"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {metrics1 collect1 signoff1 release_data1}
    merge_entry_stage     metrics1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}
    mmmc,enabled          false

    dependencies,metrics1        {}
    dependencies,collect1        {metrics1}
    dependencies,signoff1        {collect1}
    dependencies,release_data1   {signoff1}

    input_types {metrics}
    mandatory_user_inputs { dv_signoff(input,metrics) }
    reporting_stages {signoff1 release_data1}
}
foreach _s {collect1 signoff1 release_data1} {
    set dv_signoff(subnodes,$_s) {setup run validate finish}
    set dv_signoff(subnode_dependencies,${_s},setup)    {}
    set dv_signoff(subnode_dependencies,${_s},run)      {setup}
    set dv_signoff(subnode_dependencies,${_s},validate) {run}
    set dv_signoff(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} { set dv_signoff(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}" }
}
foreach _s {metrics1} {
    set dv_signoff(stage_types,$_s) inputs; set dv_signoff(node_types,$_s) inputs; set dv_signoff(runtime,timeout,$_s) 10
}
array set dv_signoff {
    stage_types,collect1       "execution"
    node_types,collect1       "collect"
    runtime,timeout,collect1  10
    mandatory_outputs,collect1 {exits.json}
    stage_types,signoff1       "execution"
    node_types,signoff1       "signoff"
    runtime,timeout,signoff1  10
    mandatory_outputs,signoff1 {signoff.status}
    stage_types,release_data1  "release_data"
    node_types,release_data1  "release_data"
    runtime,timeout,release_data1 10
    mandatory_outputs,release_data1 {release.manifest}
}
unset -nocomplain _s _k _sub

array set dv_signoff {
    oss,tool,collect       "verilator"
    oss,tool,signoff       "verilator"
    oss,tool,release_data  "oss_tclsh"
}

set dv_signoff(smartgrid,milestone) "DV_SIGNOFF_EXIT"
set dv_signoff(checklist,exit_node,DV_SIGNOFF_EXIT) signoff1
set dv_signoff(checklist,report)                    {work/DV_SIGNOFF/signoff1/reports/dv_signoff.rpt}
set dv_signoff(checklist,report,dv_signoff_status)  {work/DV_SIGNOFF/signoff1/reports/dv_signoff.rpt}
set dv_signoff(checklist,mandatory_files,DV_SIGNOFF_EXIT) {work/DV_SIGNOFF/signoff1/reports/dv_signoff.rpt}
set dv_signoff(checklist,report,dv_closure_signoff)       {work/DV_SIGNOFF/signoff1/reports/dv_signoff.rpt}
set dv_signoff(checklist,report,release_manifest_present) {work/DV_SIGNOFF/release_data1/outputs/release.manifest}
