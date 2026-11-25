# ═══════════════════════════════════════════════════════════════════════════════
# LINT_SIGNOFF Milestone Configuration
# Lint Sign-off — RTL elaborates, 0 open lint errors / warnings (slang, Verilator, Verible); waivers reasoned, owned, unexpired
# Stage: report1 (RTL_LINT flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "LINT_SIGNOFF"
set milestone_info(discipline)  "RTL"
set milestone_info(flow_type)   "RTL_LINT"
set milestone_info(stage)       "report"
set milestone_info(description) "Lint Sign-off — RTL elaborates, 0 open lint errors / warnings (slang, Verilator, Verible); waivers reasoned, owned, unexpired"
set milestone_info(stage_node)  "report1"
set milestone_info(report_dir)  "reports/rtl_lint"
set milestone_info(owner)       "vmerugu"

array set check_packs {}

array set mandatory_checks {
    "lint_open_errors" {
        "id"                "LINT_0001"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) errors"
        "criteria"          "lint_open_errors <= 0"
        "min_phase_index"   "0"
        "metric_name"       "lint_open_errors"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "lint_open_warnings" {
        "id"                "LINT_0002"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) warnings"
        "criteria"          "lint_open_warnings <= 0"
        "min_phase_index"   "0"
        "metric_name"       "lint_open_warnings"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "lint_expired_waivers" {
        "id"                "LINT_0003"
        "script"            "check_metric.tcl"
        "description"       "No expired waivers"
        "criteria"          "lint_expired_waivers <= 0"
        "min_phase_index"   "0"
        "metric_name"       "lint_expired_waivers"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
}

array set optional_checks {}

set mandatory_files [list \
    "reports/lint_signoff.rpt" \
    "outputs/violations_final.csv" \
]

array set deliverables {}
