#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# M2_EXEC — Open-source tool configuration (vendor opensource, tool verilator)
# Sourced from M2_EXEC_config.tcl when m2_exec(tool,name) = verilator.
# Command files: DV/cmds/M2_EXEC/opensource/verilator/v1.0.0/
#
# Milestone M2 regression of the TB_SETUP testbench (UVM on Verilator):
#   inputs    tb (TB_SETUP release tb/tb.f), vplan — handshakes M2_EXEC,tb|vplan
#   compile   the testbench (Verilator --coverage, UVM)
#   regress   every vPlan test of the features up to M2 x m2_exec(oss,regress,seeds)
#             seeds, in parallel (DV/utils/oss/dv_tool.py regress)
#   cov_merge coverage of the passing runs merged: code coverage of the DUT
#             (line / branch / expr / toggle / FSM), functional coverage
#             (covergroup bins), vPlan closure per feature
#   triage    failing runs bucketed by first UVM_ERROR / UVM_FATAL
#   signoff   pass rate / code coverage / vPlan coverage against the project's
#             M2 targets — project(dv,targets,M2) (DV project overlay)
#   release   M2_EXIT: reports (regression, coverage, vPlan status, triage,
#             metrics.json), merged coverage database
# ═══════════════════════════════════════════════════════════════════════════════

# The generic review-gate flow's keys go; this overlay defines the flow.
foreach _s $m2_exec(stages) {
    foreach _k [array names m2_exec *,$_s] { unset m2_exec($_k) }
    foreach _k [array names m2_exec *,$_s,*] { unset m2_exec($_k) }
}
foreach _k {stages optional_stages input_types mandatory_input_groups mandatory_user_inputs
            reporting_stages merge_entry_stage merge_handoff_stage merge_parallel_stages} {
    unset -nocomplain m2_exec($_k)
}
foreach _k [array names m2_exec release_types,*] { unset m2_exec($_k) }

array set m2_exec {
    tool,vendor   "opensource"
    tool,name     "verilator"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {tb1 vplan1 compile1 regress1 cov_merge1 triage1 signoff1 release_data1}
    merge_entry_stage     tb1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}
    mmmc,enabled          false

    dependencies,tb1             {}
    dependencies,vplan1          {}
    dependencies,compile1        {tb1 vplan1}
    dependencies,regress1        {compile1}
    dependencies,cov_merge1      {regress1}
    dependencies,triage1         {cov_merge1}
    dependencies,signoff1        {triage1}
    dependencies,release_data1   {signoff1}

    input_types {tb vplan}
    mandatory_user_inputs { m2_exec(input,tb) m2_exec(input,vplan) }
    reporting_stages {signoff1 release_data1}
}
foreach _s {compile1 regress1 cov_merge1 triage1 signoff1 release_data1} {
    set m2_exec(subnodes,$_s) {setup run validate finish}
    set m2_exec(subnode_dependencies,${_s},setup)    {}
    set m2_exec(subnode_dependencies,${_s},run)      {setup}
    set m2_exec(subnode_dependencies,${_s},validate) {run}
    set m2_exec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} { set m2_exec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}" }
}
foreach _s {tb1 vplan1} {
    set m2_exec(stage_types,$_s) inputs; set m2_exec(node_types,$_s) inputs; set m2_exec(runtime,timeout,$_s) 10
}
array set m2_exec {
    stage_types,compile1       "execution"
    node_types,compile1       "compile"
    runtime,timeout,compile1  60
    mandatory_outputs,compile1 {sim}
    stage_types,regress1       "execution"
    node_types,regress1       "regress"
    runtime,timeout,regress1  240
    mandatory_outputs,regress1 {results.csv}
    stage_types,cov_merge1     "execution"
    node_types,cov_merge1     "cov_merge"
    runtime,timeout,cov_merge1 30
    mandatory_outputs,cov_merge1 {metrics.json}
    stage_types,triage1        "execution"
    node_types,triage1        "triage"
    runtime,timeout,triage1   10
    mandatory_outputs,triage1 {triage.status}
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
# triage runs beside the coverage merge; sign-off needs both
set m2_exec(dependencies,triage1)  {regress1}
set m2_exec(dependencies,signoff1) {cov_merge1 triage1}

array set m2_exec {
    oss,tool,compile       "verilator"
    oss,tool,regress       "verilator"
    oss,tool,cov_merge     "verilator"
    oss,tool,triage        "verilator"
    oss,tool,signoff       "verilator"
    oss,tool,release_data  "oss_tclsh"
}

# oss,milestone: the vPlan milestone this flow closes; oss,regress,seeds /
# jobs; oss,sim,timeout_s per run; oss,verilator,flags / jobs: the build.
array set m2_exec {
    oss,milestone            "M2"
    oss,regress,seeds        5
    oss,regress,jobs         8
    oss,sim,timeout_s        1800
    oss,verilator,flags      {-Wno-fatal -Wno-lint -Wno-style}
    oss,verilator,jobs       8
}

set m2_exec(smartgrid,milestone) "M2_EXIT"
set m2_exec(checklist,exit_node,M2_EXIT) signoff1
set m2_exec(checklist,report)                       {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,m2_review_signoff) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,dv_signoff_status)     {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,dv_pass_rate) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,dv_code_coverage) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,dv_functional_coverage) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,report,dv_plan_coverage) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt}
set m2_exec(checklist,mandatory_files,M2_EXIT) {work/M2_EXEC/signoff1/reports/dv_signoff.rpt
    work/M2_EXEC/cov_merge1/reports/coverage.rpt}
