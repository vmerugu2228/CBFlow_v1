#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV — TB_SETUP Flow Configuration
# Testbench setup & sanity verification (0.1v RTL / M0)
#
# Linear review-gate flow: inputs → N review stages → release_data1
# No EDA tool invocation — each review stage attaches an artifact and stamps a
# signoff via the shared review_gate.tcl command file.
# ═══════════════════════════════════════════════════════════════════════════════

# Optional stages — included in the DAG but can be skipped via
# user_config: set tb_setup(skip_stages) {formal_setup1}
# Linear deps: inputs → review_1 → review_2 → ... → release_data1
array set tb_setup {
    stages {review_artifact1 vip_review1 tb_alignment1 sanity_tests1 tb_quality_check1 formal_setup1 repo_checkin1 export_db1 release_data1}

    merge_entry_stage     inputs
    merge_handoff_stage   release_data1
    merge_parallel_stages {}

    optional_stages {formal_setup1}

    dependencies,vip_review1                         {review_artifact1}
    dependencies,tb_alignment1                       {vip_review1}
    dependencies,sanity_tests1                       {tb_alignment1}
    dependencies,tb_quality_check1                   {sanity_tests1}
    dependencies,formal_setup1                       {tb_quality_check1}
    dependencies,repo_checkin1                       {formal_setup1}
    dependencies,export_db1                          {repo_checkin1}
    dependencies,release_data1                       {export_db1}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUBNODES & WORK DIRS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Every non-inputs stage uses the standard 4-phase subnode pattern.
set _tb_setup_exec_stages {vip_review1 tb_alignment1 sanity_tests1 tb_quality_check1 formal_setup1 repo_checkin1 export_db1 release_data1}
foreach _s $_tb_setup_exec_stages {
    set tb_setup(subnodes,$_s) {setup run validate finish}
    set tb_setup(subnode_dependencies,${_s},setup)    {}
    set tb_setup(subnode_dependencies,${_s},run)      {setup}
    set tb_setup(subnode_dependencies,${_s},validate) {run}
    set tb_setup(subnode_dependencies,${_s},finish)   {validate}
    foreach _sub {setup run validate finish} {
        set tb_setup(subnode_work_dirs,${_s},${_sub}) "work/${_s}/${_sub}"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NODE TYPES & STAGE TYPES                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set tb_setup {
    stage_types,review_artifact1 "inputs"
    stage_types,vip_review1                         "review"
    stage_types,tb_alignment1                       "review"
    stage_types,sanity_tests1                       "review"
    stage_types,tb_quality_check1                   "review"
    stage_types,formal_setup1                       "review"
    stage_types,repo_checkin1                       "review"
    stage_types,export_db1                          "review"
    stage_types,release_data1 "release"

    node_types,review_artifact1 "inputs"
    node_types,vip_review1                         "review"
    node_types,tb_alignment1                       "review"
    node_types,sanity_tests1                       "review"
    node_types,tb_quality_check1                   "review"
    node_types,formal_setup1                       "review"
    node_types,repo_checkin1                       "review"
    node_types,export_db1                          "review"
    node_types,release_data1  "release_data"

    node_descriptions,review_artifact1 "Review-artifact input collection"
    node_descriptions,vip_review1                         "Vip Review1 review gate (artifact-attach + signoff)"
    node_descriptions,tb_alignment1                       "Tb Alignment1 review gate (artifact-attach + signoff)"
    node_descriptions,sanity_tests1                       "Sanity Tests1 review gate (artifact-attach + signoff)"
    node_descriptions,tb_quality_check1                   "Tb Quality Check1 review gate (artifact-attach + signoff)"
    node_descriptions,formal_setup1                       "Formal Setup1 review gate (artifact-attach + signoff)"
    node_descriptions,repo_checkin1                       "Repo Checkin1 review gate (artifact-attach + signoff)"
    node_descriptions,export_db1                          "Export Db1 review gate (artifact-attach + signoff)"
    node_descriptions,release_data1 "Release the full review audit trail (signoffs + MANIFEST)"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RUNTIME                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set tb_setup {
    runtime,timeout,review_artifact1 10
    runtime,timeout,vip_review1                         30
    runtime,timeout,tb_alignment1                       30
    runtime,timeout,sanity_tests1                       30
    runtime,timeout,tb_quality_check1                   30
    runtime,timeout,formal_setup1                       30
    runtime,timeout,repo_checkin1                       30
    runtime,timeout,export_db1                          30
    runtime,timeout,release_data1 10
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        INPUTS & OUTPUTS                                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Every review stage produces a signoff artifact under its outputs/.
# Review flows take a single generic 'review_artifact' input bundle —
# the engineer attaches the review document / regression log / coverage
# report through user_config: set tb_setup(input,review_artifact) <path>.
array set tb_setup {
    mandatory_outputs,vip_review1                         {outputs/review_signoff.txt}
    mandatory_outputs,tb_alignment1                       {outputs/review_signoff.txt}
    mandatory_outputs,sanity_tests1                       {outputs/review_signoff.txt}
    mandatory_outputs,tb_quality_check1                   {outputs/review_signoff.txt}
    mandatory_outputs,formal_setup1                       {outputs/review_signoff.txt}
    mandatory_outputs,repo_checkin1                       {outputs/review_signoff.txt}
    mandatory_outputs,export_db1                          {outputs/review_signoff.txt}
    mandatory_outputs,release_data1 {outputs/release_data/MANIFEST.json}

    input_types {review_artifact}

    mandatory_input_groups {
        review_inputs { tb_setup(input,review_artifact) }
    }
    mandatory_user_inputs {
        tb_setup(input,review_artifact)
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        RELEASE CONFIGURATION                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set tb_setup {
    release_types,review_audit,description "Review signoffs + manifest for TB_SETUP"
    release_types,review_audit,files {
        "outputs/release_data/MANIFEST.json" "MANIFEST.json"
        "work/vip_review11/outputs/review_signoff.txt" "review_signoffs/vip_review1.txt"
        "work/tb_alignment11/outputs/review_signoff.txt" "review_signoffs/tb_alignment1.txt"
        "work/sanity_tests11/outputs/review_signoff.txt" "review_signoffs/sanity_tests1.txt"
        "work/tb_quality_check11/outputs/review_signoff.txt" "review_signoffs/tb_quality_check1.txt"
        "work/formal_setup11/outputs/review_signoff.txt" "review_signoffs/formal_setup1.txt"
        "work/repo_checkin11/outputs/review_signoff.txt" "review_signoffs/repo_checkin1.txt"
        "work/export_db11/outputs/review_signoff.txt" "review_signoffs/export_db1.txt"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SUPPORTED TOOLS                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set tb_setup {
    supported_tools {review}
    default_tool    "review"
    tool,vendor     "generic"
    tool,name       "review"
    tool,version    "v1.0.0"
}
