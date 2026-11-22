# ═══════════════════════════════════════════════════════════════════════════════
# PRO_EXIT Milestone Configuration
# Post Route Optimization Exit — Design ready for Physical Verification
# Stage: pro1 (SYNTH_PNR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "PRO_EXIT"
set milestone_info(discipline) "PD"
set milestone_info(flow_type)   "PNR"
set milestone_info(stage)       "pro"
set milestone_info(description) "Post Route Optimization Exit - Design ready for Physical Verification"
set milestone_info(stage_node)  "pro1"
set milestone_info(report_dir)  "work/SYNTH_PNR/pro1/reports"

# ── Check packs ──────────────────────────────────────────────────────────
array set check_packs {
    timing      "0"
    placement   "0"
    clock       "0"
    power       "1"
    routing     "0"
    physical    "1"
    si          "2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "pro_routing" {
        "id"          "PNR_0022"
        "script"      "check_routing.tcl"
        "description" "Opens and shorts after route"
        "criteria"    "routing_completion == 100% && opens == 0 && shorts == 0"
        "operator"    "=="
        "default_threshold" "0"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_routes"
    }
    "pro_setup_timing" {
        "id"          "PNR_0023"
        "script"      "check_timing.tcl"
        "description" "Post-route setup slack (WNS)"
        "criteria"    "setup_wns >= threshold"
        "unit"        "ns"
        "operator"    ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_timing.max.rpt"
    }
    "pro_qor" {
        "id"          "PNR_0024"
        "script"      "check_timing.tcl"
        "description" "Post-route QoR summary"
        "criteria"    "report exists and parseable"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_qor.rpt"
    }
    "pro_hold_timing" {
        "id"          "PNR_0025"
        "script"      "check_timing.tcl"
        "description" "Post-route hold slack (WNS)"
        "criteria"    "hold_wns >= threshold"
        "unit"        "ns"
        "operator"    ">="
        "default_threshold" "0"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_timing.min.rpt"
    }
    "pro_power" {
        "id"          "PNR_0026"
        "script"      "check_power.tcl"
        "description" "Post-route power within budget"
        "criteria"    "total_power <= power_budget"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_power.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "pro_congestion" {
        "id"          "PNR_0027"
        "script"      "check_congestion.tcl"
        "description" "Post-route congestion"
        "criteria"    "congestion <= threshold"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_congestion.rpt"
    }
    "pro_signal_integrity" {
        "id"          "PNR_0028"
        "script"      "check_signal_integrity.tcl"
        "description" "Crosstalk (SI) violations"
        "criteria"    "si_violations == 0"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_si.rpt"
    }
    "pro_qor_summary" {
        "id"          "PNR_0029"
        "script"      "check_file_exists.tcl"
        "description" "QoR summary condensed report"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_qor_summary.rpt"
    }
    "pro_vt_group" {
        "id"          "PNR_0030"
        "script"      "check_file_exists.tcl"
        "description" "Threshold-voltage (VT) group mix"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "work/SYNTH_PNR/pro1/reports/report_threshold_voltage_group.rpt"
    }
    "pro_legality" {
        "id"          "PNR_0031"
        "script"      "check_legality.tcl"
        "description" "Final cell legality check"
        "criteria"    "illegal_cells == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_legality.rpt"
    }
    "pro_constraint_check" {
        "id"          "PNR_0032"
        "script"      "check_constraints.tcl"
        "description" "Max cap/tran/fanout constraint compliance"
        "criteria"    "constraint violations == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/pro1/reports/check_timing.rpt"
    }
    "pro_signoff_drc" {
        "id"          "PNR_0033"
        "script"      "check_drc.tcl"
        "description" "In-design signoff DRC"
        "criteria"    "drc_violations == 0"
        "min_phase_index"   "3"
        "report_file" "work/SYNTH_PNR/pro1/reports/signoff_check_drc.rpt"
    }
    "pro_routes_final" {
        "id"          "PNR_0034"
        "script"      "check_routing.tcl"
        "description" "Violations after final route"
        "criteria"    "route_violations == 0"
        "min_phase_index"   "3"
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
