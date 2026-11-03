#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  RTL_LINT — Synopsys Spyglass tool overlay                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Spyglass goals: lint, lint/lint_rtl_enhanced, lint/lint_rtl, lint/lint_abstract.
# Default here is lint/lint_rtl_enhanced — the industry-standard pre-synth lint.
# Projects can override via `rtl_lint(spyglass,goal)` in user_config.

# Report-level filters. Projects can tune these in user_config via
# the standard override path: rtl_lint(spyglass,severity_filter) ...
# NB: no `#` comments inside the `array set { ... }` block — TCL treats
# them as list elements, not comments.
array set rtl_lint {
    tool,vendor          "synopsys"
    tool,name            "spyglass"
    tool,version         "v1.0.0"
    tool,executable      "spyglass"
    tool,args            "-shell -tcl"

    spyglass,goal              "lint/lint_rtl_enhanced"
    spyglass,parallel          "true"
    spyglass,parallel_cores    4
    spyglass,enable_elaborate  "true"
    spyglass,enable_sdc_check  "false"
    spyglass,abort_on_fatal    "true"
    spyglass,abort_on_error    "false"
    spyglass,waiver_mode       "project"
    spyglass,policy_file       ""
    spyglass,methodology       "spyglass_builtin"
    spyglass,severity_filter   {Fatal ERROR Warning Info}
    spyglass,output_format     "csv_html"
}

# Scripts (relative to this discipline's cmds/<FLOW>/synopsys/spyglass/<ver>/).
# Keep this scaffolded — handler files land as separate commits.
array set rtl_lint {
    cmd_files,init1          "init_spyglass.tcl"
    cmd_files,compile1       "compile_spyglass.tcl"
    cmd_files,lint1          "lint_spyglass.tcl"
    cmd_files,waiver_apply1  "waiver_apply_spyglass.tcl"
    cmd_files,report1        "report_spyglass.tcl"
    cmd_files,release_data1  "release_data_spyglass.tcl"
}
