# ═══════════════════════════════════════════════════════════════════════════════
# BTO Milestone Configuration
# Backend Tape Out — Design ready for Physical Verification signoff
# Stage: signoff1 (SYNTH_PNR flow) + cross-flow checks (STA, LEC, PV, CLP)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "BTO"
set milestone_info(stage)       "signoff"
set milestone_info(description) "Backend Tape Out - Design ready for mask generation"
set milestone_info(stage_node)  "signoff1"
set milestone_info(report_dir)  "work/SYNTH_PNR/signoff1/reports"

# ── Check packs — all categories active for BTO ──────────────────────────
array set check_packs {
    timing         "P0"
    placement      "P0"
    clock          "P0"
    power          "P1"
    routing        "P0"
    physical       "P1"
    si             "P2"
    manufacturing  "P2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "bto_setup_timing" {
        "script"      "check_timing.tcl"
        "description" "Signoff setup timing — WNS >= 0 at P2+"
        "criteria"    "setup_wns >= threshold"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt"
    }
    "bto_qor" {
        "script"      "check_timing.tcl"
        "description" "Signoff QoR summary"
        "criteria"    "report exists and parseable"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_qor.rpt"
    }
    "bto_routing" {
        "script"      "check_routing.tcl"
        "description" "Final route check — zero opens/shorts"
        "criteria"    "opens == 0 && shorts == 0"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/signoff1/reports/check_routes.final"
    }
    "bto_hold_timing" {
        "script"      "check_timing.tcl"
        "description" "Signoff hold timing — WNS >= 0 at P2+"
        "criteria"    "hold_wns >= threshold"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_timing.min.rpt"
    }
    "bto_signoff_drc" {
        "script"      "check_drc.tcl"
        "description" "Signoff DRC — zero violations"
        "criteria"    "drc_violations == 0"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt"
    }
    "bto_power" {
        "script"      "check_power.tcl"
        "description" "Signoff power analysis"
        "criteria"    "total_power <= budget"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_power.rpt"
    }
    "bto_si" {
        "script"      "check_signal_integrity.tcl"
        "description" "Signal integrity — crosstalk clean"
        "criteria"    "si_violations == 0"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_si.rpt"
    }
    "bto_legality" {
        "script"      "check_legality.tcl"
        "description" "Final cell legality"
        "criteria"    "illegal_cells == 0"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/check_legality.rpt"
    }
    "bto_constraint_check" {
        "script"      "check_constraints.tcl"
        "description" "All constraint checks pass"
        "criteria"    "constraint violations == 0"
        "min_phase"   "P3"
        "report_file" "work/SYNTH_PNR/signoff1/reports/check_timing.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "bto_qor_summary" {
        "script"      "check_file_exists.tcl"
        "description" "QoR summary condensed"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_qor_summary.rpt"
    }
    "bto_vt_group" {
        "script"      "check_file_exists.tcl"
        "description" "Threshold voltage group distribution"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_threshold_voltage_group.rpt"
    }
    "bto_utilization" {
        "script"      "check_utilization.tcl"
        "description" "Final area utilization"
        "criteria"    "utilization within range"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/signoff1/reports/report_utilization.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
# Progressive: P0 core files, P2+ additional netlists
set mandatory_files {
    "work/SYNTH_PNR/signoff1/run/signoff1.nlib"
    "work/SYNTH_PNR/signoff1/reports/report_qor.rpt"
    "work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt"
    "outputs/${design_name}.v"
    "outputs/${design_name}.def"
    "outputs/${design_name}.gds"
    "outputs/${design_name}.lef"
    "outputs/${design_name}.nlib"
    "outputs/${design_name}.enc"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "signoff_db" {
        "source" "work/SYNTH_PNR/signoff1/run/signoff1.nlib"
        "target" "releases/BTO/signoff1.nlib"
        "type"   "design_db"
    }
    "gds" {
        "source" "outputs/${design_name}.gds"
        "target" "releases/BTO/${design_name}.gds"
        "type"   "layout"
    }
    "netlist" {
        "source" "outputs/${design_name}.v"
        "target" "releases/BTO/${design_name}.v"
        "type"   "netlist"
    }
    "def" {
        "source" "outputs/${design_name}.def"
        "target" "releases/BTO/${design_name}.def"
        "type"   "physical"
    }
    "lef" {
        "source" "outputs/${design_name}.lef"
        "target" "releases/BTO/${design_name}.lef"
        "type"   "abstract"
    }
    "pt_netlist" {
        "source" "outputs/${design_name}.pt.v"
        "target" "releases/BTO/${design_name}.pt.v"
        "type"   "netlist"
    }
    "fm_netlist" {
        "source" "outputs/${design_name}.fm.v"
        "target" "releases/BTO/${design_name}.fm.v"
        "type"   "netlist"
    }
    "qor_report" {
        "source" "work/SYNTH_PNR/signoff1/reports/report_qor.rpt"
        "target" "releases/BTO/report_qor.rpt"
        "type"   "report"
    }
    "drc_report" {
        "source" "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt"
        "target" "releases/BTO/signoff_check_drc.rpt"
        "type"   "verification"
    }
    "timing_report" {
        "source" "work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt"
        "target" "releases/BTO/report_timing.max.rpt"
        "type"   "report"
    }
    "power_report" {
        "source" "work/SYNTH_PNR/signoff1/reports/report_power.rpt"
        "target" "releases/BTO/report_power.rpt"
        "type"   "report"
    }
}
