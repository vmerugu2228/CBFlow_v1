# ═══════════════════════════════════════════════════════════════════════════════
# EMIR_SIGNOFF Milestone Configuration
# EMIR Signoff — IR drop and EM within limits for power grid signoff
# Stage: ir_drop1 (EMIR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "EMIR_SIGNOFF"
set milestone_info(stage)       "ir_drop"
set milestone_info(description) "EMIR Signoff - IR drop and EM within limits"
set milestone_info(stage_node)  "ir_drop1"
set milestone_info(report_dir)  "work/EMIR/ir_drop1/reports"

# ── Check packs ─────────────────────────────────────────────────────────────
array set check_packs {
    emir_flow   "P0"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "emir_ir_drop_pass" {
        "script"      "check_emir.tcl"
        "description" "IR drop within specified limits"
        "criteria"    "grep ir_drop_summary.rpt for PASS"
        "min_phase"   "P1"
        "report_file" "work/EMIR/ir_drop1/reports/ir_drop_summary.rpt"
    }
    "emir_em_clean" {
        "script"      "check_emir.tcl"
        "description" "Electromigration check — zero violations"
        "criteria"    "grep em_summary.rpt for violations.*0"
        "min_phase"   "P2"
        "report_file" "work/EMIR/ir_drop1/reports/em_summary.rpt"
    }
    "emir_power_analysis" {
        "script"      "check_file_exists.tcl"
        "description" "Power analysis report generated"
        "criteria"    "report exists and parseable"
        "min_phase"   "P0"
        "report_file" "work/EMIR/power_analysis1/reports/power_summary.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "emir_thermal_check" {
        "script"      "check_file_exists.tcl"
        "description" "Thermal analysis within limits"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/EMIR/ir_drop1/reports/thermal_analysis.rpt"
    }
    "emir_dynamic_ir" {
        "script"      "check_file_exists.tcl"
        "description" "Dynamic IR drop analysis"
        "criteria"    "file exists"
        "min_phase"   "P3"
        "report_file" "work/EMIR/ir_drop1/reports/dynamic_ir_drop.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/EMIR/ir_drop1/reports/ir_drop_summary.rpt"
    "work/EMIR/power_analysis1/reports/power_summary.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "ir_drop_summary" {
        "source" "work/EMIR/ir_drop1/reports/ir_drop_summary.rpt"
        "target" "releases/EMIR_SIGNOFF/ir_drop_summary.rpt"
        "type"   "report"
    }
    "em_summary" {
        "source" "work/EMIR/ir_drop1/reports/em_summary.rpt"
        "target" "releases/EMIR_SIGNOFF/em_summary.rpt"
        "type"   "report"
    }
    "power_summary" {
        "source" "work/EMIR/power_analysis1/reports/power_summary.rpt"
        "target" "releases/EMIR_SIGNOFF/power_summary.rpt"
        "type"   "report"
    }
}
