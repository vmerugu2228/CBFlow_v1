# ═══════════════════════════════════════════════════════════════════════════════
# DV_SIGNOFF_EXIT Milestone Configuration
# DV Signoff Exit — verification closure, ready for tapeout handoff
# Stage: dv_signoff1 (DV_SIGNOFF flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "DV_SIGNOFF_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "dv_signoff"
set milestone_info(description) "DV Signoff Exit — verification closure, ready for tapeout handoff"
set milestone_info(stage_node)  "dv_signoff1"
set milestone_info(report_dir)  "reports/dv_signoff"
set milestone_info(owner)       "DV discipline lead"
set milestone_info(flow_type)   "DV_SIGNOFF"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "dv_closure_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "DV closure signoff present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/review_signoff.txt"
    }
    "release_manifest_present" {
        "script"            "check_file_exists.tcl"
        "description"       "DV release manifest present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/release_data/MANIFEST.json"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
# Owner-team populates coverage / warning / mismatch thresholds here as
# the DV flow matures.
array set optional_checks {}

# ── Mandatory files ──────────────────────────────────────────────────────────
set mandatory_files [list \
    "outputs/review_signoff.txt" \
    "outputs/release_data/MANIFEST.json" \
]

# ── Deliverables ─────────────────────────────────────────────────────────────
array set deliverables {
    "dv_signoff_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/DV_SIGNOFF_EXIT/review_signoff.txt" }
    "dv_signoff_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/DV_SIGNOFF_EXIT/MANIFEST.json" }
}
