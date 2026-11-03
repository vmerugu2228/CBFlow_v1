#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    UPF_CHECK Flow Configuration — Static UPF intent check                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Static UPF (IEEE-1801 Unified Power Format) check on RTL + UPF intent.
# Catches power-intent errors before synthesis + implementation: unknown
# supply ports, missing isolation on crossings, retention conflicts, bad
# power switch wiring, unresolved power states.
#
# Complementary to PD's CLP (which runs post-synth on gate-level netlist).
# This flow runs on the RTL + UPF pair as the first low-power gate.
#
# Supported tools:
#   · Synopsys VC-LP (default)
#   · Cadence Conformal LP

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    stages {rtl1 upf1 waivers1
            init1 compile1 upf_parse1 upf_check1 upf_report1 waiver_apply1 signoff1
            release_data1}

    dependencies,rtl1          {}
    dependencies,upf1          {}
    dependencies,waivers1      {}
    dependencies,init1         {rtl1 upf1}
    dependencies,compile1      {init1}
    dependencies,upf_parse1    {compile1}
    dependencies,upf_check1    {upf_parse1}
    dependencies,upf_report1   {upf_check1}
    dependencies,waiver_apply1 {upf_report1 waivers1}
    dependencies,signoff1      {waiver_apply1}
    dependencies,release_data1 {signoff1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _upf_exec_stages {init1 compile1 upf_parse1 upf_check1 upf_report1 waiver_apply1 signoff1 release_data1}
foreach _s $_upf_exec_stages {
    set upf_check(subnodes,$_s) {setup run validate finish}
    set upf_check(subnode_dependencies,${_s},setup)    {}
    set upf_check(subnode_dependencies,${_s},run)      {setup}
    set upf_check(subnode_dependencies,${_s},validate) {run}
    set upf_check(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set upf_check(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    stage_types,rtl1          "inputs"
    stage_types,upf1          "inputs"
    stage_types,waivers1      "inputs"
    stage_types,init1         "execution"
    stage_types,compile1      "execution"
    stage_types,upf_parse1    "execution"
    stage_types,upf_check1    "execution"
    stage_types,upf_report1   "execution"
    stage_types,waiver_apply1 "execution"
    stage_types,signoff1      "execution"
    stage_types,release_data1 "release_data"

    node_types,rtl1          "inputs"
    node_types,upf1          "inputs"
    node_types,waivers1      "inputs"
    node_types,init1         "init"
    node_types,compile1      "compile"
    node_types,upf_parse1    "upf_parse"
    node_types,upf_check1    "upf_check"
    node_types,upf_report1   "upf_report"
    node_types,waiver_apply1 "waiver_apply"
    node_types,signoff1      "signoff"
    node_types,release_data1 "release_data"

    node_descriptions,rtl1          "RTL source filelist"
    node_descriptions,upf1          "UPF intent file (IEEE-1801)"
    node_descriptions,waivers1      "UPF-check waiver file"
    node_descriptions,init1         "Tool context + project file setup"
    node_descriptions,compile1      "Analyze + elaborate RTL"
    node_descriptions,upf_parse1    "Load + parse UPF file; build power intent"
    node_descriptions,upf_check1    "Run static UPF intent check"
    node_descriptions,upf_report1   "Generate violations + power domain reports"
    node_descriptions,waiver_apply1 "Apply waiver file"
    node_descriptions,signoff1      "Sign-off summary"
    node_descriptions,release_data1 "Package UPF-check deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    mmmc,enabled            false

    runtime,timeout,rtl1          10
    runtime,timeout,upf1          10
    runtime,timeout,waivers1      10
    runtime,timeout,init1         15
    runtime,timeout,compile1      30
    runtime,timeout,upf_parse1    20
    runtime,timeout,upf_check1    60
    runtime,timeout,upf_report1   30
    runtime,timeout,waiver_apply1 15
    runtime,timeout,signoff1      15
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    critical_files,init1      {upf_check(input,rtl) upf_check(input,upf)}
    critical_files,upf_parse1 {upf_check(input,upf)}

    mandatory_input_groups {
        rtl_inputs    {upf_check(input,rtl)}
        upf_inputs    {upf_check(input,upf)}
        waiver_inputs {upf_check(input,waiver_file)}
    }

    mandatory_user_inputs {
        upf_check(input,rtl)
        upf_check(input,upf)
        upf_check(input,top_module)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    mandatory_outputs,compile1 {
        reports/upf_check/compile.log
    }
    mandatory_outputs,upf_parse1 {
        reports/upf_check/upf_parse.log
    }
    mandatory_outputs,upf_check1 {
        reports/upf_check/upf_check_summary.rpt
        reports/upf_check/upf_violations.csv
    }
    mandatory_outputs,upf_report1 {
        reports/upf_check/power_domains.rpt
        reports/upf_check/power_states.rpt
    }
    mandatory_outputs,waiver_apply1 {
        reports/upf_check/waivers_applied.rpt
    }
    mandatory_outputs,signoff1 {
        reports/upf_check/upf_signoff.rpt
        reports/upf_check/violations_final.csv
    }

    output,report_dir  "reports/upf_check"
    output,results_dir "results/upf_check"
    output,work_dir    "work/UPF_CHECK"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set upf_check {
    release_types,upf_check,description "UPF static-check sign-off deliverables"
    release_types,upf_check,files {
        "reports/upf_check/upf_signoff.rpt"      "reports/upf_signoff.rpt"
        "reports/upf_check/violations_final.csv" "reports/violations_final.csv"
        "reports/upf_check/power_domains.rpt"    "reports/power_domains.rpt"
        "reports/upf_check/power_states.rpt"     "reports/power_states.rpt"
        "reports/upf_check/waivers_applied.rpt"  "reports/waivers_applied.rpt"
        "outputs/validated/${design_name}.upf"   "upf/${design_name}.upf"
    }

    reporting_stages {upf_report1 signoff1 release_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        TOOL BINDING                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set upf_check(supported_tools) {vc_lp conformal_lp}
set upf_check(default_tool)    "vc_lp"

set _active_tool $upf_check(default_tool)
if {[info exists ::env(CBFLOW_TOOL_NAME)] && $::env(CBFLOW_TOOL_NAME) ne ""} {
    set _active_tool $::env(CBFLOW_TOOL_NAME)
}
set _tool_cfg [file join [file dirname [info script]] "UPF_CHECK_${_active_tool}_config.tcl"]
if {[file exists $_tool_cfg]} {
    source $_tool_cfg
}
unset -nocomplain _tool_cfg _active_tool _upf_exec_stages _s _sub
