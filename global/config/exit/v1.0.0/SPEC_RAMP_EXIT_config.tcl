# ═══════════════════════════════════════════════════════════════════════════════
# SPEC_RAMP_EXIT Milestone Configuration
# Spec Ramp-Up Exit — spec baseline reviewed, interfaces catalogued
# Stage: spec1 (SPEC_RAMP flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "SPEC_RAMP_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "spec"
set milestone_info(description) "Spec Ramp-Up Exit — spec baseline reviewed, interfaces catalogued"
set milestone_info(stage_node)  "spec1"
set milestone_info(report_dir)  "reports/spec_ramp"
set milestone_info(owner)       "DV spec lead"
set milestone_info(flow_type)   "SPEC_RAMP"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "spec_baseline_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "Spec baseline review signoff present"
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
]

# ── Deliverables ─────────────────────────────────────────────────────────────
array set deliverables {
    "spec_ramp_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/SPEC_RAMP_EXIT/review_signoff.txt" }
    "spec_ramp_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/SPEC_RAMP_EXIT/MANIFEST.json" }
}
