###############################################################################
# CBflow Placement Check Library
# Category: placement
# Version: 1.0.0
#
# Defines 20 placement-related checks for exit milestone validation.
# Used by the checklist engine to evaluate placement quality at each milestone.
###############################################################################

array set placement_checks {

    "illegal_cells" {
        "description"             "Zero illegal cell placement violations required"
        "category"                "placement"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Total\s+Illegal\s+Cells\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_density" {
        "description"             "Overall cell density percentage within target range"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Cell\s+Density\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "80.0"
    }

    "brickwall_density" {
        "description"             "Local density hotspots must not exceed 90%"
        "category"                "placement"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Max\s+Local\s+Density\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "90.0"
    }

    "displacement_quality" {
        "description"             "Cell displacement from optimal placement position"
        "category"                "placement"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Average\s+Cell\s+Displacement\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "pin_accessibility" {
        "description"             "Pin access violations for routing must be zero"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Pin\s+Access\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "macro_spacing" {
        "description"             "Macro-to-macro minimum spacing compliance"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Macro\s+Spacing\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "macro_orientation" {
        "description"             "Macro orientation legality — all macros correctly oriented"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Macro\s+Orientation\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "macro_channel_width" {
        "description"             "Routing channel width between macros meets minimum"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Min\s+Macro\s+Channel\s+Width\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "2.0"
    }

    "halo_violations" {
        "description"             "Halo/keepout region violations count"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Halo\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "blockage_overlap" {
        "description"             "Cell-in-blockage placement violations"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Blockage\s+Overlap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_orientation" {
        "description"             "Standard cell orientation violations"
        "category"                "placement"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Cell\s+Orientation\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "well_tap_spacing" {
        "description"             "Well tap proximity compliance — max spacing within limit"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Well\s+Tap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "endcap_placement" {
        "description"             "Endcap cell placement completeness"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Missing\s+Endcap\s+Cells\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "filler_coverage" {
        "description"             "Filler cell coverage ratio percentage"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Filler\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "power_domain_boundary" {
        "description"             "Power domain boundary cell placement violations"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Power\s+Domain\s+Boundary\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "io_placement_legality" {
        "description"             "IO pad placement legality violations"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {IO\s+Placement\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "utilization_uniformity" {
        "description"             "Utilization variance across placement regions"
        "category"                "placement"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Utilization\s+Std\s+Dev\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "10.0"
    }

    "congestion_hotspot" {
        "description"             "Local congestion hotspot overflow percentage"
        "category"                "placement"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          {Max\s+Overflow\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "placement_wirelength" {
        "description"             "Total estimated wirelength within budget"
        "category"                "placement"
        "severity"                "minor"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Wire\s+Length\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "1000000"
    }

    "scan_chain_reorder" {
        "description"             "Scan chain physical order quality — reorder distance"
        "category"                "placement"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Scan\s+Chain\s+Reorder\s+Distance\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "100.0"
    }
}
