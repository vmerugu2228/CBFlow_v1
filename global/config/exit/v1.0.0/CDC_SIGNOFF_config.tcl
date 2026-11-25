# ═══════════════════════════════════════════════════════════════════════════════
# CDC_SIGNOFF Milestone Configuration
# CDC Sign-off — 0 open clock-domain-crossing errors / warnings (opencdc, clocks from the SDC)
# Stage: signoff1 (RTL_CDC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "CDC_SIGNOFF"
set milestone_info(discipline)  "RTL"
set milestone_info(flow_type)   "RTL_CDC"
set milestone_info(stage)       "signoff"
set milestone_info(description) "CDC Sign-off — 0 open clock-domain-crossing errors / warnings (opencdc, clocks from the SDC)"
set milestone_info(stage_node)  "signoff1"
set milestone_info(report_dir)  "reports/rtl_cdc"
set milestone_info(owner)       "vmerugu"

array set check_packs {}

array set mandatory_checks {
    "cdc_open_errors" {
        "id"                "CDC_0001"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) errors"
        "criteria"          "cdc_open_errors <= 0"
        "min_phase_index"   "0"
        "metric_name"       "cdc_open_errors"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "cdc_open_warnings" {
        "id"                "CDC_0002"
        "script"            "check_metric.tcl"
        "description"       "No open (unwaived) warnings"
        "criteria"          "cdc_open_warnings <= 0"
        "min_phase_index"   "0"
        "metric_name"       "cdc_open_warnings"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
}

array set optional_checks {}

set mandatory_files [list \
    "reports/cdc_signoff.rpt" \
    "outputs/violations_final.csv" \
]

array set deliverables {}
