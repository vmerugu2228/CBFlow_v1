#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — ECO_EXEC Flow Configuration
# ECO verification & re-regression
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set eco_exec(skip_stages) {}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set eco_exec {
    stages {inputs eco_test_coding random_log_check waveform_check full_pass_zero_bugs gls_sdf_full_pass export_db release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,eco_test_coding                     {inputs}
    dependencies,random_log_check                    {eco_test_coding}
    dependencies,waveform_check                      {random_log_check}
    dependencies,full_pass_zero_bugs                 {waveform_check}
    dependencies,gls_sdf_full_pass                   {full_pass_zero_bugs}
    dependencies,export_db                           {gls_sdf_full_pass}
    dependencies,release_data1                       {export_db}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _eco_exec_exec_stages {eco_test_coding random_log_check waveform_check full_pass_zero_bugs gls_sdf_full_pass export_db release_data1}
foreach _s $_eco_exec_exec_stages {
    set eco_exec(subnodes,$_s) {setup run validate finish}
    set eco_exec(subnode_dependencies,${_s},setup)    {}
    set eco_exec(subnode_dependencies,${_s},run)      {setup}
    set eco_exec(subnode_dependencies,${_s},validate) {run}
    set eco_exec(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set eco_exec(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco_exec {
    stage_types,inputs        "inputs"
    stage_types,eco_test_coding                     "review"
    stage_types,random_log_check                    "review"
    stage_types,waveform_check                      "review"
    stage_types,full_pass_zero_bugs                 "review"
    stage_types,gls_sdf_full_pass                   "review"
    stage_types,export_db                           "review"
    stage_types,release_data1 "release"

    node_types,inputs         "inputs"
    node_types,eco_test_coding                     "review"
    node_types,random_log_check                    "review"
    node_types,waveform_check                      "review"
    node_types,full_pass_zero_bugs                 "review"
    node_types,gls_sdf_full_pass                   "review"
    node_types,export_db                           "review"
    node_types,release_data1  "release_data"

    node_descriptions,inputs        "Review-artifact input collection"
    node_descriptions,eco_test_coding                     "Eco Test Coding review gate (artifact-attach + signoff)"
    node_descriptions,random_log_check                    "Random Log Check review gate (artifact-attach + signoff)"
    node_descriptions,waveform_check                      "Waveform Check review gate (artifact-attach + signoff)"
    node_descriptions,full_pass_zero_bugs                 "Full Pass Zero Bugs review gate (artifact-attach + signoff)"
    node_descriptions,gls_sdf_full_pass                   "Gls Sdf Full Pass review gate (artifact-attach + signoff)"
    node_descriptions,export_db                           "Export Db review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco_exec {
    runtime,timeout,inputs        10
    runtime,timeout,eco_test_coding                     30
    runtime,timeout,random_log_check                    30
    runtime,timeout,waveform_check                      30
    runtime,timeout,full_pass_zero_bugs                 30
    runtime,timeout,gls_sdf_full_pass                   30
    runtime,timeout,export_db                           30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set eco_exec(input,review_artifact) <path>.
array set eco_exec {
    mandatory_outputs,eco_test_coding                     {outputs/review_signoff.txt}
    mandatory_outputs,random_log_check                    {outputs/review_signoff.txt}
    mandatory_outputs,waveform_check                      {outputs/review_signoff.txt}
    mandatory_outputs,full_pass_zero_bugs                 {outputs/review_signoff.txt}
    mandatory_outputs,gls_sdf_full_pass                   {outputs/review_signoff.txt}
    mandatory_outputs,export_db                           {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { eco_exec(input,review_artifact) }
    }
    mandatory_user_inputs {
        eco_exec(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco_exec {
    release_types,review_audit,description "Review signoffs + manifest for ECO_EXEC"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/eco_test_coding1/outputs/review_signoff.txt" "review_signoffs/eco_test_coding.txt"
        "work/random_log_check1/outputs/review_signoff.txt" "review_signoffs/random_log_check.txt"
        "work/waveform_check1/outputs/review_signoff.txt" "review_signoffs/waveform_check.txt"
        "work/full_pass_zero_bugs1/outputs/review_signoff.txt" "review_signoffs/full_pass_zero_bugs.txt"
        "work/gls_sdf_full_pass1/outputs/review_signoff.txt" "review_signoffs/gls_sdf_full_pass.txt"
        "work/export_db1/outputs/review_signoff.txt" "review_signoffs/export_db.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco_exec {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
