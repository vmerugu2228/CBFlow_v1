# ═══════════════════════════════════════════════════════════════════════════════
# PV_SIGNOFF Milestone Configuration
# PV Signoff — DRC/LVS/ERC clean for tapeout readiness
# Stage: merge_data1 (PV flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "PV_SIGNOFF"
set milestone_info(stage)       "merge_data"
set milestone_info(description) "PV Signoff - DRC/LVS/ERC clean"
set milestone_info(stage_node)  "merge_data1"
set milestone_info(report_dir)  "work/PV/merge_data1/reports"

# ── Check packs ─────────────────────────────────────────────────────────────
array set check_packs {
    pv_flow         "0"
    manufacturing   "2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "pv_drc_clean" {
        "script"      "check_drc.tcl"
        "description" "DRC clean — zero violations"
        "criteria"    "grep drc_summary.rpt for Total.*0"
        "min_phase_index"   "0"
        "report_file" "work/PV/drc1/reports/drc_summary.rpt"
    }
    "pv_lvs_match" {
        "script"      "check_lvs.tcl"
        "description" "LVS layout vs schematic match"
        "criteria"    "grep lvs_summary.rpt for MATCH"
        "min_phase_index"   "0"
        "report_file" "work/PV/lvs1/reports/lvs_summary.rpt"
    }
    "pv_erc_clean" {
        "script"      "check_erc.tcl"
        "description" "ERC electrical rule check clean"
        "criteria"    "erc_violations == 0"
        "min_phase_index"   "1"
        "report_file" "work/PV/erc1/reports/erc_summary.rpt"
    }
    "pv_verification_complete" {
        "script"      "check_file_exists.tcl"
        "description" "All PV verification stages completed"
        "criteria"    "all verification reports exist"
        "min_phase_index"   "0"
        "report_file" "work/PV/merge_data1/reports/pv_status.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "pv_perc_clean" {
        "script"      "check_file_exists.tcl"
        "description" "PERC reliability check clean"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/PV/perc1/reports/perc_summary.rpt"
    }
    "pv_fill_density" {
        "script"      "check_file_exists.tcl"
        "description" "Metal fill density within foundry limits"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/PV/fill1/reports/fill_density.rpt"
    }
    "pv_xor_clean" {
        "script"      "check_file_exists.tcl"
        "description" "XOR check between revisions clean"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "work/PV/xor1/reports/xor_summary.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/PV/drc1/reports/drc_summary.rpt"
    "work/PV/lvs1/reports/lvs_summary.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "drc_summary" {
        "source" "work/PV/drc1/reports/drc_summary.rpt"
        "target" "releases/PV_SIGNOFF/drc_summary.rpt"
        "type"   "verification"
    }
    "lvs_summary" {
        "source" "work/PV/lvs1/reports/lvs_summary.rpt"
        "target" "releases/PV_SIGNOFF/lvs_summary.rpt"
        "type"   "verification"
    }
    "erc_summary" {
        "source" "work/PV/erc1/reports/erc_summary.rpt"
        "target" "releases/PV_SIGNOFF/erc_summary.rpt"
        "type"   "verification"
    }
    "pv_status" {
        "source" "work/PV/merge_data1/reports/pv_status.rpt"
        "target" "releases/PV_SIGNOFF/pv_status.rpt"
        "type"   "report"
    }
}
