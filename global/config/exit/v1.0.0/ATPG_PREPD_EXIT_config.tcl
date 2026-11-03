# ═══════════════════════════════════════════════════════════════════════════════
# ATPG_PREPD_EXIT Milestone Configuration
# ATPG Pre-PD Exit — pattern gen + fault sim + coverage report complete
# Stage: coverage_report1 (ATPG flow, pd_phase=pre)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "ATPG_PREPD_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(stage)       "coverage_report"
set milestone_info(description) "ATPG Pre-PD Exit — patterns generated, fault sim done, coverage reported"
set milestone_info(stage_node)  "coverage_report1"
set milestone_info(report_dir)  "reports/atpg"
set milestone_info(owner)       "Gnaneswar"

array set check_packs {}

array set mandatory_checks {
    "atpg_patterns_generated" {
        "script"            "check_file_exists.tcl"
        "description"       "ATPG stuck-at + transition patterns present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.atpg.stil"
    }
    "atpg_coverage_report" {
        "script"            "check_file_exists.tcl"
        "description"       "Fault coverage report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/coverage.rpt"
    }
    "atpg_fault_sim_log" {
        "script"            "check_file_exists.tcl"
        "description"       "Fault simulation log present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/atpg/fault_sim.log"
    }
}

array set optional_checks {
    "atpg_fault_coverage_pct" {
        "script"            "check_metric.tcl"
        "description"       "Stuck-at fault coverage >= 99%"
        "criteria"          "fault_coverage_pct >= 99"
        "min_phase_index"   "0"
        "metric_name"       "fault_coverage_pct"
        "operator"          ">="
        "default_threshold" "99"
    }
    "atpg_test_coverage_pct" {
        "script"            "check_metric.tcl"
        "description"       "Test coverage (ATE) >= 95%"
        "criteria"          "test_coverage_pct >= 95"
        "min_phase_index"   "0"
        "metric_name"       "test_coverage_pct"
        "operator"          ">="
        "default_threshold" "95"
    }
}

set mandatory_files [list \
    "outputs/${design_name}.atpg.stil" \
    "reports/atpg/coverage.rpt" \
    "reports/atpg/fault_sim.log" \
]

array set deliverables {
    "atpg_patterns"  { "type" "patterns" "src" "outputs/${design_name}.atpg.stil" "dst" "releases/ATPG_PREPD_EXIT/${design_name}.atpg.stil" }
    "coverage"       { "type" "report"   "src" "reports/atpg/coverage.rpt"         "dst" "releases/ATPG_PREPD_EXIT/coverage.rpt" }
}
