#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    RTL_RDC Flow Configuration — Reset Domain Crossing analysis              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Static RDC analysis — flags unsynchronized paths crossing async reset
# domains. Prevents soft-reset glitches on registers downstream of
# asynchronous resets. Required gate for designs with multiple reset trees.
#
# Supported tools:
#   · Synopsys Spyglass RDC (default)
#   · Cadence Jaspergold RDC

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    stages {rtl1 sdc1 reset_scheme1 waivers1
            init1 compile1 rdc_setup1 rdc_analyze1 rdc_report1 waiver_apply1 signoff1
            release_data1}

    dependencies,rtl1          {}
    dependencies,sdc1          {}
    dependencies,reset_scheme1 {}
    dependencies,waivers1      {}
    dependencies,init1         {rtl1 sdc1 reset_scheme1}
    dependencies,compile1      {init1}
    dependencies,rdc_setup1    {compile1}
    dependencies,rdc_analyze1  {rdc_setup1}
    dependencies,rdc_report1   {rdc_analyze1}
    dependencies,waiver_apply1 {rdc_report1 waivers1}
    dependencies,signoff1      {waiver_apply1}
    dependencies,release_data1 {signoff1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _rdc_exec_stages {init1 compile1 rdc_setup1 rdc_analyze1 rdc_report1 waiver_apply1 signoff1 release_data1}
foreach _s $_rdc_exec_stages {
    set rtl_rdc(subnodes,$_s) {setup run validate finish}
    set rtl_rdc(subnode_dependencies,${_s},setup)    {}
    set rtl_rdc(subnode_dependencies,${_s},run)      {setup}
    set rtl_rdc(subnode_dependencies,${_s},validate) {run}
    set rtl_rdc(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set rtl_rdc(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    stage_types,rtl1          "inputs"
    stage_types,sdc1          "inputs"
    stage_types,reset_scheme1 "inputs"
    stage_types,waivers1      "inputs"
    stage_types,init1         "execution"
    stage_types,compile1      "execution"
    stage_types,rdc_setup1    "execution"
    stage_types,rdc_analyze1  "execution"
    stage_types,rdc_report1   "execution"
    stage_types,waiver_apply1 "execution"
    stage_types,signoff1      "execution"
    stage_types,release_data1 "release_data"

    node_types,rtl1          "inputs"
    node_types,sdc1          "inputs"
    node_types,reset_scheme1 "inputs"
    node_types,waivers1      "inputs"
    node_types,init1         "init"
    node_types,compile1      "compile"
    node_types,rdc_setup1    "rdc_setup"
    node_types,rdc_analyze1  "rdc_analyze"
    node_types,rdc_report1   "rdc_report"
    node_types,waiver_apply1 "waiver_apply"
    node_types,signoff1      "signoff"
    node_types,release_data1 "release_data"

    node_descriptions,rtl1          "RTL source filelist"
    node_descriptions,sdc1          "SDC with create_clock"
    node_descriptions,reset_scheme1 "Reset scheme file — async/sync reset tree declarations"
    node_descriptions,waivers1      "RDC waiver file (project-approved exemptions)"
    node_descriptions,init1         "Tool context + project file + top module setup"
    node_descriptions,compile1      "Analyze + elaborate RTL"
    node_descriptions,rdc_setup1    "Load reset scheme; declare async reset groups"
    node_descriptions,rdc_analyze1  "Run structural + functional RDC analysis"
    node_descriptions,rdc_report1   "Generate violations + reset tree reports"
    node_descriptions,waiver_apply1 "Apply waiver file + classify remaining"
    node_descriptions,signoff1      "Sign-off summary"
    node_descriptions,release_data1 "Package RDC deliverables"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    mmmc,enabled            false

    runtime,timeout,rtl1          10
    runtime,timeout,sdc1          10
    runtime,timeout,reset_scheme1 10
    runtime,timeout,waivers1      10
    runtime,timeout,init1         15
    runtime,timeout,compile1      30
    runtime,timeout,rdc_setup1    20
    runtime,timeout,rdc_analyze1  120
    runtime,timeout,rdc_report1   30
    runtime,timeout,waiver_apply1 15
    runtime,timeout,signoff1      15
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    critical_files,init1        {rtl_rdc(input,rtl) rtl_rdc(input,sdc) rtl_rdc(input,reset_scheme_file)}
    critical_files,compile1     {rtl_rdc(input,rtl)}
    critical_files,rdc_setup1   {rtl_rdc(input,reset_scheme_file)}

    mandatory_input_groups {
        rtl_inputs           {rtl_rdc(input,rtl)}
        sdc_inputs           {rtl_rdc(input,sdc)}
        reset_scheme_inputs  {rtl_rdc(input,reset_scheme_file)}
        waiver_inputs        {rtl_rdc(input,waiver_file)}
    }

    mandatory_user_inputs {
        rtl_rdc(input,rtl)
        rtl_rdc(input,sdc)
        rtl_rdc(input,reset_scheme_file)
        rtl_rdc(input,top_module)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    mandatory_outputs,compile1 {
        reports/rtl_rdc/compile.log
    }
    mandatory_outputs,rdc_analyze1 {
        reports/rtl_rdc/rdc_summary.rpt
        reports/rtl_rdc/rdc_violations.csv
    }
    mandatory_outputs,rdc_report1 {
        reports/rtl_rdc/reset_tree.rpt
    }
    mandatory_outputs,waiver_apply1 {
        reports/rtl_rdc/waivers_applied.rpt
    }
    mandatory_outputs,signoff1 {
        reports/rtl_rdc/rdc_signoff.rpt
        reports/rtl_rdc/violations_final.csv
    }

    output,report_dir  "reports/rtl_rdc"
    output,results_dir "results/rtl_rdc"
    output,work_dir    "work/RTL_RDC"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_rdc {
    release_types,rtl_rdc,description "RTL RDC sign-off deliverables"
    release_types,rtl_rdc,files {
        "reports/rtl_rdc/rdc_signoff.rpt"       "reports/rdc_signoff.rpt"
        "reports/rtl_rdc/violations_final.csv"  "reports/violations_final.csv"
        "reports/rtl_rdc/reset_tree.rpt"        "reports/reset_tree.rpt"
        "reports/rtl_rdc/waivers_applied.rpt"   "reports/waivers_applied.rpt"
    }

    reporting_stages {rdc_report1 signoff1 release_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        TOOL BINDING                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set rtl_rdc(supported_tools) {spyglass jaspergold}
set rtl_rdc(default_tool)    "spyglass"

set _active_tool $rtl_rdc(default_tool)
if {[info exists ::env(CBFLOW_TOOL_NAME)] && $::env(CBFLOW_TOOL_NAME) ne ""} {
    set _active_tool $::env(CBFLOW_TOOL_NAME)
}
set _tool_cfg [file join [file dirname [info script]] "RTL_RDC_${_active_tool}_config.tcl"]
if {[file exists $_tool_cfg]} {
    source $_tool_cfg
}
unset -nocomplain _tool_cfg _active_tool _rdc_exec_stages _s _sub
