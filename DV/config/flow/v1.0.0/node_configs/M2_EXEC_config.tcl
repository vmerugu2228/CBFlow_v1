#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — M2_EXEC Flow Configuration
# Test plan execution — Milestone 2 (0.5v RTL & GLS/LP setup)
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set m2_exec(skip_stages) {lp_plan_signoff}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set m2_exec {
    stages {inputs m2_test_review log_scoreboard_check waveform_check coverage_waivers gls_plan_signoff lp_plan_signoff bug_tracking export_db release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {lp_plan_signoff}

    dependencies,m2_test_review                      {inputs}
    dependencies,log_scoreboard_check                {m2_test_review}
    dependencies,waveform_check                      {log_scoreboard_check}
    dependencies,coverage_waivers                    {waveform_check}
    dependencies,gls_plan_signoff                    {coverage_waivers}
    dependencies,lp_plan_signoff                     {gls_plan_signoff}
    dependencies,bug_tracking                        {lp_plan_signoff}
    dependencies,export_db                           {bug_tracking}
    dependencies,release_data1                       {export_db}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _m2_exec_exec_stages {m2_test_review log_scoreboard_check waveform_check coverage_waivers gls_plan_signoff lp_plan_signoff bug_tracking export_db release_data1}
foreach _s $_m2_exec_exec_stages {
    set m2_exec(subnodes,$_s) {setup run validate finish}
    set m2_exec(subnode_dependencies,${_s},setup)    {}
    set m2_exec(subnode_dependencies,${_s},run)      {setup}
    set m2_exec(subnode_dependencies,${_s},validate) {run}
    set m2_exec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set m2_exec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m2_exec {
    stage_types,inputs        "inputs"
    stage_types,m2_test_review                      "review"
    stage_types,log_scoreboard_check                "review"
    stage_types,waveform_check                      "review"
    stage_types,coverage_waivers                    "review"
    stage_types,gls_plan_signoff                    "review"
    stage_types,lp_plan_signoff                     "review"
    stage_types,bug_tracking                        "review"
    stage_types,export_db                           "review"
    stage_types,release_data1 "release"

    node_types,inputs         "inputs"
    node_types,m2_test_review                      "review"
    node_types,log_scoreboard_check                "review"
    node_types,waveform_check                      "review"
    node_types,coverage_waivers                    "review"
    node_types,gls_plan_signoff                    "review"
    node_types,lp_plan_signoff                     "review"
    node_types,bug_tracking                        "review"
    node_types,export_db                           "review"
    node_types,release_data1  "release_data"

    node_descriptions,inputs        "Review-artifact input collection"
    node_descriptions,m2_test_review                      "M2 Test Review review gate (artifact-attach + signoff)"
    node_descriptions,log_scoreboard_check                "Log Scoreboard Check review gate (artifact-attach + signoff)"
    node_descriptions,waveform_check                      "Waveform Check review gate (artifact-attach + signoff)"
    node_descriptions,coverage_waivers                    "Coverage Waivers review gate (artifact-attach + signoff)"
    node_descriptions,gls_plan_signoff                    "Gls Plan Signoff review gate (artifact-attach + signoff)"
    node_descriptions,lp_plan_signoff                     "Lp Plan Signoff review gate (artifact-attach + signoff)"
    node_descriptions,bug_tracking                        "Bug Tracking review gate (artifact-attach + signoff)"
    node_descriptions,export_db                           "Export Db review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m2_exec {
    runtime,timeout,inputs        10
    runtime,timeout,m2_test_review                      30
    runtime,timeout,log_scoreboard_check                30
    runtime,timeout,waveform_check                      30
    runtime,timeout,coverage_waivers                    30
    runtime,timeout,gls_plan_signoff                    30
    runtime,timeout,lp_plan_signoff                     30
    runtime,timeout,bug_tracking                        30
    runtime,timeout,export_db                           30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set m2_exec(input,review_artifact) <path>.
array set m2_exec {
    mandatory_outputs,m2_test_review                      {outputs/review_signoff.txt}
    mandatory_outputs,log_scoreboard_check                {outputs/review_signoff.txt}
    mandatory_outputs,waveform_check                      {outputs/review_signoff.txt}
    mandatory_outputs,coverage_waivers                    {outputs/review_signoff.txt}
    mandatory_outputs,gls_plan_signoff                    {outputs/review_signoff.txt}
    mandatory_outputs,lp_plan_signoff                     {outputs/review_signoff.txt}
    mandatory_outputs,bug_tracking                        {outputs/review_signoff.txt}
    mandatory_outputs,export_db                           {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { m2_exec(input,review_artifact) }
    }
    mandatory_user_inputs {
        m2_exec(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m2_exec {
    release_types,review_audit,description "Review signoffs + manifest for M2_EXEC"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/m2_test_review1/outputs/review_signoff.txt" "review_signoffs/m2_test_review.txt"
        "work/log_scoreboard_check1/outputs/review_signoff.txt" "review_signoffs/log_scoreboard_check.txt"
        "work/waveform_check1/outputs/review_signoff.txt" "review_signoffs/waveform_check.txt"
        "work/coverage_waivers1/outputs/review_signoff.txt" "review_signoffs/coverage_waivers.txt"
        "work/gls_plan_signoff1/outputs/review_signoff.txt" "review_signoffs/gls_plan_signoff.txt"
        "work/lp_plan_signoff1/outputs/review_signoff.txt" "review_signoffs/lp_plan_signoff.txt"
        "work/bug_tracking1/outputs/review_signoff.txt" "review_signoffs/bug_tracking.txt"
        "work/export_db1/outputs/review_signoff.txt" "review_signoffs/export_db.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set m2_exec {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
