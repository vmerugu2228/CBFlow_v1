# ═══════════════════════════════════════════════════════════════════════════════
# PRO_EXIT Milestone Configuration
# Post Route Optimization Exit — Design ready for Physical Verification
# Stage: pro1 (SYNTH_PNR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "PRO_EXIT"
set milestone_info(stage)       "pro"
set milestone_info(description) "Post Route Optimization Exit - Design ready for Physical Verification"
set milestone_info(stage_node)  "pro1"
set milestone_info(report_dir)  "work/SYNTH_PNR/pro1/reports"

# ── Check packs ──────────────────────────────────────────────────────────
array set check_packs {
    timing      "P0"
    placement   "P0"
    clock       "P0"
    power       "P1"
    routing     "P0"
    physical    "P1"
    si          "P2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "pro_routing" {
        "script"      "check_routing.tcl"
        "description" "Routing 100% complete — zero opens/shorts"
        "criteria"    "routing_completion == 100% && opens == 0 && shorts == 0"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_routes"
    }
    "pro_setup_timing" {
        "script"      "check_timing.tcl"
        "description" "Post-route setup timing meets threshold"
        "criteria"    "setup_wns >= threshold"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_timing.max.rpt"
    }
    "pro_qor" {
        "script"      "check_timing.tcl"
        "description" "Post-route QoR summary"
        "criteria"    "report exists and parseable"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_qor.rpt"
    }
    "pro_hold_timing" {
        "script"      "check_timing.tcl"
        "description" "Post-route hold timing meets threshold"
        "criteria"    "hold_wns >= threshold"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_timing.min.rpt"
    }
    "pro_power" {
        "script"      "check_power.tcl"
        "description" "Post-route power within budget"
        "criteria"    "total_power <= power_budget"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_power.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "pro_congestion" {
        "script"      "check_congestion.tcl"
        "description" "Post-route congestion"
        "criteria"    "congestion <= threshold"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_congestion.rpt"
    }
    "pro_signal_integrity" {
        "script"      "check_signal_integrity.tcl"
        "description" "Signal integrity — crosstalk violations"
        "criteria"    "si_violations == 0"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_si.rpt"
    }
    "pro_qor_summary" {
        "script"      "check_file_exists.tcl"
        "description" "QoR summary condensed report"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_qor_summary.rpt"
    }
    "pro_vt_group" {
        "script"      "check_file_exists.tcl"
        "description" "Threshold voltage group distribution"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_threshold_voltage_group.rpt"
    }
    "pro_legality" {
        "script"      "check_legality.tcl"
        "description" "Final cell legality check"
        "criteria"    "illegal_cells == 0"
        "min_phase"   "P3"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_legality.rpt"
    }
    "pro_constraint_check" {
        "script"      "check_constraints.tcl"
        "description" "Max cap/tran/fanout constraint compliance"
        "criteria"    "constraint violations == 0"
        "min_phase"   "P3"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_timing.rpt"
    }
    "pro_signoff_drc" {
        "script"      "check_drc.tcl"
        "description" "In-design signoff DRC"
        "criteria"    "drc_violations == 0"
        "min_phase"   "P3"
        "report_file" "work/SYNTH_PNR/pro1/reports/signoff_check_drc.rpt"
    }
    "pro_routes_final" {
        "script"      "check_routing.tcl"
        "description" "Final route check — zero violations"
        "criteria"    "route_violations == 0"
        "min_phase"   "P3"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_routes.final"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/SYNTH_PNR/pro1/run/pro1.nlib"
    "work/SYNTH_PNR/pro1/reports/report_qor.rpt"
    "work/SYNTH_PNR/pro1/reports/report_timing.max.rpt"
    "work/SYNTH_PNR/pro1/reports/report_timing.min.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "pro_db" {
        "source" "work/SYNTH_PNR/pro1/run/pro1.nlib"
        "target" "releases/PRO_EXIT/pro1.nlib"
        "type"   "design_db"
    }
    "netlist" {
        "source" "outputs/${design_name}.v"
        "target" "releases/PRO_EXIT/${design_name}.v"
        "type"   "netlist"
    }
    "def" {
        "source" "outputs/${design_name}.def"
        "target" "releases/PRO_EXIT/${design_name}.def"
        "type"   "physical"
    }
    "qor_report" {
        "source" "work/SYNTH_PNR/pro1/reports/report_qor.rpt"
        "target" "releases/PRO_EXIT/report_qor.rpt"
        "type"   "report"
    }
    "timing_setup_report" {
        "source" "work/SYNTH_PNR/pro1/reports/report_timing.max.rpt"
        "target" "releases/PRO_EXIT/report_timing.max.rpt"
        "type"   "report"
    }
    "timing_hold_report" {
        "source" "work/SYNTH_PNR/pro1/reports/report_timing.min.rpt"
        "target" "releases/PRO_EXIT/report_timing.min.rpt"
        "type"   "report"
    }
    "power_report" {
        "source" "work/SYNTH_PNR/pro1/reports/report_power.rpt"
        "target" "releases/PRO_EXIT/report_power.rpt"
        "type"   "report"
    }
}
