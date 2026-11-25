#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# TB_SETUP — Open-source tool configuration (vendor opensource, tool verilator)
# Sourced from TB_SETUP_config.tcl when tb_setup(tool,name) = verilator.
# Command files: DV/cmds/TB_SETUP/opensource/verilator/v1.0.0/
#
# SystemVerilog UVM testbench built from the block spec (uvmgen) and run:
#   inputs    spec (<d>.spec.yaml), ral (UVM register model), vplan, rtl (<d>.f)
#             — RTL_SPEC / RTL_LINT releases by tag (handshakes TB_SETUP,*)
#   tb_gen    DV/utils/oss/uvmgen.py: interfaces, agents (valid_ready, APB4 +
#             RAL adapter), scoreboard, env, sequences, base + sanity tests,
#             stubs for unwritten vPlan tests; the user-owned files of
#             tb_setup(oss,tb_dir) (reference model, coverage, tests) replace
#             the generated ones; memory models from the library tag
#   compile   Verilator --binary --timing --coverage with UVM (UVM_HOME)
#   sanity    <d>_sanity_test x tb_setup(oss,sanity,seeds) — all must pass
#   release   TB_SETUP_EXIT: tb/ (every TB file + tb.f at the released paths),
#             spec/<d>_vplan.xlsx, reports — what M1-M4_EXEC compile and run
# The human gate is the exit checklist sign-off (cbflow flow checklist sign-off).
# ═══════════════════════════════════════════════════════════════════════════════

# The generic review-gate flow's keys go; this overlay defines the flow.
foreach _s $tb_setup(stages) {
    foreach _k [array names tb_setup *,$_s] { unset tb_setup($_k) }
    foreach _k [array names tb_setup *,$_s,*] { unset tb_setup($_k) }
}
foreach _k {stages optional_stages input_types mandatory_input_groups mandatory_user_inputs
            reporting_stages merge_entry_stage merge_handoff_stage merge_parallel_stages} {
    unset -nocomplain tb_setup($_k)
}
foreach _k [array names tb_setup release_types,*] { unset tb_setup($_k) }

array set tb_setup {
    tool,vendor   "opensource"
    tool,name     "verilator"
    tool,version  "v1.0.0"
    tool,args     ""

    stages {spec1 ral1 vplan1 rtl1 tb_gen1 compile1 sanity1 release_data1}
    merge_entry_stage     spec1
    merge_handoff_stage   release_data1
    merge_parallel_stages {}
    mmmc,enabled          false

    dependencies,spec1           {}
    dependencies,ral1            {}
    dependencies,vplan1          {}
    dependencies,rtl1            {}
    dependencies,tb_gen1         {spec1 ral1 vplan1 rtl1}
    dependencies,compile1        {tb_gen1}
    dependencies,sanity1         {compile1}
    dependencies,release_data1   {sanity1}

    input_types {spec ral vplan rtl}
    mandatory_user_inputs { tb_setup(input,spec) tb_setup(input,ral) tb_setup(input,vplan) tb_setup(input,rtl) }
    reporting_stages {sanity1 release_data1}
}
foreach _s {tb_gen1 compile1 sanity1 release_data1} {
    set tb_setup(subnodes,$_s) {setup run validate finish}
    set tb_setup(subnode_dependencies,${_s},setup)    {}
    set tb_setup(subnode_dependencies,${_s},run)      {setup}
    set tb_setup(subnode_dependencies,${_s},validate) {run}
    set tb_setup(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} { set tb_setup(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}" }
}
foreach _s {spec1 ral1 vplan1 rtl1} {
    set tb_setup(stage_types,$_s) inputs; set tb_setup(node_types,$_s) inputs; set tb_setup(runtime,timeout,$_s) 10
}
array set tb_setup {
    stage_types,tb_gen1        "execution"
    node_types,tb_gen1        "tb_gen"
    runtime,timeout,tb_gen1   15
    mandatory_outputs,tb_gen1 {tb/tb.f tb_gen.status}
    stage_types,compile1       "execution"
    node_types,compile1       "compile"
    runtime,timeout,compile1  60
    mandatory_outputs,compile1 {sim}
    stage_types,sanity1        "execution"
    node_types,sanity1        "sanity"
    runtime,timeout,sanity1   60
    mandatory_outputs,sanity1 {sanity.status}
    stage_types,release_data1  "release_data"
    node_types,release_data1  "release_data"
    runtime,timeout,release_data1 10
    mandatory_outputs,release_data1 {release.manifest}
}
unset -nocomplain _s _k _sub

array set tb_setup {
    oss,tool,tb_gen        "verilator"
    oss,tool,compile       "verilator"
    oss,tool,sanity        "verilator"
    oss,tool,release_data  "oss_tclsh"
}

# ┌─ Testbench ────────────────────────────────────────────────────────────────┐
# oss,tb_dir: user-owned TB files ("" = generated stubs only — outputs are
# then not checked and the vPlan tests fail as TEST-TODO); oss,verilator,flags /
# jobs: the testbench build; oss,sanity,seeds; oss,sim,timeout_s: per run.
array set tb_setup {
    oss,tb_dir               ""
    oss,verilator,flags      {-Wno-fatal -Wno-lint -Wno-style}
    oss,verilator,jobs       8
    oss,sanity,seeds         2
    oss,sim,timeout_s        1800
}

set tb_setup(smartgrid,milestone) "TB_SETUP_EXIT"
set tb_setup(checklist,exit_node,TB_SETUP_EXIT) sanity1
set tb_setup(checklist,report)                       {work/TB_SETUP/sanity1/reports/sanity.rpt}
set tb_setup(checklist,report,dv_signoff_status)     {work/TB_SETUP/sanity1/reports/sanity.rpt}
set tb_setup(checklist,metric,dv_pass_rate)          {Pass rate\s*:\s*([\d.]+)}
set tb_setup(checklist,mandatory_files,TB_SETUP_EXIT) {work/TB_SETUP/sanity1/reports/sanity.rpt
    work/TB_SETUP/tb_gen1/reports/tb_gen.rpt}
set tb_setup(checklist,report,tb_sanity_signoff) {work/TB_SETUP/sanity1/reports/sanity.rpt}
