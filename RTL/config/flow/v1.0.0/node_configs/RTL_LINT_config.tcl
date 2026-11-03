#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║    RTL_LINT Flow Configuration — Static RTL lint checks                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Static lint over the design RTL — catches synthesizability issues, naming
# conventions, DFT-readiness, latches, race conditions, uninitialized regs,
# multi-driver nets, etc. First quality gate before synthesis/CDC/RDC.
#
# Supported tools:
#   · Synopsys Spyglass (default)
#   · Cadence Jaspergold / HAL
#
# Rule-deck selection comes from `rtl_lint(input,rule_deck)`. Waivers from
# `rtl_lint(input,waiver_file)`. Clean sign-off = zero fatal + zero error
# violations after waivers.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        STAGES & DEPENDENCIES                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    stages {rtl1 ruledeck1 waivers1
            init1 compile1 lint1 waiver_apply1 report1
            release_data1}

    dependencies,rtl1          {}
    dependencies,ruledeck1     {}
    dependencies,waivers1      {}
    dependencies,init1         {rtl1 ruledeck1}
    dependencies,compile1      {init1}
    dependencies,lint1         {compile1}
    dependencies,waiver_apply1 {lint1 waivers1}
    dependencies,report1       {waiver_apply1}
    dependencies,release_data1 {report1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set _lint_exec_stages {init1 compile1 lint1 waiver_apply1 report1 release_data1}
foreach _s $_lint_exec_stages {
    set rtl_lint(subnodes,$_s) {setup run validate finish}
    set rtl_lint(subnode_dependencies,${_s},setup)    {}
    set rtl_lint(subnode_dependencies,${_s},run)      {setup}
    set rtl_lint(subnode_dependencies,${_s},validate) {run}
    set rtl_lint(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set rtl_lint(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    stage_types,rtl1          "inputs"
    stage_types,ruledeck1     "inputs"
    stage_types,waivers1      "inputs"
    stage_types,init1         "execution"
    stage_types,compile1      "execution"
    stage_types,lint1         "execution"
    stage_types,waiver_apply1 "execution"
    stage_types,report1       "execution"
    stage_types,release_data1 "release_data"

    node_types,rtl1          "inputs"
    node_types,ruledeck1     "inputs"
    node_types,waivers1      "inputs"
    node_types,init1         "init"
    node_types,compile1      "compile"
    node_types,lint1         "lint"
    node_types,waiver_apply1 "waiver_apply"
    node_types,report1       "report"
    node_types,release_data1 "release_data"

    node_descriptions,rtl1          "RTL source filelist (Verilog/SystemVerilog)"
    node_descriptions,ruledeck1     "Lint goal / rule-deck file"
    node_descriptions,waivers1      "Lint waiver file (project-approved exemptions)"
    node_descriptions,init1         "Tool context + project file + top module setup"
    node_descriptions,compile1      "Analyze + elaborate RTL (catches syntax + hierarchy)"
    node_descriptions,lint1         "Run lint goal against the full design"
    node_descriptions,waiver_apply1 "Apply waiver file + classify remaining violations"
    node_descriptions,report1       "Generate lint summary + violations CSV + HTML"
    node_descriptions,release_data1 "Package lint deliverables for sign-off"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    mmmc,enabled            false

    runtime,timeout,rtl1          10
    runtime,timeout,ruledeck1     10
    runtime,timeout,waivers1      10
    runtime,timeout,init1         15
    runtime,timeout,compile1      30
    runtime,timeout,lint1         60
    runtime,timeout,waiver_apply1 15
    runtime,timeout,report1       15
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS                                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    critical_files,init1    {rtl_lint(input,rtl) rtl_lint(input,rule_deck)}
    critical_files,compile1 {rtl_lint(input,rtl)}
    critical_files,lint1    {rtl_lint(input,rule_deck)}

    mandatory_input_groups {
        rtl_inputs      {rtl_lint(input,rtl)}
        ruledeck_inputs {rtl_lint(input,rule_deck)}
        waiver_inputs   {rtl_lint(input,waiver_file)}
    }

    mandatory_user_inputs {
        rtl_lint(input,rtl)
        rtl_lint(input,rule_deck)
        rtl_lint(input,top_module)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        MANDATORY OUTPUTS                                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    mandatory_outputs,compile1 {
        reports/rtl_lint/compile.log
    }
    mandatory_outputs,lint1 {
        reports/rtl_lint/lint_summary.rpt
        reports/rtl_lint/violations_raw.csv
    }
    mandatory_outputs,waiver_apply1 {
        reports/rtl_lint/waivers_applied.rpt
        reports/rtl_lint/violations_waived.csv
    }
    mandatory_outputs,report1 {
        reports/rtl_lint/lint_signoff.rpt
        reports/rtl_lint/violations_final.csv
        reports/rtl_lint/violations_final.html
    }

    output,report_dir  "reports/rtl_lint"
    output,results_dir "results/rtl_lint"
    output,work_dir    "work/RTL_LINT"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set rtl_lint {
    release_types,rtl_lint,description "RTL lint sign-off deliverables"
    release_types,rtl_lint,files {
        "reports/rtl_lint/lint_signoff.rpt"       "reports/lint_signoff.rpt"
        "reports/rtl_lint/violations_final.csv"   "reports/violations_final.csv"
        "reports/rtl_lint/violations_final.html"  "reports/violations_final.html"
        "reports/rtl_lint/waivers_applied.rpt"    "reports/waivers_applied.rpt"
        "outputs/clean_rtl/${design_name}.v"      "netlist/${design_name}.v"
    }

    reporting_stages {report1 release_data1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        TOOL BINDING                                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set rtl_lint(supported_tools) {spyglass jaspergold}
set rtl_lint(default_tool)    "spyglass"

# Source the active tool's overlay (knobs + command invocation specifics).
# CBFLOW_TOOL_NAME env override wins; otherwise default_tool.
set _active_tool $rtl_lint(default_tool)
if {[info exists ::env(CBFLOW_TOOL_NAME)] && $::env(CBFLOW_TOOL_NAME) ne ""} {
    set _active_tool $::env(CBFLOW_TOOL_NAME)
}
set _tool_cfg [file join [file dirname [info script]] "RTL_LINT_${_active_tool}_config.tcl"]
if {[file exists $_tool_cfg]} {
    source $_tool_cfg
}
unset -nocomplain _tool_cfg _active_tool _lint_exec_stages _s _sub
