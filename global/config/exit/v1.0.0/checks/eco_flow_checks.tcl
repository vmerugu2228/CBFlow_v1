###############################################################################
# CBflow ECO Check Library
# Category: eco
# Version: 1.0.0
#
# Defines 12 ECO-related checks for exit milestone validation.
# Covers ECO implementation, timing impact, verification, and reporting.
# Used by the checklist engine to evaluate ECO quality at each milestone.
###############################################################################

array set eco_flow_checks {

    "eco_implementation" {
        "id"          "ECO_FLOW_0001"
        "description"             "ECO changes implemented successfully"
        "script"                  "check_file_exists.tcl"
        "category"                "eco"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {ECO\s+Implementation\s+Status\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "eco_netlist_generated" {
        "id"          "ECO_FLOW_0002"
        "description"             "Post-ECO netlist generated successfully"
        "script"                  "check_file_exists.tcl"
        "category"                "eco"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {Post-ECO\s+Netlist\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }

    "eco_timing_impact" {
        "id"          "ECO_FLOW_0003"
        "description"             "ECO timing impact must be within acceptable range"
        "script"                  "check_timing.tcl"
        "category"                "eco_timing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_timing.rpt"
        "metric_pattern"          {ECO\s+Setup\s+WNS\s+Impact\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "-0.050"
    }

    "eco_hold_impact" {
        "id"          "ECO_FLOW_0004"
        "description"             "ECO hold timing impact must be within acceptable range"
        "script"                  "check_timing.tcl"
        "category"                "eco_timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_timing.rpt"
        "metric_pattern"          {ECO\s+Hold\s+WNS\s+Impact\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "-0.020"
    }

    "eco_drc_clean" {
        "id"          "ECO_FLOW_0005"
        "description"             "Post-ECO DRC must be clean"
        "script"                  "check_drc.tcl"
        "category"                "eco_physical"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {Post-ECO\s+DRC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "eco_connectivity" {
        "id"          "ECO_FLOW_0006"
        "description"             "Post-ECO connectivity must be verified"
        "script"                  "check_legality.tcl"
        "category"                "eco_physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {Post-ECO\s+Connectivity\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "eco_legality" {
        "id"          "ECO_FLOW_0007"
        "description"             "Post-ECO cell placement must be legal"
        "script"                  "check_legality.tcl"
        "category"                "eco_physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {Post-ECO\s+Legality\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "eco_lec_verify" {
        "id"          "ECO_FLOW_0008"
        "description"             "Post-ECO LEC verification recommended"
        "script"                  "check_file_exists.tcl"
        "category"                "eco"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {Post-ECO\s+LEC\s+Status\s*:\s*(PASS|FAIL|PENDING)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "eco_spare_cell_usage" {
        "id"          "ECO_FLOW_0009"
        "description"             "Spare cells used vs available within acceptable ratio"
        "script"                  "check_utilization.tcl"
        "category"                "eco"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_changes.rpt"
        "metric_pattern"          {Spare\s+Cell\s+Usage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "80.0"
    }

    "eco_routing_complete" {
        "id"          "ECO_FLOW_0010"
        "description"             "ECO routing must be completed"
        "script"                  "check_routing.tcl"
        "category"                "eco_physical"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {ECO\s+Routing\s+Status\s*:\s*(COMPLETED|INCOMPLETE)}
        "operator"                "=="
        "default_threshold"       "COMPLETED"
    }

    "eco_changes_report" {
        "id"          "ECO_FLOW_0011"
        "description"             "ECO changes report generated"
        "script"                  "check_file_exists.tcl"
        "category"                "eco"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_changes.rpt"
        "metric_pattern"          {ECO\s+Changes\s+Report\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }

    "eco_summary_report" {
        "id"          "ECO_FLOW_0012"
        "description"             "Complete ECO summary report generated"
        "script"                  "check_file_exists.tcl"
        "category"                "eco"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "ECO_SIGNOFF"
        "report_pattern"          "eco_summary.rpt"
        "metric_pattern"          {ECO\s+Summary\s+Report\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }
}
