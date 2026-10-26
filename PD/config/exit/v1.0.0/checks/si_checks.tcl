##############################################################################
# Signal Integrity Check Library
# CBflow v2.0.0 — Exit Milestone Checks
##############################################################################

array set si_checks {
    "crosstalk_delay" {
        "description"             "Crosstalk-induced delay violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_si.rpt"
        "metric_pattern"          "Total crosstalk delay violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "crosstalk_noise" {
        "description"             "Crosstalk noise violations (DC)"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_noise.rpt"
        "metric_pattern"          "Total noise violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "glitch_violations" {
        "description"             "Glitch propagation violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_noise.rpt"
        "metric_pattern"          "Glitch propagation violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "coupling_cap_ratio" {
        "description"             "Max coupling cap to total cap ratio"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_crosstalk.rpt"
        "metric_pattern"          "Max coupling ratio\\s*:\\s*([0-9.]+)"
        "operator"                "<="
        "default_threshold"       "0.35"
    }
    "aggressor_count" {
        "description"             "Nets with excessive aggressors"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_crosstalk.rpt"
        "metric_pattern"          "Nets with excessive aggressors\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "victim_slack_degradation" {
        "description"             "Timing degradation from SI effects"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_si.rpt"
        "metric_pattern"          "Max slack degradation\\s*:\\s*([0-9.]+)"
        "operator"                "<="
        "default_threshold"       "0.050"
    }
    "si_hold_violations" {
        "description"             "SI-induced hold timing violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          "SI hold violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "si_setup_violations" {
        "description"             "SI-induced setup timing violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          "SI setup violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "noise_margin" {
        "description"             "Worst noise margin remaining"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_noise.rpt"
        "metric_pattern"          "Worst noise margin\\s*:\\s*([0-9.]+)"
        "operator"                ">="
        "default_threshold"       "0.10"
    }
    "shielding_effectiveness" {
        "description"             "Shield net effectiveness percentage"
        "script"                  "check_utilization.tcl"
        "category"                "signal_integrity"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_si.rpt"
        "metric_pattern"          "Shielding effectiveness\\s*:\\s*([0-9.]+)%"
        "operator"                ">="
        "default_threshold"       "90.0"
    }
    "si_aware_timing_delta" {
        "description"             "SI vs non-SI timing delta"
        "script"                  "check_timing.tcl"
        "category"                "signal_integrity"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          "SI timing delta\\s*:\\s*([0-9.]+)"
        "operator"                "<="
        "default_threshold"       "0.100"
    }
    "bus_crosstalk" {
        "description"             "Bus self-coupling analysis violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_crosstalk.rpt"
        "metric_pattern"          "Bus coupling violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "clock_si_impact" {
        "description"             "SI impact on clock network"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_si.rpt"
        "metric_pattern"          "Clock SI violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_rail_noise" {
        "description"             "Power rail noise coupling violations"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_noise.rpt"
        "metric_pattern"          "Power rail noise violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "simultaneous_switching" {
        "description"             "SSO/SSN simultaneous switching analysis"
        "script"                  "check_signal_integrity.tcl"
        "category"                "signal_integrity"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_noise.rpt"
        "metric_pattern"          "SSO violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
}
