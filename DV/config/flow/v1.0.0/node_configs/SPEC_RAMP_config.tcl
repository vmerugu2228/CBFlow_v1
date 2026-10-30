#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — SPEC_RAMP Flow Configuration
# Specification ramp-up & requirement analysis
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set spec_ramp(skip_stages) {}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set spec_ramp {
    stages {inputs drs_review architecture_detailing presentation_review timeline_alignment queries_addressed release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,drs_review                          {inputs}
    dependencies,architecture_detailing              {drs_review}
    dependencies,presentation_review                 {architecture_detailing}
    dependencies,timeline_alignment                  {presentation_review}
    dependencies,queries_addressed                   {timeline_alignment}
    dependencies,release_data1                       {queries_addressed}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _spec_ramp_exec_stages {drs_review architecture_detailing presentation_review timeline_alignment queries_addressed release_data1}
foreach _s $_spec_ramp_exec_stages {
    set spec_ramp(subnodes,$_s) {setup run validate finish}
    set spec_ramp(subnode_dependencies,${_s},setup)    {}
    set spec_ramp(subnode_dependencies,${_s},run)      {setup}
    set spec_ramp(subnode_dependencies,${_s},validate) {run}
    set spec_ramp(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set spec_ramp(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set spec_ramp {
    stage_types,inputs        "inputs"
    stage_types,drs_review                          "review"
    stage_types,architecture_detailing              "review"
    stage_types,presentation_review                 "review"
    stage_types,timeline_alignment                  "review"
    stage_types,queries_addressed                   "review"
    stage_types,release_data1 "release"

    node_types,inputs         "inputs"
    node_types,drs_review                          "review"
    node_types,architecture_detailing              "review"
    node_types,presentation_review                 "review"
    node_types,timeline_alignment                  "review"
    node_types,queries_addressed                   "review"
    node_types,release_data1  "release_data"

    node_descriptions,inputs        "Review-artifact input collection"
    node_descriptions,drs_review                          "Drs Review review gate (artifact-attach + signoff)"
    node_descriptions,architecture_detailing              "Architecture Detailing review gate (artifact-attach + signoff)"
    node_descriptions,presentation_review                 "Presentation Review review gate (artifact-attach + signoff)"
    node_descriptions,timeline_alignment                  "Timeline Alignment review gate (artifact-attach + signoff)"
    node_descriptions,queries_addressed                   "Queries Addressed review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set spec_ramp {
    runtime,timeout,inputs        10
    runtime,timeout,drs_review                          30
    runtime,timeout,architecture_detailing              30
    runtime,timeout,presentation_review                 30
    runtime,timeout,timeline_alignment                  30
    runtime,timeout,queries_addressed                   30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set spec_ramp(input,review_artifact) <path>.
array set spec_ramp {
    mandatory_outputs,drs_review                          {outputs/review_signoff.txt}
    mandatory_outputs,architecture_detailing              {outputs/review_signoff.txt}
    mandatory_outputs,presentation_review                 {outputs/review_signoff.txt}
    mandatory_outputs,timeline_alignment                  {outputs/review_signoff.txt}
    mandatory_outputs,queries_addressed                   {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { spec_ramp(input,review_artifact) }
    }
    mandatory_user_inputs {
        spec_ramp(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set spec_ramp {
    release_types,review_audit,description "Review signoffs + manifest for SPEC_RAMP"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/drs_review1/outputs/review_signoff.txt" "review_signoffs/drs_review.txt"
        "work/architecture_detailing1/outputs/review_signoff.txt" "review_signoffs/architecture_detailing.txt"
        "work/presentation_review1/outputs/review_signoff.txt" "review_signoffs/presentation_review.txt"
        "work/timeline_alignment1/outputs/review_signoff.txt" "review_signoffs/timeline_alignment.txt"
        "work/queries_addressed1/outputs/review_signoff.txt" "review_signoffs/queries_addressed.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set spec_ramp {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
