# ═══════════════════════════════════════════════════════════════════════════════
# STA_SIGNOFF Milestone Configuration
# STA Signoff — All timing scenarios pass across all MMMC views
# Stage: timing1 (STA flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "STA_SIGNOFF"
set milestone_info(stage)       "timing"
set milestone_info(description) "STA Signoff - All timing scenarios pass"
set milestone_info(stage_node)  "timing1"
set milestone_info(report_dir)  "work/STA/timing1/reports"

# ── Check packs ─────────────────────────────────────────────────────────────
array set check_packs {
    sta_flow     "P0"
    timing       "P1"
    si           "P2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "sta_all_scenarios_pass" {
        "script"      "check_timing.tcl"
        "description" "All MMMC timing scenarios pass"
        "criteria"    "grep mmmc_timing_summary.rpt for All.*PASS"
        "min_phase"   "P0"
        "report_file" "work/STA/timing1/reports/mmmc_timing_summary.rpt"
    }
    "sta_setup_clean" {
        "script"      "check_timing.tcl"
        "description" "Setup timing clean — WNS >= 0 across all corners"
        "criteria"    "setup_wns >= 0"
        "min_phase"   "P0"
        "report_file" "work/STA/timing1/reports/report_timing.max.rpt"
    }
    "sta_hold_clean" {
        "script"      "check_timing.tcl"
        "description" "Hold timing clean — WNS >= 0 across all corners"
        "criteria"    "hold_wns >= 0"
        "min_phase"   "P1"
        "report_file" "work/STA/timing1/reports/report_timing.min.rpt"
    }
    "sta_constraints_complete" {
        "script"      "check_constraints.tcl"
        "description" "All timing constraints fully defined"
        "criteria"    "check_timing.rpt shows no unconstrained paths"
        "min_phase"   "P1"
        "report_file" "work/STA/timing1/reports/check_timing.rpt"
    }
    "sta_qor_report" {
        "script"      "check_file_exists.tcl"
        "description" "STA QoR report generated"
        "criteria"    "report exists and parseable"
        "min_phase"   "P0"
        "report_file" "work/STA/merge_reports1/reports/report_qor.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "sta_power_report" {
        "script"      "check_file_exists.tcl"
        "description" "STA power analysis report"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/STA/timing1/reports/report_power.rpt"
    }
    "sta_si_report" {
        "script"      "check_signal_integrity.tcl"
        "description" "Signal integrity crosstalk report"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/STA/timing1/reports/report_si.rpt"
    }
    "sta_sdf_generated" {
        "script"      "check_file_exists.tcl"
        "description" "SDF delay annotation file generated"
        "criteria"    "file exists"
        "min_phase"   "P3"
        "report_file" "work/STA/timing1/outputs/timing.sdf"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/STA/timing1/reports/mmmc_timing_summary.rpt"
    "work/STA/merge_reports1/reports/report_qor.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "timing_summary" {
        "source" "work/STA/timing1/reports/mmmc_timing_summary.rpt"
        "target" "releases/STA_SIGNOFF/mmmc_timing_summary.rpt"
        "type"   "report"
    }
    "qor_report" {
        "source" "work/STA/merge_reports1/reports/report_qor.rpt"
        "target" "releases/STA_SIGNOFF/report_qor.rpt"
        "type"   "report"
    }
    "setup_timing" {
        "source" "work/STA/timing1/reports/report_timing.max.rpt"
        "target" "releases/STA_SIGNOFF/report_timing.max.rpt"
        "type"   "report"
    }
    "hold_timing" {
        "source" "work/STA/timing1/reports/report_timing.min.rpt"
        "target" "releases/STA_SIGNOFF/report_timing.min.rpt"
        "type"   "report"
    }
    "constraint_check" {
        "source" "work/STA/timing1/reports/check_timing.rpt"
        "target" "releases/STA_SIGNOFF/check_timing.rpt"
        "type"   "verification"
    }
}
