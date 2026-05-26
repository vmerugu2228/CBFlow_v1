################################################################################
# CBflow v2.0.0 — Routing Check Library
# File: PD/config/exit/v1.0.0/checks/routing_checks.tcl
#
# 25 routing-related checks for exit milestone validation.
# Covers: route completion, DRC, congestion, antenna, density, NDR, shielding.
################################################################################

array set routing_checks {

    "routing_completion" {
        "description"             "Routing 100% complete — all nets fully routed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Completion\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "=="
        "default_threshold"       "100"
    }

    "opens" {
        "description"             "Zero open nets — no incomplete routing"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Number of open nets\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "shorts" {
        "description"             "Zero short violations — no shorted nets"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Number of shorts\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "drc_total" {
        "description"             "Total DRC violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Total DRC violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_spacing" {
        "description"             "Metal spacing violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Spacing violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_width" {
        "description"             "Minimum width violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Min width violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_via" {
        "description"             "Via enclosure violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Via enclosure violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_area" {
        "description"             "Minimum area violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Min area violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "congestion_h" {
        "description"             "Horizontal routing congestion overflow percentage"
        "script"                  "check_congestion.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          "^Horizontal overflow\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "0.5"
    }

    "congestion_v" {
        "description"             "Vertical routing congestion overflow percentage"
        "script"                  "check_congestion.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          "^Vertical overflow\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "0.5"
    }

    "antenna_violations" {
        "description"             "Antenna rule violations count"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Antenna violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "antenna_ratio" {
        "description"             "Worst antenna ratio within allowed limit"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Worst antenna ratio\\s*:\\s*(\\d+\\.?\\d*)"
        "operator"                "<="
        "default_threshold"       "1.0"
    }

    "net_length_threshold" {
        "description"             "Number of nets exceeding maximum length threshold"
        "script"                  "check_constraints.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Nets exceeding length threshold\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "detour_routing" {
        "description"             "Routing detour percentage — ratio of actual to ideal length"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Detour percentage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "via_count_optimization" {
        "description"             "Via count per net optimization — excess via percentage"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Excess via percentage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "10.0"
    }

    "ndr_compliance" {
        "description"             "Non-default rule compliance — all NDR nets meet rules"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^NDR violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "shielding_coverage" {
        "description"             "Critical net shielding coverage percentage"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Shielding coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "metal_density_min" {
        "description"             "Minimum metal density per layer meets foundry requirement"
        "script"                  "check_utilization.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Min metal density\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "20.0"
    }

    "metal_density_max" {
        "description"             "Maximum metal density per layer within foundry limit"
        "script"                  "check_utilization.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Max metal density\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "80.0"
    }

    "via_density" {
        "description"             "Via density uniformity across design"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Via density variance\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "15.0"
    }

    "power_shorts" {
        "description"             "Power-to-signal short violations — zero allowed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Power-to-signal shorts\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_opens" {
        "description"             "Power mesh open connections — zero allowed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Power mesh opens\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "critical_net_routing" {
        "description"             "Critical net routing quality — DRC-clean critical nets"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Critical net DRC violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "clock_route_drc" {
        "description"             "Clock routing specific DRC violations"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Clock route DRC violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "multi_cut_via_ratio" {
        "description"             "Multi-cut via usage ratio for reliability"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Multi-cut via ratio\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "90.0"
    }

}
