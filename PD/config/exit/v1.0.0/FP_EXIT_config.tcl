# ═══════════════════════════════════════════════════════════════════════════════
# FP_EXIT Milestone Configuration
# Floorplan Exit — Design ready for placement
# Stage: init_design1 (SYNTH_PNR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "FP_EXIT"
set milestone_info(stage)       "init_design"
set milestone_info(description) "Floorplan Exit - Design ready for placement"
set milestone_info(stage_node)  "init_design1"
set milestone_info(report_dir)  "work/SYNTH_PNR/init_design1/reports"

# ── Check packs — which check library categories to activate ──────────────
# Format: category → min_phase when this category starts applying to this milestone
array set check_packs {
    timing      "P0"
    placement   "P0"
    clock       "P1"
    power       "P1"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "fp_qor" {
        "script"      "check_timing.tcl"
        "description" "QoR summary — WNS/TNS/area/power snapshot"
        "criteria"    "report exists and parseable"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_qor.rpt"
    }
    "fp_utilization" {
        "script"      "check_utilization.tcl"
        "description" "Floorplan utilization within target range"
        "criteria"    "utilization >= utilization_min && utilization <= utilization_max"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_utilization.rpt"
    }
    "fp_design_summary" {
        "script"      "check_file_exists.tcl"
        "description" "Design summary report exists"
        "criteria"    "file exists"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_design.rpt"
    }
    "fp_clock_definitions" {
        "script"      "check_file_exists.tcl"
        "description" "Clock definitions report — all clocks defined"
        "criteria"    "file exists"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_clocks.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "fp_timing_estimate" {
        "script"      "check_timing.tcl"
        "description" "Early timing estimation after floorplan"
        "criteria"    "setup_wns >= threshold"
        "min_phase"   "P0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_timing.max.rpt"
    }
    "fp_constraint_check" {
        "script"      "check_file_exists.tcl"
        "description" "Constraint completeness check"
        "criteria"    "file exists"
        "min_phase"   "P1"
        "report_file" "work/SYNTH_PNR/init_design1/reports/check_timing.rpt"
    }
    "fp_floorplan_rules" {
        "script"      "check_file_exists.tcl"
        "description" "Floorplan design rule check"
        "criteria"    "file exists"
        "min_phase"   "P2"
        "report_file" "work/SYNTH_PNR/init_design1/reports/check_floorplan_rules.rpt"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "work/SYNTH_PNR/init_design1/run/init_design1.nlib"
    "work/SYNTH_PNR/init_design1/reports/report_qor.rpt"
    "work/SYNTH_PNR/init_design1/reports/report_utilization.rpt"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "floorplan_db" {
        "source" "work/SYNTH_PNR/init_design1/run/init_design1.nlib"
        "target" "releases/FP_EXIT/init_design1.nlib"
        "type"   "design_db"
    }
    "qor_report" {
        "source" "work/SYNTH_PNR/init_design1/reports/report_qor.rpt"
        "target" "releases/FP_EXIT/report_qor.rpt"
        "type"   "report"
    }
    "utilization_report" {
        "source" "work/SYNTH_PNR/init_design1/reports/report_utilization.rpt"
        "target" "releases/FP_EXIT/report_utilization.rpt"
        "type"   "report"
    }
}
