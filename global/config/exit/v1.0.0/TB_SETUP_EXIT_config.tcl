# ═══════════════════════════════════════════════════════════════════════════════
# TB_SETUP_EXIT Milestone Configuration
# Testbench Setup Exit (M0) — sim env green, sanity tests passing
# Stage: tb_setup1 (TB_SETUP flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "TB_SETUP_EXIT"
set milestone_info(discipline)  "DV"
set milestone_info(stage)       "tb_setup"
set milestone_info(description) "Testbench Setup Exit (M0) — sim env green, sanity tests passing"
set milestone_info(stage_node)  "tb_setup1"
set milestone_info(report_dir)  "reports/tb_setup"
set milestone_info(owner)       "DV testbench lead"
set milestone_info(flow_type)   "TB_SETUP"

# ── Check packs ──────────────────────────────────────────────────────────────
# DV milestones don't yet consume the shared check library (timing /
# placement / clock / power / routing / physical / si / manufacturing)
# — all of those are PD-shaped. DV-specific checks (coverage %, UVM
# error counts, bins, uvm_warnings) land here as the DV team evolves
# their check library.
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "tb_sanity_signoff" {
        "script"            "check_file_exists.tcl"
        "description"       "Testbench sanity signoff present"
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
    "tb_setup_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/TB_SETUP_EXIT/review_signoff.txt" }
    "tb_setup_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/TB_SETUP_EXIT/MANIFEST.json" }
}
