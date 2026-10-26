# ═══════════════════════════════════════════════════════════════════════════════
# CTS_EXIT Milestone Configuration
# Clock Tree Synthesis Exit — Design ready for Routing
# Stage: cts_opt1 (SYNTH_PNR flow), also references cts1 for clock reports
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "CTS_EXIT"
set milestone_info(stage)       "cts_opt"
set milestone_info(description) "Clock Tree Synthesis Exit - Design ready for Routing"
set milestone_info(stage_node)  "cts_opt1"
set milestone_info(report_dir)  "work/SYNTH_PNR/cts_opt1/reports"

# ── Check packs ──────────────────────────────────────────────────────────
array set check_packs {
    timing      "0"
    placement   "0"
    clock       "0"
    power       "1"
    physical    "1"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "cts_clock_qor" {
        "script"      "check_clock_quality.tcl"
        "description" "Clock tree quality — skew, insertion delay"
        "criteria"    "clock_skew <= threshold"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt"
    }
    "cts_opt_qor" {
        "script"      "check_timing.tcl"
        "description" "Post-CTS optimization QoR"
        "criteria"    "report exists and parseable"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt"
    }
    "cts_setup_timing" {
        "script"      "check_timing.tcl"
        "description" "Post-CTS setup timing"
        "criteria"    "setup_wns >= threshold"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt"
    }
    "cts_clock_timing" {
        "script"      "check_clock_quality.tcl"
        "description" "Clock timing — setup slack on clock paths"
        "criteria"    "clock setup timing clean"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/cts1/reports/report_clock_timing.setup.rpt"
    }
    "cts_hold_timing" {
        "script"      "check_timing.tcl"
        "description" "Post-CTS hold timing"
        "criteria"    "hold_wns >= threshold"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_timing.min.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "cts_power" {
        "script"      "check_power.tcl"
        "description" "Clock power consumption"
        "criteria"    "clock_power <= budget"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_power.rpt"
    }
    "cts_congestion" {
        "script"      "check_congestion.tcl"
        "description" "Congestion impact from clock tree"
        "criteria"    "congestion <= threshold"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_congestion.rpt"
    }
    "cts_vt_group" {
        "script"      "check_file_exists.tcl"
        "description" "Threshold voltage group distribution"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/report_threshold_voltage_group.rpt"
    }
    "cts_legality" {
        "script"      "check_legality.tcl"
        "description" "Post-CTS cell legality"
        "criteria"    "illegal_cells == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/check_legality.rpt"
    }
    "cts_constraint_check" {
        "script"      "check_constraints.tcl"
        "description" "Constraint completeness after CTS"
        "criteria"    "constraint violations == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/cts_opt1/reports/check_timing.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/SYNTH_PNR/cts_opt1/run/cts_opt1.nlib"
    "work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt"
    "work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "cts_db" {
        "source" "work/SYNTH_PNR/cts_opt1/run/cts_opt1.nlib"
        "target" "releases/CTS_EXIT/cts_opt1.nlib"
        "type"   "design_db"
    }
    "qor_report" {
        "source" "work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt"
        "target" "releases/CTS_EXIT/report_qor.rpt"
        "type"   "report"
    }
    "clock_qor_report" {
        "source" "work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt"
        "target" "releases/CTS_EXIT/report_clock_qor.rpt"
        "type"   "report"
    }
    "timing_report" {
        "source" "work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt"
        "target" "releases/CTS_EXIT/report_timing.max.rpt"
        "type"   "report"
    }
    "power_report" {
        "source" "work/SYNTH_PNR/cts_opt1/reports/report_power.rpt"
        "target" "releases/CTS_EXIT/report_power.rpt"
        "type"   "report"
    }
}
