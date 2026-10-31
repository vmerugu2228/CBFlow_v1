#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — M1_EXEC Flow Configuration
# Test plan execution — Milestone 1 (0.3v RTL)
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set m1_exec(skip_stages) {}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set m1_exec {
    stages {review_artifact1 m1_test_review1 log_scoreboard_check1 waveform_check1 coverage_assertions_review1 bug_tracking1 regression_gatekeeper1 export_db1 release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,m1_test_review1                     {review_artifact1}
    dependencies,log_scoreboard_check1               {m1_test_review1}
    dependencies,waveform_check1                     {log_scoreboard_check1}
    dependencies,coverage_assertions_review1         {waveform_check1}
    dependencies,bug_tracking1                       {coverage_assertions_review1}
    dependencies,regression_gatekeeper1              {bug_tracking1}
    dependencies,export_db1                          {regression_gatekeeper1}
    dependencies,release_data1                       {export_db1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _m1_exec_exec_stages {m1_test_review1 log_scoreboard_check1 waveform_check1 coverage_assertions_review1 bug_tracking1 regression_gatekeeper1 export_db1 release_data1}
foreach _s $_m1_exec_exec_stages {
    set m1_exec(subnodes,$_s) {setup run validate finish}
    set m1_exec(subnode_dependencies,${_s},setup)    {}
    set m1_exec(subnode_dependencies,${_s},run)      {setup}
    set m1_exec(subnode_dependencies,${_s},validate) {run}
    set m1_exec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set m1_exec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m1_exec {
    stage_types,review_artifact1 "inputs"
    stage_types,m1_test_review1                     "review"
    stage_types,log_scoreboard_check1               "review"
    stage_types,waveform_check1                     "review"
    stage_types,coverage_assertions_review1         "review"
    stage_types,bug_tracking1                       "review"
    stage_types,regression_gatekeeper1              "review"
    stage_types,export_db1                          "review"
    stage_types,release_data1 "release"

    node_types,review_artifact1 "inputs"
    node_types,m1_test_review1                     "review"
    node_types,log_scoreboard_check1               "review"
    node_types,waveform_check1                     "review"
    node_types,coverage_assertions_review1         "review"
    node_types,bug_tracking1                       "review"
    node_types,regression_gatekeeper1              "review"
    node_types,export_db1                          "review"
    node_types,release_data1  "release_data"

    node_descriptions,review_artifact1 "Review-artifact input collection"
    node_descriptions,m1_test_review1                     "M1 Test Review1 review gate (artifact-attach + signoff)"
    node_descriptions,log_scoreboard_check1               "Log Scoreboard Check1 review gate (artifact-attach + signoff)"
    node_descriptions,waveform_check1                     "Waveform Check1 review gate (artifact-attach + signoff)"
    node_descriptions,coverage_assertions_review1         "Coverage Assertions Review1 review gate (artifact-attach + signoff)"
    node_descriptions,bug_tracking1                       "Bug Tracking1 review gate (artifact-attach + signoff)"
    node_descriptions,regression_gatekeeper1              "Regression Gatekeeper1 review gate (artifact-attach + signoff)"
    node_descriptions,export_db1                          "Export Db1 review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m1_exec {
    runtime,timeout,review_artifact1 10
    runtime,timeout,m1_test_review1                     30
    runtime,timeout,log_scoreboard_check1               30
    runtime,timeout,waveform_check1                     30
    runtime,timeout,coverage_assertions_review1         30
    runtime,timeout,bug_tracking1                       30
    runtime,timeout,regression_gatekeeper1              30
    runtime,timeout,export_db1                          30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set m1_exec(input,review_artifact) <path>.
array set m1_exec {
    mandatory_outputs,m1_test_review1                     {outputs/review_signoff.txt}
    mandatory_outputs,log_scoreboard_check1               {outputs/review_signoff.txt}
    mandatory_outputs,waveform_check1                     {outputs/review_signoff.txt}
    mandatory_outputs,coverage_assertions_review1         {outputs/review_signoff.txt}
    mandatory_outputs,bug_tracking1                       {outputs/review_signoff.txt}
    mandatory_outputs,regression_gatekeeper1              {outputs/review_signoff.txt}
    mandatory_outputs,export_db1                          {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { m1_exec(input,review_artifact) }
    }
    mandatory_user_inputs {
        m1_exec(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m1_exec {
    release_types,review_audit,description "Review signoffs + manifest for M1_EXEC"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/m1_test_review11/outputs/review_signoff.txt" "review_signoffs/m1_test_review1.txt"
        "work/log_scoreboard_check11/outputs/review_signoff.txt" "review_signoffs/log_scoreboard_check1.txt"
        "work/waveform_check11/outputs/review_signoff.txt" "review_signoffs/waveform_check1.txt"
        "work/coverage_assertions_review11/outputs/review_signoff.txt" "review_signoffs/coverage_assertions_review1.txt"
        "work/bug_tracking11/outputs/review_signoff.txt" "review_signoffs/bug_tracking1.txt"
        "work/regression_gatekeeper11/outputs/review_signoff.txt" "review_signoffs/regression_gatekeeper1.txt"
        "work/export_db11/outputs/review_signoff.txt" "review_signoffs/export_db1.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m1_exec {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
