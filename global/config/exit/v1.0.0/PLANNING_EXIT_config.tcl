# ═══════════════════════════════════════════════════════════════════════════════
# PLANNING_EXIT Milestone Configuration
# Planning Exit — verification plan approved, feature matrix locked
# Stage: planning1 (PLANNING flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "PLANNING_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "planning"
set milestone_info(description) "Planning Exit — verification plan approved, feature matrix locked"
set milestone_info(stage_node)  "planning1"
set milestone_info(report_dir)  "reports/planning"
set milestone_info(owner)       "DV planning lead"
set milestone_info(flow_type)   "PLANNING"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "testplan_review_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "Testplan review signoff present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/review_signoff.txt"
    }
    "feature_matrix_locked" {
        "script"            "check_file_exists.tcl"
        "description"       "Feature matrix lock review present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/review_signoff.txt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
# Owner-team populates coverage / warning / mismatch thresholds here as
# the DV flow matures.
array set optional_checks {}

# ── Mandatory files ──────────────────────────────────────────────────────────
set mandatory_files [list \
    "outputs/review_signoff.txt" \
    "outputs/review_signoff.txt" \
]

# ── Deliverables ─────────────────────────────────────────────────────────────
array set deliverables {
    "planning_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/PLANNING_EXIT/review_signoff.txt" }
    "planning_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/PLANNING_EXIT/MANIFEST.json" }
}
