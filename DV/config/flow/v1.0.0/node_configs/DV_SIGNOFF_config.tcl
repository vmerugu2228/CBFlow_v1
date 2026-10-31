#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — DV_SIGNOFF Flow Configuration
# Verification signoff & closure
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set dv_signoff(skip_stages) {}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set dv_signoff {
    stages {review_artifact1 test_pass_coverage_1001 selected_test_deepdive1 waiver_force_bug_review1 closure_doc_lessons_learned1 final_signoff1 release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,test_pass_coverage_1001             {review_artifact1}
    dependencies,selected_test_deepdive1             {test_pass_coverage_1001}
    dependencies,waiver_force_bug_review1            {selected_test_deepdive1}
    dependencies,closure_doc_lessons_learned1        {waiver_force_bug_review1}
    dependencies,final_signoff1                      {closure_doc_lessons_learned1}
    dependencies,release_data1                       {final_signoff1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _dv_signoff_exec_stages {test_pass_coverage_1001 selected_test_deepdive1 waiver_force_bug_review1 closure_doc_lessons_learned1 final_signoff1 release_data1}
foreach _s $_dv_signoff_exec_stages {
    set dv_signoff(subnodes,$_s) {setup run validate finish}
    set dv_signoff(subnode_dependencies,${_s},setup)    {}
    set dv_signoff(subnode_dependencies,${_s},run)      {setup}
    set dv_signoff(subnode_dependencies,${_s},validate) {run}
    set dv_signoff(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set dv_signoff(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dv_signoff {
    stage_types,review_artifact1 "inputs"
    stage_types,test_pass_coverage_1001             "review"
    stage_types,selected_test_deepdive1             "review"
    stage_types,waiver_force_bug_review1            "review"
    stage_types,closure_doc_lessons_learned1        "review"
    stage_types,final_signoff1                      "review"
    stage_types,release_data1 "release"

    node_types,review_artifact1 "inputs"
    node_types,test_pass_coverage_1001             "review"
    node_types,selected_test_deepdive1             "review"
    node_types,waiver_force_bug_review1            "review"
    node_types,closure_doc_lessons_learned1        "review"
    node_types,final_signoff1                      "review"
    node_types,release_data1  "release_data"

    node_descriptions,review_artifact1 "Review-artifact input collection"
    node_descriptions,test_pass_coverage_1001             "Test Pass Coverage 1001 review gate (artifact-attach + signoff)"
    node_descriptions,selected_test_deepdive1             "Selected Test Deepdive1 review gate (artifact-attach + signoff)"
    node_descriptions,waiver_force_bug_review1            "Waiver Force Bug Review1 review gate (artifact-attach + signoff)"
    node_descriptions,closure_doc_lessons_learned1        "Closure Doc Lessons Learned1 review gate (artifact-attach + signoff)"
    node_descriptions,final_signoff1                      "Final Signoff1 review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dv_signoff {
    runtime,timeout,review_artifact1 10
    runtime,timeout,test_pass_coverage_1001             30
    runtime,timeout,selected_test_deepdive1             30
    runtime,timeout,waiver_force_bug_review1            30
    runtime,timeout,closure_doc_lessons_learned1        30
    runtime,timeout,final_signoff1                      30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set dv_signoff(input,review_artifact) <path>.
array set dv_signoff {
    mandatory_outputs,test_pass_coverage_1001             {outputs/review_signoff.txt}
    mandatory_outputs,selected_test_deepdive1             {outputs/review_signoff.txt}
    mandatory_outputs,waiver_force_bug_review1            {outputs/review_signoff.txt}
    mandatory_outputs,closure_doc_lessons_learned1        {outputs/review_signoff.txt}
    mandatory_outputs,final_signoff1                      {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { dv_signoff(input,review_artifact) }
    }
    mandatory_user_inputs {
        dv_signoff(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dv_signoff {
    release_types,review_audit,description "Review signoffs + manifest for DV_SIGNOFF"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/test_pass_coverage_10011/outputs/review_signoff.txt" "review_signoffs/test_pass_coverage_1001.txt"
        "work/selected_test_deepdive11/outputs/review_signoff.txt" "review_signoffs/selected_test_deepdive1.txt"
        "work/waiver_force_bug_review11/outputs/review_signoff.txt" "review_signoffs/waiver_force_bug_review1.txt"
        "work/closure_doc_lessons_learned11/outputs/review_signoff.txt" "review_signoffs/closure_doc_lessons_learned1.txt"
        "work/final_signoff11/outputs/review_signoff.txt" "review_signoffs/final_signoff1.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set dv_signoff {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
