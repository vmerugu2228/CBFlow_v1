# ═══════════════════════════════════════════════════════════════════════════════
# FP_EXIT Milestone Configuration
# Floorplan Exit — Design ready for placement
# Stage: init_design1 (SYNTH_PNR flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "FP_EXIT"
set milestone_info(discipline) "PD"
set milestone_info(flow_type)   "FP"
set milestone_info(stage)       "init_design"
set milestone_info(description) "Floorplan Exit - Design ready for placement"
set milestone_info(stage_node)  "init_design1"
set milestone_info(report_dir)  "work/SYNTH_PNR/init_design1/reports"

# ── Check packs — which check library categories to activate ──────────────
# Format: category → min_phase when this category starts applying to this milestone
array set check_packs {
    timing      "0"
    placement   "0"
    clock       "1"
    power       "1"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "fp_qor" {
        "id"          "FP_0001"
        "script"      "check_timing.tcl"
        "description" "QoR summary after floorplan (WNS/TNS/area)"
        "criteria"    "report exists and parseable"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_qor.rpt"
    }
    "fp_utilization" {
        "id"          "FP_0002"
        "script"      "check_utilization.tcl"
        "description" "Floorplan utilization within target range"
        "criteria"    "utilization >= utilization_min && utilization <= utilization_max"
        "unit"        "%"
        "operator"    "between"
        "default_threshold" "1,85"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_utilization.rpt"
    }
    "fp_design_summary" {
        "id"          "FP_0003"
        "script"      "check_file_exists.tcl"
        "description" "Design summary report exists"
        "criteria"    "file exists"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_design.rpt"
    }
    "fp_clock_definitions" {
        "id"          "FP_0004"
        "script"      "check_file_exists.tcl"
        "description" "Clock definitions report"
        "criteria"    "file exists"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_clocks.rpt"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "fp_timing_estimate" {
        "id"          "FP_0005"
        "script"      "check_timing.tcl"
        "description" "Early timing estimation after floorplan"
        "criteria"    "setup_wns >= threshold"
        "operator"    ">="
        "default_threshold" "0"
        "min_phase_index"   "0"
        "report_file" "work/SYNTH_PNR/init_design1/reports/report_timing.max.rpt"
    }
    "fp_constraint_check" {
        "id"          "FP_0006"
        "script"      "check_file_exists.tcl"
        "description" "Constraint completeness check"
        "criteria"    "file exists"
        "min_phase_index"   "1"
        "report_file" "work/SYNTH_PNR/init_design1/reports/check_timing.rpt"
    }
    "fp_floorplan_rules" {
        "id"          "FP_0007"
        "script"      "check_file_exists.tcl"
        "description" "Floorplan design rule check"
        "criteria"    "file exists"
        "min_phase_index"   "2"
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
