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
    "dv_signoff_status" {
        "id"                "M3_EXEC_0010"
        "script"            "check_grep.tcl"
        "description"       "M3 regression sign-off: every project(dv,targets,M3) target met (open-source UVM flow)"
        "criteria"          "Status PASS"
        "min_phase_index"   "0"
        "report_file"       "reports/dv_signoff.rpt"
        "grep_pattern"      "Status\\s*:\\s*PASS"
        "grep_pass_if"      "found"
    }
    "m3_review_signoff" {
        "id"          "M3_EXEC_0001"
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
array set optional_checks {
    "dv_pass_rate" {
        "id"                "M3_EXEC_0011"
        "script"            "check_grep.tcl"
        "description"       "Regression pass rate meets its project(dv,targets,M3) target (or has none)"
        "criteria"          "pass_rate not NOT MET in the sign-off report"
        "min_phase_index"   "0"
        "report_file"       "reports/dv_signoff.rpt"
        "grep_pattern"      "^\\s*pass_rate\\s*:.*NOT MET"
        "grep_pass_if"      "not_found"
    }
    "dv_code_coverage" {
        "id"                "M3_EXEC_0012"
        "script"            "check_grep.tcl"
        "description"       "DUT code coverage (line + branch) meets its project(dv,targets,M3) target (or has none)"
        "criteria"          "code_coverage not NOT MET in the sign-off report"
        "min_phase_index"   "0"
        "report_file"       "reports/dv_signoff.rpt"
        "grep_pattern"      "^\\s*code_coverage\\s*:.*NOT MET"
        "grep_pass_if"      "not_found"
    }
    "dv_functional_coverage" {
        "id"                "M3_EXEC_0013"
        "script"            "check_grep.tcl"
        "description"       "Functional coverage (covergroup bins) meets its project(dv,targets,M3) target (or has none)"
        "criteria"          "functional_coverage not NOT MET in the sign-off report"
        "min_phase_index"   "0"
        "report_file"       "reports/dv_signoff.rpt"
        "grep_pattern"      "^\\s*functional_coverage\\s*:.*NOT MET"
        "grep_pass_if"      "not_found"
    }
    "dv_plan_coverage" {
        "id"                "M3_EXEC_0014"
        "script"            "check_grep.tcl"
        "description"       "vPlan features closed / waived meets its project(dv,targets,M3) target (or has none)"
        "criteria"          "plan_coverage not NOT MET in the sign-off report"
        "min_phase_index"   "0"
        "report_file"       "reports/dv_signoff.rpt"
        "grep_pattern"      "^\\s*plan_coverage\\s*:.*NOT MET"
        "grep_pass_if"      "not_found"
    }
}

# ── Mandatory files ──────────────────────────────────────────────────────────
set mandatory_files [list \
    "outputs/review_signoff.txt" \
]

# ── Deliverables ─────────────────────────────────────────────────────────────
array set deliverables {
    "m3_review"  { "type" "report"   "src" "outputs/review_signoff.txt"      "dst" "releases/M3_EXIT/review_signoff.txt" }
    "m3_manifest" { "type" "manifest" "src" "outputs/release_data/MANIFEST.json" "dst" "releases/M3_EXIT/MANIFEST.json" }
}
