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
    stages {review_artifact1 eco_test_coding1 random_log_check1 waveform_check1 full_pass_zero_bugs1 gls_sdf_full_pass1 export_db1 release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,eco_test_coding1                    {review_artifact1}
    dependencies,random_log_check1                   {eco_test_coding1}
    dependencies,waveform_check1                     {random_log_check1}
    dependencies,full_pass_zero_bugs1                {waveform_check1}
    dependencies,gls_sdf_full_pass1                  {full_pass_zero_bugs1}
    dependencies,export_db1                          {gls_sdf_full_pass1}
    dependencies,release_data1                       {export_db1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _eco_exec_exec_stages {eco_test_coding1 random_log_check1 waveform_check1 full_pass_zero_bugs1 gls_sdf_full_pass1 export_db1 release_data1}
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
    stage_types,review_artifact1 "inputs"
    stage_types,eco_test_coding1                    "review"
    stage_types,random_log_check1                   "review"
    stage_types,waveform_check1                     "review"
    stage_types,full_pass_zero_bugs1                "review"
    stage_types,gls_sdf_full_pass1                  "review"
    stage_types,export_db1                          "review"
    stage_types,release_data1 "release"

    node_types,review_artifact1 "inputs"
    node_types,eco_test_coding1                    "review"
    node_types,random_log_check1                   "review"
    node_types,waveform_check1                     "review"
    node_types,full_pass_zero_bugs1                "review"
    node_types,gls_sdf_full_pass1                  "review"
    node_types,export_db1                          "review"
    node_types,release_data1  "release_data"

    node_descriptions,review_artifact1 "Review-artifact input collection"
    node_descriptions,eco_test_coding1                    "Eco Test Coding1 review gate (artifact-attach + signoff)"
    node_descriptions,random_log_check1                   "Random Log Check1 review gate (artifact-attach + signoff)"
    node_descriptions,waveform_check1                     "Waveform Check1 review gate (artifact-attach + signoff)"
    node_descriptions,full_pass_zero_bugs1                "Full Pass Zero Bugs1 review gate (artifact-attach + signoff)"
    node_descriptions,gls_sdf_full_pass1                  "Gls Sdf Full Pass1 review gate (artifact-attach + signoff)"
    node_descriptions,export_db1                          "Export Db1 review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set eco_exec {
    runtime,timeout,review_artifact1 10
    runtime,timeout,eco_test_coding1                    30
    runtime,timeout,random_log_check1                   30
    runtime,timeout,waveform_check1                     30
    runtime,timeout,full_pass_zero_bugs1                30
    runtime,timeout,gls_sdf_full_pass1                  30
    runtime,timeout,export_db1                          30
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
    mandatory_outputs,eco_test_coding1                    {outputs/review_signoff.txt}
    mandatory_outputs,random_log_check1                   {outputs/review_signoff.txt}
    mandatory_outputs,waveform_check1                     {outputs/review_signoff.txt}
    mandatory_outputs,full_pass_zero_bugs1                {outputs/review_signoff.txt}
    mandatory_outputs,gls_sdf_full_pass1                  {outputs/review_signoff.txt}
    mandatory_outputs,export_db1                          {outputs/review_signoff.txt}
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
        "work/eco_test_coding11/outputs/review_signoff.txt" "review_signoffs/eco_test_coding1.txt"
        "work/random_log_check11/outputs/review_signoff.txt" "review_signoffs/random_log_check1.txt"
        "work/waveform_check11/outputs/review_signoff.txt" "review_signoffs/waveform_check1.txt"
        "work/full_pass_zero_bugs11/outputs/review_signoff.txt" "review_signoffs/full_pass_zero_bugs1.txt"
        "work/gls_sdf_full_pass11/outputs/review_signoff.txt" "review_signoffs/gls_sdf_full_pass1.txt"
        "work/export_db11/outputs/review_signoff.txt" "review_signoffs/export_db1.txt"
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
