#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — PLANNING Flow Configuration
# Verification plan & strategy definition
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set planning(skip_stages) {}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set planning {
    stages {inputs approach_definition vip_identification plan_review_l1_l2 signoff export_db release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,approach_definition                 {inputs}
    dependencies,vip_identification                  {approach_definition}
    dependencies,plan_review_l1_l2                   {vip_identification}
    dependencies,signoff                             {plan_review_l1_l2}
    dependencies,export_db                           {signoff}
    dependencies,release_data1                       {export_db}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _planning_exec_stages {approach_definition vip_identification plan_review_l1_l2 signoff export_db release_data1}
foreach _s $_planning_exec_stages {
    set planning(subnodes,$_s) {setup run validate finish}
    set planning(subnode_dependencies,${_s},setup)    {}
    set planning(subnode_dependencies,${_s},run)      {setup}
    set planning(subnode_dependencies,${_s},validate) {run}
    set planning(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set planning(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set planning {
    stage_types,inputs        "inputs"
    stage_types,approach_definition                 "review"
    stage_types,vip_identification                  "review"
    stage_types,plan_review_l1_l2                   "review"
    stage_types,signoff                             "review"
    stage_types,export_db                           "review"
    stage_types,release_data1 "release"

    node_types,inputs         "inputs"
    node_types,approach_definition                 "review"
    node_types,vip_identification                  "review"
    node_types,plan_review_l1_l2                   "review"
    node_types,signoff                             "review"
    node_types,export_db                           "review"
    node_types,release_data1  "release_data"

    node_descriptions,inputs        "Review-artifact input collection"
    node_descriptions,approach_definition                 "Approach Definition review gate (artifact-attach + signoff)"
    node_descriptions,vip_identification                  "Vip Identification review gate (artifact-attach + signoff)"
    node_descriptions,plan_review_l1_l2                   "Plan Review L1 L2 review gate (artifact-attach + signoff)"
    node_descriptions,signoff                             "Signoff review gate (artifact-attach + signoff)"
    node_descriptions,export_db                           "Export Db review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set planning {
    runtime,timeout,inputs        10
    runtime,timeout,approach_definition                 30
    runtime,timeout,vip_identification                  30
    runtime,timeout,plan_review_l1_l2                   30
    runtime,timeout,signoff                             30
    runtime,timeout,export_db                           30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set planning(input,review_artifact) <path>.
array set planning {
    mandatory_outputs,approach_definition                 {outputs/review_signoff.txt}
    mandatory_outputs,vip_identification                  {outputs/review_signoff.txt}
    mandatory_outputs,plan_review_l1_l2                   {outputs/review_signoff.txt}
    mandatory_outputs,signoff                             {outputs/review_signoff.txt}
    mandatory_outputs,export_db                           {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { planning(input,review_artifact) }
    }
    mandatory_user_inputs {
        planning(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set planning {
    release_types,review_audit,description "Review signoffs + manifest for PLANNING"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/approach_definition1/outputs/review_signoff.txt" "review_signoffs/approach_definition.txt"
        "work/vip_identification1/outputs/review_signoff.txt" "review_signoffs/vip_identification.txt"
        "work/plan_review_l1_l21/outputs/review_signoff.txt" "review_signoffs/plan_review_l1_l2.txt"
        "work/signoff1/outputs/review_signoff.txt" "review_signoffs/signoff.txt"
        "work/export_db1/outputs/review_signoff.txt" "review_signoffs/export_db.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set planning {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
