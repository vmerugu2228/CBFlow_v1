# ═══════════════════════════════════════════════════════════════════════════════
# M1_EXIT Milestone Configuration
# M1 Exit — testplan execution milestone 1 (0.3v RTL)
# Stage: m1_exec1 (M1_EXEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "M1_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "m1_exec"
set milestone_info(description) "M1 Exit — testplan execution milestone 1 (0.3v RTL)"
set milestone_info(stage_node)  "m1_exec1"
set milestone_info(report_dir)  "reports/m1_exec"
set milestone_info(owner)       "DV M1 owner"
set milestone_info(flow_type)   "M1_EXEC"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "m1_review_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "M1 execution review signoff present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/review_signoff.txt"
    }
    "m1_regression_gatekeeper" {
        "script"            "check_file_exists.tcl"
        "description"       "M1 regression gatekeeper report"
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
    "m1_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/M1_EXIT/review_signoff.txt" }
    "m1_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/M1_EXIT/MANIFEST.json" }
}
