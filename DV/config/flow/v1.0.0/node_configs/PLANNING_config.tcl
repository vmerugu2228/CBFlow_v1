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
    stages {review_artifact1 approach_definition1 vip_identification1 plan_review_l1_l21 signoff1 export_db1 release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {}

    dependencies,approach_definition1                {review_artifact1}
    dependencies,vip_identification1                 {approach_definition1}
    dependencies,plan_review_l1_l21                  {vip_identification1}
    dependencies,signoff1                            {plan_review_l1_l21}
    dependencies,export_db1                          {signoff1}
    dependencies,release_data1                       {export_db1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _planning_exec_stages {approach_definition1 vip_identification1 plan_review_l1_l21 signoff1 export_db1 release_data1}
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
    stage_types,review_artifact1 "inputs"
    stage_types,approach_definition1                "review"
    stage_types,vip_identification1                 "review"
    stage_types,plan_review_l1_l21                  "review"
    stage_types,signoff1                            "review"
    stage_types,export_db1                          "review"
    stage_types,release_data1 "release"

    node_types,review_artifact1 "inputs"
    node_types,approach_definition1                "review"
    node_types,vip_identification1                 "review"
    node_types,plan_review_l1_l21                  "review"
    node_types,signoff1                            "review"
    node_types,export_db1                          "review"
    node_types,release_data1  "release_data"

    node_descriptions,review_artifact1 "Review-artifact input collection"
    node_descriptions,approach_definition1                "Approach Definition1 review gate (artifact-attach + signoff)"
    node_descriptions,vip_identification1                 "Vip Identification1 review gate (artifact-attach + signoff)"
    node_descriptions,plan_review_l1_l21                  "Plan Review L1 L21 review gate (artifact-attach + signoff)"
    node_descriptions,signoff1                            "Signoff1 review gate (artifact-attach + signoff)"
    node_descriptions,export_db1                          "Export Db1 review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set planning {
    runtime,timeout,review_artifact1 10
    runtime,timeout,approach_definition1                30
    runtime,timeout,vip_identification1                 30
    runtime,timeout,plan_review_l1_l21                  30
    runtime,timeout,signoff1                            30
    runtime,timeout,export_db1                          30
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
    mandatory_outputs,approach_definition1                {outputs/review_signoff.txt}
    mandatory_outputs,vip_identification1                 {outputs/review_signoff.txt}
    mandatory_outputs,plan_review_l1_l21                  {outputs/review_signoff.txt}
    mandatory_outputs,signoff1                            {outputs/review_signoff.txt}
    mandatory_outputs,export_db1                          {outputs/review_signoff.txt}
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
        "work/approach_definition11/outputs/review_signoff.txt" "review_signoffs/approach_definition1.txt"
        "work/vip_identification11/outputs/review_signoff.txt" "review_signoffs/vip_identification1.txt"
        "work/plan_review_l1_l211/outputs/review_signoff.txt" "review_signoffs/plan_review_l1_l21.txt"
        "work/signoff11/outputs/review_signoff.txt" "review_signoffs/signoff1.txt"
        "work/export_db11/outputs/review_signoff.txt" "review_signoffs/export_db1.txt"
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
