# ═══════════════════════════════════════════════════════════════════════════════
# M3_EXIT Milestone Configuration
# M3 Exit — testplan execution milestone 3 (0.8v RTL & GLS zero-delay)
# Stage: m3_exec1 (M3_EXEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "M3_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "m3_exec"
set milestone_info(description) "M3 Exit — testplan execution milestone 3 (0.8v RTL & GLS zero-delay)"
set milestone_info(stage_node)  "m3_exec1"
set milestone_info(report_dir)  "reports/m3_exec"
set milestone_info(owner)       "DV M3 owner"
set milestone_info(flow_type)   "M3_EXEC"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "m3_review_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "M3 execution review signoff present"
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
    "m3_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/M3_EXIT/review_signoff.txt" }
    "m3_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/M3_EXIT/MANIFEST.json" }
}
