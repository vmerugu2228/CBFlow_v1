# ═══════════════════════════════════════════════════════════════════════════════
# M4_EXIT Milestone Configuration
# M4 Exit — testplan execution milestone 4 (RTL freeze & GLS SDF)
# Stage: m4_exec1 (M4_EXEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "M4_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "m4_exec"
set milestone_info(description) "M4 Exit — testplan execution milestone 4 (RTL freeze & GLS SDF)"
set milestone_info(stage_node)  "m4_exec1"
set milestone_info(report_dir)  "reports/m4_exec"
set milestone_info(owner)       "DV M4 owner"
set milestone_info(flow_type)   "M4_EXEC"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "m4_review_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "M4 execution review signoff present"
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
    "m4_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/M4_EXIT/review_signoff.txt" }
    "m4_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/M4_EXIT/MANIFEST.json" }
}
