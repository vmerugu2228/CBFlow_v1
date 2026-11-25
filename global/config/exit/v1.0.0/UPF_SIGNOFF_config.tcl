# ═══════════════════════════════════════════════════════════════════════════════
# UPF_SIGNOFF Milestone Configuration
# UPF Sign-off — power intent consistent with the RTL and the spec, 0 open errors / warnings
# Stage: signoff1 (UPF_CHECK flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "UPF_SIGNOFF"
set milestone_info(discipline)  "RTL"
set milestone_info(flow_type)   "UPF_CHECK"
set milestone_info(stage)       "signoff"
set milestone_info(description) "UPF Sign-off — power intent consistent with the RTL and the spec, 0 open errors / warnings"
set milestone_info(stage_node)  "signoff1"
set milestone_info(report_dir)  "reports/upf_check"
set milestone_info(owner)       "vmerugu"

array set check_packs {}

array set mandatory_checks {
    "upf_open_errors" {
        "id"                "UPF_0001"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) errors"
        "criteria"          "upf_open_errors <= 0"
        "min_phase_index"   "0"
        "metric_name"       "upf_open_errors"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "upf_open_warnings" {
        "id"                "UPF_0002"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) warnings"
        "criteria"          "upf_open_warnings <= 0"
        "min_phase_index"   "0"
        "metric_name"       "upf_open_warnings"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
}

array set optional_checks {}

set mandatory_files [list \
    "reports/upf_signoff.rpt" \
    "outputs/violations_final.csv" \
]

array set deliverables {}
