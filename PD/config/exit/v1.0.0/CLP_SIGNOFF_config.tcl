# ═══════════════════════════════════════════════════════════════════════════════
# CLP_SIGNOFF Milestone Configuration
# CLP Signoff — Power intent verification pass (UPF/CPF clean)
# Stage: clp1 (CLP flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "CLP_SIGNOFF"
set milestone_info(stage)       "clp"
set milestone_info(description) "CLP Signoff - Power intent verification pass"
set milestone_info(stage_node)  "clp1"
set milestone_info(report_dir)  "work/CLP/clp1/reports"

# ── Check packs ─────────────────────────────────────────────────────────────
array set check_packs {
    clp_flow    "0"
    power       "1"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "clp_all_checks_pass" {
        "script"      "check_clp.tcl"
        "description" "All power verification checks passed"
        "criteria"    "grep power_verification_summary.rpt for All.*PASSED"
        "min_phase_index"   "0"
        "report_file" "work/CLP/clp1/reports/power_verification_summary.rpt"
    }
    "clp_isolation_clean" {
        "script"      "check_clp.tcl"
        "description" "Isolation cell checks clean — no missing isolation"
        "criteria"    "isolation_violations == 0"
        "min_phase_index"   "0"
        "report_file" "work/CLP/clp1/reports/isolation_check.rpt"
    }
    "clp_level_shifter_clean" {
        "script"      "check_clp.tcl"
        "description" "Level shifter checks clean — no missing level shifters"
        "criteria"    "level_shifter_violations == 0"
        "min_phase_index"   "0"
        "report_file" "work/CLP/clp1/reports/level_shifter_check.rpt"
    }
    "clp_upf_clean" {
        "script"      "check_clp.tcl"
        "description" "UPF power intent read without errors"
        "criteria"    "upf_errors == 0"
        "min_phase_index"   "0"
        "report_file" "work/CLP/clp1/reports/upf_check.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "clp_retention_verify" {
        "script"      "check_file_exists.tcl"
        "description" "Retention register verification"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/CLP/clp1/reports/retention_verify.rpt"
    }
    "clp_power_state_complete" {
        "script"      "check_file_exists.tcl"
        "description" "All power states and transitions verified"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "work/CLP/clp1/reports/power_state_table.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/CLP/clp1/reports/power_verification_summary.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "power_verification_summary" {
        "source" "work/CLP/clp1/reports/power_verification_summary.rpt"
        "target" "releases/CLP_SIGNOFF/power_verification_summary.rpt"
        "type"   "verification"
    }
    "isolation_report" {
        "source" "work/CLP/clp1/reports/isolation_check.rpt"
        "target" "releases/CLP_SIGNOFF/isolation_check.rpt"
        "type"   "verification"
    }
    "level_shifter_report" {
        "source" "work/CLP/clp1/reports/level_shifter_check.rpt"
        "target" "releases/CLP_SIGNOFF/level_shifter_check.rpt"
        "type"   "verification"
    }
    "upf_report" {
        "source" "work/CLP/clp1/reports/upf_check.rpt"
        "target" "releases/CLP_SIGNOFF/upf_check.rpt"
        "type"   "verification"
    }
}
