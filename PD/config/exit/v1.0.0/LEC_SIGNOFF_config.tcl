# ═══════════════════════════════════════════════════════════════════════════════
# LEC_SIGNOFF Milestone Configuration
# LEC Signoff — Formal equivalence verified between RTL and netlist
# Stage: compare1 (LEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "LEC_SIGNOFF"
set milestone_info(stage)       "compare"
set milestone_info(description) "LEC Signoff - Formal equivalence verified"
set milestone_info(stage_node)  "compare1"
set milestone_info(report_dir)  "work/LEC/compare1/reports"

# ── Check packs ─────────────────────────────────────────────────────────────
array set check_packs {
    lec_flow    "P0"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "lec_equivalence_pass" {
        "script"      "check_lec.tcl"
        "description" "Formal equivalence check passed"
        "criteria"    "grep comparison_summary.rpt for SUCCEEDED"
        "min_phase"   "P0"
        "report_file" "work/LEC/compare1/reports/comparison_summary.rpt"
    }
    "lec_zero_failures" {
        "script"      "check_lec.tcl"
        "description" "Zero non-equivalent points"
        "criteria"    "failing_points == 0"
        "min_phase"   "P0"
        "report_file" "work/LEC/compare1/reports/comparison_summary.rpt"
    }
    "lec_netlist_read_clean" {
        "script"      "check_lec.tcl"
        "description" "Netlist read without errors"
        "criteria"    "read errors == 0"
        "min_phase"   "P0"
        "report_file" "work/LEC/compare1/reports/read_design.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "lec_datapath_verify" {
        "script"      "check_file_exists.tcl"
        "description" "Datapath equivalence verification"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/LEC/compare1/reports/datapath_verify.rpt"
    }
    "lec_svf_applied" {
        "script"      "check_file_exists.tcl"
        "description" "SVF guidance file applied successfully"
        "criteria"    "file exists"
        "min_phase"   "P1"
        "report_file" "work/LEC/compare1/reports/svf_status.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/LEC/compare1/reports/comparison_summary.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "comparison_summary" {
        "source" "work/LEC/compare1/reports/comparison_summary.rpt"
        "target" "releases/LEC_SIGNOFF/comparison_summary.rpt"
        "type"   "verification"
    }
    "read_design_report" {
        "source" "work/LEC/compare1/reports/read_design.rpt"
        "target" "releases/LEC_SIGNOFF/read_design.rpt"
        "type"   "report"
    }
}
