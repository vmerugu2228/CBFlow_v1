###############################################################################
# CBflow EMIR Check Library
# Category: emir
# Version: 1.0.0
#
# Defines 20 EMIR-related checks for exit milestone validation.
# Covers power analysis, IR drop, electromigration, thermal, and power mesh.
# Used by the checklist engine to evaluate EMIR quality at each milestone.
###############################################################################

array set emir_flow_checks {

    "emir_power_total" {
        "description"             "Total power must be within budget"
        "script"                  "check_power.tcl"
        "category"                "power_analysis"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {Total\s+Power\s*:\s*([0-9]+\.[0-9]+)\s*mW}
        "operator"                "<="
        "default_threshold"       "1000.0"
    }

    "emir_power_leakage" {
        "description"             "Leakage power must be within limit"
        "script"                  "check_power.tcl"
        "category"                "power_analysis"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {Leakage\s+Power\s*:\s*([0-9]+\.[0-9]+)\s*mW}
        "operator"                "<="
        "default_threshold"       "100.0"
    }

    "emir_power_dynamic" {
        "description"             "Dynamic power must be within limit"
        "script"                  "check_power.tcl"
        "category"                "power_analysis"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {Dynamic\s+Power\s*:\s*([0-9]+\.[0-9]+)\s*mW}
        "operator"                "<="
        "default_threshold"       "900.0"
    }

    "emir_power_clock" {
        "description"             "Clock power percentage must be acceptable"
        "script"                  "check_power.tcl"
        "category"                "power_analysis"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {Clock\s+Power\s+Ratio\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "40.0"
    }

    "emir_power_per_domain" {
        "description"             "Per-power-domain power must be within budget"
        "script"                  "check_power.tcl"
        "category"                "power_analysis"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {Domain\s+Power\s+Budget\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "emir_static_ir_vdd" {
        "description"             "Static VDD IR drop must be within threshold"
        "script"                  "check_power.tcl"
        "category"                "ir_drop"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {Static\s+VDD\s+IR\s+Drop\s*:\s*([0-9]+\.[0-9]+)\s*mV}
        "operator"                "<="
        "default_threshold"       "20.0"
    }

    "emir_static_ir_vss" {
        "description"             "Static VSS IR drop (ground bounce) must be within threshold"
        "script"                  "check_power.tcl"
        "category"                "ir_drop"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {Static\s+VSS\s+IR\s+Drop\s*:\s*([0-9]+\.[0-9]+)\s*mV}
        "operator"                "<="
        "default_threshold"       "20.0"
    }

    "emir_dynamic_ir" {
        "description"             "Dynamic IR drop must be within threshold"
        "script"                  "check_power.tcl"
        "category"                "ir_drop"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {Dynamic\s+IR\s+Drop\s*:\s*([0-9]+\.[0-9]+)\s*mV}
        "operator"                "<="
        "default_threshold"       "50.0"
    }

    "emir_ir_worst_instance" {
        "description"             "Worst instance voltage drop must be within margin"
        "script"                  "check_power.tcl"
        "category"                "ir_drop"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {Worst\s+Instance\s+Voltage\s+Drop\s*:\s*([0-9]+\.[0-9]+)\s*mV}
        "operator"                "<="
        "default_threshold"       "30.0"
    }

    "emir_ir_coverage" {
        "description"             "IR analysis coverage (percent of PG mesh analyzed)"
        "script"                  "check_utilization.tcl"
        "category"                "ir_drop"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {IR\s+Analysis\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "95.0"
    }

    "emir_em_signal" {
        "description"             "Signal EM violations must be zero"
        "script"                  "check_power.tcl"
        "category"                "em"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "em_summary.rpt"
        "metric_pattern"          {Signal\s+EM\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "emir_em_power" {
        "description"             "Power net EM violations must be zero"
        "script"                  "check_power.tcl"
        "category"                "em"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "em_summary.rpt"
        "metric_pattern"          {Power\s+Net\s+EM\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "emir_em_via" {
        "description"             "Via EM violations must be zero"
        "script"                  "check_power.tcl"
        "category"                "em"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "em_summary.rpt"
        "metric_pattern"          {Via\s+EM\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "emir_em_worst_ratio" {
        "description"             "Worst EM current ratio must be within limit"
        "script"                  "check_power.tcl"
        "category"                "em"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "em_summary.rpt"
        "metric_pattern"          {Worst\s+EM\s+Current\s+Ratio\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "1.0"
    }

    "emir_thermal_max" {
        "description"             "Max junction temperature must be within limit"
        "script"                  "check_file_exists.tcl"
        "category"                "thermal"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "thermal_summary.rpt"
        "metric_pattern"          {Max\s+Junction\s+Temperature\s*:\s*([0-9]+\.[0-9]+)\s*C}
        "operator"                "<="
        "default_threshold"       "125.0"
    }

    "emir_thermal_hotspot" {
        "description"             "Number of thermal hotspots must be within limit"
        "script"                  "check_file_exists.tcl"
        "category"                "thermal"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "thermal_summary.rpt"
        "metric_pattern"          {Thermal\s+Hotspots\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "emir_thermal_gradient" {
        "description"             "Thermal gradient must be within limit"
        "script"                  "check_file_exists.tcl"
        "category"                "thermal"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "thermal_summary.rpt"
        "metric_pattern"          {Thermal\s+Gradient\s*:\s*([0-9]+\.[0-9]+)\s*C/mm}
        "operator"                "<="
        "default_threshold"       "10.0"
    }

    "emir_pg_missing_via" {
        "description"             "Missing PG vias must be zero"
        "script"                  "check_routing.tcl"
        "category"                "power_mesh"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {Missing\s+PG\s+Vias\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "emir_pg_strap_integrity" {
        "description"             "PG strap connectivity must be verified"
        "script"                  "check_routing.tcl"
        "category"                "power_mesh"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "ir_drop_summary.rpt"
        "metric_pattern"          {PG\s+Strap\s+Integrity\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "emir_summary_report" {
        "description"             "Complete EMIR summary report generated"
        "script"                  "check_file_exists.tcl"
        "category"                "emir"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "EMIR_SIGNOFF"
        "report_pattern"          "power_summary.rpt"
        "metric_pattern"          {EMIR\s+Summary\s+Report\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }
}
