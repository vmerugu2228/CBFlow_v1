# ═══════════════════════════════════════════════════════════════════════════════
# PLACE_EXIT Milestone Configuration
# Placement Exit — Design ready for Clock Tree Synthesis (CTS)
# Stage: place1 (SYNTH_PNR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "PLACE_EXIT"
set milestone_info(stage)       "place"
set milestone_info(description) "Placement Exit - Design ready for Clock Tree Synthesis"
set milestone_info(stage_node)  "place1"
set milestone_info(report_dir)  "work/SYNTH_PNR/place1/reports"

# ── Check packs ──────────────────────────────────────────────────────────
array set check_packs {
    timing      "0"
    placement   "0"
    clock       "1"
    power       "1"
    physical    "1"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "place_legality" {
        "script"      "check_legality.tcl"
        "description" "All cells legally placed — zero illegal cells"
        "criteria"    "illegal_cells == 0"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/place1/reports/check_legality.rpt"
    }
    "place_setup_timing" {
        "script"      "check_timing.tcl"
        "description" "Setup WNS meets phase threshold"
        "criteria"    "setup_wns >= threshold"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/place1/reports/report_timing.max.rpt"
    }
    "place_qor" {
        "script"      "check_timing.tcl"
        "description" "QoR summary — WNS/TNS/area/power"
        "criteria"    "report exists and parseable"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/place1/reports/report_qor.rpt"
    }
    "place_congestion" {
        "script"      "check_congestion.tcl"
        "description" "Congestion within acceptable limits"
        "criteria"    "max_congestion <= threshold"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/place1/reports/report_congestion.rpt"
    }
    "place_hold_timing" {
        "script"      "check_timing.tcl"
        "description" "Hold WNS meets phase threshold"
        "criteria"    "hold_wns >= threshold"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/place1/reports/report_timing.min.rpt"
    }
    "place_power" {
        "script"      "check_power.tcl"
        "description" "Power consumption within budget"
        "criteria"    "total_power <= power_budget"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/place1/reports/report_power.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "place_utilization" {
        "script"      "check_utilization.tcl"
        "description" "Placement utilization within target"
        "criteria"    "utilization within range"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/place1/reports/report_utilization.rpt"
    }
    "place_qor_summary" {
        "script"      "check_file_exists.tcl"
        "description" "QoR summary report generated"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/place1/reports/report_qor_summary.rpt"
    }
    "place_vt_group" {
        "script"      "check_file_exists.tcl"
        "description" "Threshold voltage group distribution"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/place1/reports/report_threshold_voltage_group.rpt"
    }
    "place_constraint_check" {
        "script"      "check_constraints.tcl"
        "description" "Max cap/tran/fanout constraint check"
        "criteria"    "constraint violations == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/place1/reports/check_timing.rpt"
    }
    "place_signoff_drc" {
        "script"      "check_drc.tcl"
        "description" "Early signoff DRC check"
        "criteria"    "drc_violations <= threshold"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/place1/reports/signoff_check_drc.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/SYNTH_PNR/place1/run/place1.nlib"
    "work/SYNTH_PNR/place1/reports/report_qor.rpt"
    "work/SYNTH_PNR/place1/reports/report_timing.max.rpt"
    "work/SYNTH_PNR/place1/reports/report_congestion.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "placement_db" {
        "source" "work/SYNTH_PNR/place1/run/place1.nlib"
        "target" "releases/PLACE_EXIT/place1.nlib"
        "type"   "design_db"
    }
    "qor_report" {
        "source" "work/SYNTH_PNR/place1/reports/report_qor.rpt"
        "target" "releases/PLACE_EXIT/report_qor.rpt"
        "type"   "report"
    }
    "timing_report" {
        "source" "work/SYNTH_PNR/place1/reports/report_timing.max.rpt"
        "target" "releases/PLACE_EXIT/report_timing.max.rpt"
        "type"   "report"
    }
    "congestion_report" {
        "source" "work/SYNTH_PNR/place1/reports/report_congestion.rpt"
        "target" "releases/PLACE_EXIT/report_congestion.rpt"
        "type"   "report"
    }
    "power_report" {
        "source" "work/SYNTH_PNR/place1/reports/report_power.rpt"
        "target" "releases/PLACE_EXIT/report_power.rpt"
        "type"   "report"
    }
}
