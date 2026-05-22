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
