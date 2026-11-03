# ═══════════════════════════════════════════════════════════════════════════════
# ATPG_POSTPD_EXIT Milestone Configuration
# ATPG Post-PD Exit — ZD sim + Timing sim + Pattern signoff + delivery repo
# Stage: signoff1 (ATPG flow, pd_phase=post)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "ATPG_POSTPD_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(stage)       "signoff"
set milestone_info(description) "ATPG Post-PD Exit — ZD + timing sim done, patterns signed off, delivery repo built"
set milestone_info(stage_node)  "signoff1"
set milestone_info(report_dir)  "reports/atpg"
set milestone_info(owner)       "Gnaneswar"

array set check_packs {}

array set mandatory_checks {
    "atpg_post_patterns" {
        "script"            "check_file_exists.tcl"
        "description"       "Post-PD ATPG patterns (STIL) present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.atpg.postpd.stil"
    }
    "atpg_zd_sim_log" {
        "script"            "check_file_exists.tcl"
        "description"       "Zero-delay pattern simulation log present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/zd_sim.log"
    }
    "atpg_timing_sim_log" {
        "script"            "check_file_exists.tcl"
        "description"       "Timing (SDF) pattern simulation log present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/timing_sim.log"
    }
    "atpg_signoff_report" {
        "script"            "check_file_exists.tcl"
        "description"       "Pattern sign-off report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/signoff.rpt"
    }
    "atpg_delivery_manifest" {
        "script"            "check_file_exists.tcl"
        "description"       "Delivery repo manifest present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/delivery/MANIFEST.json"
    }
}

array set optional_checks {
    "atpg_post_fault_coverage_pct" {
        "script"            "check_metric.tcl"
        "description"       "Post-PD fault coverage >= 99%"
        "criteria"          "fault_coverage_pct >= 99"
        "min_phase_index"   "0"
        "metric_name"       "fault_coverage_pct"
        "operator"          ">="
        "default_threshold" "99"
    }
    "atpg_timing_sim_pass" {
        "script"            "check_grep.tcl"
        "description"       "Timing simulation shows zero mismatches"
        "criteria"          "mismatches == 0"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/timing_sim.log"
        "grep_pattern"      "Mismatches\\s*:\\s*0"
        "grep_pass_if"      "found"
    }
}

set mandatory_files [list \
    "outputs/${design_name}.atpg.postpd.stil" \
    "reports/atpg/zd_sim.log" \
    "reports/atpg/timing_sim.log" \
    "reports/atpg/signoff.rpt" \
    "outputs/delivery/MANIFEST.json" \
]

array set deliverables {
    "atpg_postpd_patterns" { "type" "patterns" "src" "outputs/${design_name}.atpg.postpd.stil" "dst" "releases/ATPG_POSTPD_EXIT/${design_name}.atpg.postpd.stil" }
    "signoff_report"       { "type" "report"   "src" "reports/atpg/signoff.rpt"                "dst" "releases/ATPG_POSTPD_EXIT/signoff.rpt" }
    "delivery_manifest"    { "type" "manifest" "src" "outputs/delivery/MANIFEST.json"          "dst" "releases/ATPG_POSTPD_EXIT/MANIFEST.json" }
}
