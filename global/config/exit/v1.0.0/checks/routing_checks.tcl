################################################################################
# CBflow v2.0.0 — Routing Check Library
# File: PD/config/exit/v1.0.0/checks/routing_checks.tcl
#
# 25 routing-related checks for exit milestone validation.
# Covers: route completion, DRC, congestion, antenna, density, NDR, shielding.
################################################################################

array set routing_checks {

    "routing_completion" {
        "id"          "ROUTING_0001"
        "description"             "Routing 100% complete — all nets fully routed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Completion\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "=="
        "default_threshold"       "100"
    }

    "opens" {
        "id"          "ROUTING_0002"
        "description"             "Zero open nets — no incomplete routing"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Number of open nets\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "shorts" {
        "id"          "ROUTING_0003"
        "description"             "Zero short violations — no shorted nets"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Number of shorts\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "drc_total" {
        "id"          "ROUTING_0004"
        "description"             "Total DRC violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Total DRC violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_spacing" {
        "id"          "ROUTING_0005"
        "description"             "Metal spacing violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Spacing violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_width" {
        "id"          "ROUTING_0006"
        "description"             "Minimum width violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Min width violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_via" {
        "id"          "ROUTING_0007"
        "description"             "Via enclosure violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Via enclosure violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "drc_area" {
        "id"          "ROUTING_0008"
        "description"             "Minimum area violations within threshold"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Min area violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "congestion_h" {
        "id"          "ROUTING_0009"
        "description"             "Horizontal routing congestion overflow percentage"
        "script"                  "check_congestion.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          "^Horizontal overflow\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "0.5"
    }

    "congestion_v" {
        "id"          "ROUTING_0010"
        "description"             "Vertical routing congestion overflow percentage"
        "script"                  "check_congestion.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          "^Vertical overflow\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "0.5"
    }

    "antenna_violations" {
        "id"          "ROUTING_0011"
        "description"             "Antenna rule violations count"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Antenna violations\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "antenna_ratio" {
        "id"          "ROUTING_0012"
        "description"             "Worst antenna ratio within allowed limit"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "^Worst antenna ratio\\s*:\\s*(\\d+\\.?\\d*)"
        "operator"                "<="
        "default_threshold"       "1.0"
    }

    "net_length_threshold" {
        "id"          "ROUTING_0013"
        "description"             "Number of nets exceeding maximum length threshold"
        "script"                  "check_constraints.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Nets exceeding length threshold\\s*:\\s*(\\d+)"
        "operator"                "<="
        "default_threshold"       "0"
    }

    "detour_routing" {
        "id"          "ROUTING_0014"
        "description"             "Routing detour percentage — ratio of actual to ideal length"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Detour percentage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "via_count_optimization" {
        "id"          "ROUTING_0015"
        "description"             "Via count per net optimization — excess via percentage"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Excess via percentage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "10.0"
    }

    "ndr_compliance" {
        "id"          "ROUTING_0016"
        "description"             "Non-default rule compliance — all NDR nets meet rules"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^NDR violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "shielding_coverage" {
        "id"          "ROUTING_0017"
        "description"             "Critical net shielding coverage percentage"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Shielding coverage\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "metal_density_min" {
        "id"          "ROUTING_0018"
        "description"             "Minimum metal density per layer meets foundry requirement"
        "script"                  "check_utilization.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Min metal density\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "20.0"
    }

    "metal_density_max" {
        "id"          "ROUTING_0019"
        "description"             "Maximum metal density per layer within foundry limit"
        "script"                  "check_utilization.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Max metal density\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "80.0"
    }

    "via_density" {
        "id"          "ROUTING_0020"
        "description"             "Via density uniformity across design"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Via density variance\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                "<="
        "default_threshold"       "15.0"
    }

    "power_shorts" {
        "id"          "ROUTING_0021"
        "description"             "Power-to-signal short violations — zero allowed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Power-to-signal shorts\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "power_opens" {
        "id"          "ROUTING_0022"
        "description"             "Power mesh open connections — zero allowed"
        "script"                  "check_routing.tcl"
        "category"                "routing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.rpt"
        "metric_pattern"          "^Power mesh opens\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "critical_net_routing" {
        "id"          "ROUTING_0023"
        "description"             "Critical net routing quality — DRC-clean critical nets"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Critical net DRC violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "clock_route_drc" {
        "id"          "ROUTING_0024"
        "description"             "Clock routing specific DRC violations"
        "script"                  "check_drc.tcl"
        "category"                "routing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_routes.final.rpt"
        "metric_pattern"          "^Clock route DRC violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }

    "multi_cut_via_ratio" {
        "id"          "ROUTING_0025"
        "description"             "Multi-cut via usage ratio for reliability"
        "script"                  "check_file_exists.tcl"
        "category"                "routing"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          "^Multi-cut via ratio\\s*:\\s*(\\d+\\.?\\d*)%"
        "operator"                ">="
        "default_threshold"       "90.0"
    }

}
