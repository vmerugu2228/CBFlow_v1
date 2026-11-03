# ═══════════════════════════════════════════════════════════════════════════════
# ECO_EXEC_EXIT Milestone Configuration
# ECO Verification Exit — ECO re-regression complete, deltas reviewed
# Stage: eco_exec1 (ECO_EXEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "ECO_EXEC_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "eco_exec"
set milestone_info(description) "ECO Verification Exit — ECO re-regression complete, deltas reviewed"
set milestone_info(stage_node)  "eco_exec1"
set milestone_info(report_dir)  "reports/eco_exec"
set milestone_info(owner)       "DV ECO owner"
set milestone_info(flow_type)   "ECO_EXEC"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "eco_review_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "ECO regression review signoff present"
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
    "eco_exec_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/ECO_EXEC_EXIT/review_signoff.txt" }
    "eco_exec_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/ECO_EXEC_EXIT/MANIFEST.json" }
}
