#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    RTL_CDC Flow Configuration — Clock Domain Crossing analysis              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Static CDC analysis — flags unsynchronized paths crossing async clock
# domains. Catches metastability + glitch risks before silicon. Required
# gate for any multi-clock design.
#
# Supported tools:
#   · Synopsys Spyglass CDC (default)
#   · Cadence Jaspergold CDC
#
# Needs SDC + clock-domain declarations. Scheme file (`rtl_cdc(input,scheme_file)`)
# tells the tool which clocks are async vs synchronous. Waivers come from
# `rtl_cdc(input,waiver_file)`.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    stages {rtl1 sdc1 scheme1 waivers1
            init1 compile1 cdc_setup1 cdc_analyze1 cdc_report1 waiver_apply1 signoff1
            release_data1}

    dependencies,rtl1          {}
    dependencies,sdc1          {}
    dependencies,scheme1       {}
    dependencies,waivers1      {}
    dependencies,init1         {rtl1 sdc1 scheme1}
    dependencies,compile1      {init1}
    dependencies,cdc_setup1    {compile1}
    dependencies,cdc_analyze1  {cdc_setup1}
    dependencies,cdc_report1   {cdc_analyze1}
    dependencies,waiver_apply1 {cdc_report1 waivers1}
    dependencies,signoff1      {waiver_apply1}
    dependencies,release_data1 {signoff1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _cdc_exec_stages {init1 compile1 cdc_setup1 cdc_analyze1 cdc_report1 waiver_apply1 signoff1 release_data1}
foreach _s $_cdc_exec_stages {
    set rtl_cdc(subnodes,$_s) {setup run validate finish}
    set rtl_cdc(subnode_dependencies,${_s},setup)    {}
    set rtl_cdc(subnode_dependencies,${_s},run)      {setup}
    set rtl_cdc(subnode_dependencies,${_s},validate) {run}
    set rtl_cdc(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set rtl_cdc(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    stage_types,rtl1          "inputs"
    stage_types,sdc1          "inputs"
    stage_types,scheme1       "inputs"
    stage_types,waivers1      "inputs"
    stage_types,init1         "execution"
    stage_types,compile1      "execution"
    stage_types,cdc_setup1    "execution"
    stage_types,cdc_analyze1  "execution"
    stage_types,cdc_report1   "execution"
    stage_types,waiver_apply1 "execution"
    stage_types,signoff1      "execution"
    stage_types,release_data1 "release_data"

    node_types,rtl1          "inputs"
    node_types,sdc1          "inputs"
    node_types,scheme1       "inputs"
    node_types,waivers1      "inputs"
    node_types,init1         "init"
    node_types,compile1      "compile"
    node_types,cdc_setup1    "cdc_setup"
    node_types,cdc_analyze1  "cdc_analyze"
    node_types,cdc_report1   "cdc_report"
    node_types,waiver_apply1 "waiver_apply"
    node_types,signoff1      "signoff"
    node_types,release_data1 "release_data"

    node_descriptions,rtl1          "RTL source filelist"
    node_descriptions,sdc1          "SDC with create_clock + create_generated_clock"
    node_descriptions,scheme1       "CDC scheme file — clock-domain + reset-domain declarations"
    node_descriptions,waivers1      "CDC waiver file (project-approved exemptions)"
    node_descriptions,init1         "Tool context + project file + top module setup"
    node_descriptions,compile1      "Analyze + elaborate RTL"
    node_descriptions,cdc_setup1    "Load SDC + scheme file; declare async groups"
    node_descriptions,cdc_analyze1  "Run structural + functional CDC analysis"
    node_descriptions,cdc_report1   "Generate violations CSV + path report"
    node_descriptions,waiver_apply1 "Apply waiver file + classify remaining violations"
    node_descriptions,signoff1      "Sign-off summary — fatal/error/warning counts post-waiver"
    node_descriptions,release_data1 "Package CDC deliverables for sign-off"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    mmmc,enabled            false

    runtime,timeout,rtl1          10
    runtime,timeout,sdc1          10
    runtime,timeout,scheme1       10
    runtime,timeout,waivers1      10
    runtime,timeout,init1         15
    runtime,timeout,compile1      30
    runtime,timeout,cdc_setup1    20
    runtime,timeout,cdc_analyze1  120
    runtime,timeout,cdc_report1   30
    runtime,timeout,waiver_apply1 15
    runtime,timeout,signoff1      15
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    critical_files,init1        {rtl_cdc(input,rtl) rtl_cdc(input,sdc) rtl_cdc(input,scheme_file)}
    critical_files,compile1     {rtl_cdc(input,rtl)}
    critical_files,cdc_setup1   {rtl_cdc(input,sdc) rtl_cdc(input,scheme_file)}

    mandatory_input_groups {
        rtl_inputs     {rtl_cdc(input,rtl)}
        sdc_inputs     {rtl_cdc(input,sdc)}
        scheme_inputs  {rtl_cdc(input,scheme_file)}
        waiver_inputs  {rtl_cdc(input,waiver_file)}
    }

    mandatory_user_inputs {
        rtl_cdc(input,rtl)
        rtl_cdc(input,sdc)
        rtl_cdc(input,scheme_file)
        rtl_cdc(input,top_module)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    mandatory_outputs,compile1 {
        reports/rtl_cdc/compile.log
    }
    mandatory_outputs,cdc_analyze1 {
        reports/rtl_cdc/cdc_summary.rpt
        reports/rtl_cdc/cdc_violations.csv
    }
    mandatory_outputs,cdc_report1 {
        reports/rtl_cdc/cdc_paths.rpt
        reports/rtl_cdc/clock_summary.rpt
    }
    mandatory_outputs,waiver_apply1 {
        reports/rtl_cdc/waivers_applied.rpt
    }
    mandatory_outputs,signoff1 {
        reports/rtl_cdc/cdc_signoff.rpt
        reports/rtl_cdc/violations_final.csv
    }

    output,report_dir  "reports/rtl_cdc"
    output,results_dir "results/rtl_cdc"
    output,work_dir    "work/RTL_CDC"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_cdc {
    release_types,rtl_cdc,description "RTL CDC sign-off deliverables"
    release_types,rtl_cdc,files {
        "reports/rtl_cdc/cdc_signoff.rpt"       "reports/cdc_signoff.rpt"
        "reports/rtl_cdc/violations_final.csv"  "reports/violations_final.csv"
        "reports/rtl_cdc/cdc_paths.rpt"         "reports/cdc_paths.rpt"
        "reports/rtl_cdc/clock_summary.rpt"     "reports/clock_summary.rpt"
        "reports/rtl_cdc/waivers_applied.rpt"   "reports/waivers_applied.rpt"
    }

    reporting_stages {cdc_report1 signoff1 release_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        TOOL BINDING                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set rtl_cdc(supported_tools) {spyglass jaspergold}
set rtl_cdc(default_tool)    "spyglass"

set _active_tool $rtl_cdc(default_tool)
if {[info exists ::env(CBFLOW_TOOL_NAME)] && $::env(CBFLOW_TOOL_NAME) ne ""} {
    set _active_tool $::env(CBFLOW_TOOL_NAME)
}
set _tool_cfg [file join [file dirname [info script]] "RTL_CDC_${_active_tool}_config.tcl"]
if {[file exists $_tool_cfg]} {
    source $_tool_cfg
}
unset -nocomplain _tool_cfg _active_tool _cdc_exec_stages _s _sub
