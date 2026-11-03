# ═══════════════════════════════════════════════════════════════════════════════
# SCAN_INSERT_EXIT Milestone Configuration
# Scan Insertion Exit — scan chain stitching + scan mode definition complete
# Stage: scan_stitch1 (SCAN_INSERT flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "SCAN_INSERT_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(stage)       "scan_stitch"
set milestone_info(description) "Scan Insertion Exit — scan chains stitched, modes defined, verified"
set milestone_info(stage_node)  "scan_stitch1"
set milestone_info(report_dir)  "reports/scan_insert"
set milestone_info(owner)       "Madiha"

array set check_packs {}

array set mandatory_checks {
    "scan_stitched_netlist" {
        "script"            "check_file_exists.tcl"
        "description"       "Scan-stitched netlist exists"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.scan.v"
    }
    "scan_def" {
        "script"            "check_file_exists.tcl"
        "description"       "Scan DEF (scandef) present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.scandef"
    }
    "scan_check_report" {
        "script"            "check_file_exists.tcl"
        "description"       "Scan chain check report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/scan_insert/scan_check.rpt"
    }
}

array set optional_checks {
    "scan_coverage_pct" {
        "script"            "check_metric.tcl"
        "description"       "Scan chain coverage >= 95%"
        "criteria"          "scan_coverage_pct >= 95"
        "min_phase_index"   "0"
        "metric_name"       "scan_coverage_pct"
        "operator"          ">="
        "default_threshold" "95"
    }
}

set mandatory_files [list \
    "outputs/${design_name}.scan.v" \
    "outputs/${design_name}.scandef" \
    "reports/scan_insert/scan_check.rpt" \
]

array set deliverables {
    "scan_netlist"  { "type" "netlist" "src" "outputs/${design_name}.scan.v"       "dst" "releases/SCAN_INSERT_EXIT/${design_name}.scan.v" }
    "scandef"       { "type" "scandef" "src" "outputs/${design_name}.scandef"      "dst" "releases/SCAN_INSERT_EXIT/${design_name}.scandef" }
    "scan_report"   { "type" "report"  "src" "reports/scan_insert/scan_check.rpt"  "dst" "releases/SCAN_INSERT_EXIT/scan_check.rpt" }
}
