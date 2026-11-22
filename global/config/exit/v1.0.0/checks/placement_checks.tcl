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
        "id"          "PLACEMENT_0001"
        "description"             "Zero illegal cell placement violations required"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Total\s+Illegal\s+Cells\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_density" {
        "id"          "PLACEMENT_0002"
        "description"             "Overall cell density percentage within target range"
        "script"                  "check_utilization.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Cell\s+Density\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "80.0"
    }

    "brickwall_density" {
        "id"          "PLACEMENT_0003"
        "description"             "Peak local placement density"
        "script"                  "check_utilization.tcl"
        "category"                "placement"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Max\s+Local\s+Density\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "90.0"
    }

    "displacement_quality" {
        "id"          "PLACEMENT_0004"
        "description"             "Cell displacement from optimal placement position"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Average\s+Cell\s+Displacement\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "pin_accessibility" {
        "id"          "PLACEMENT_0005"
        "description"             "Pin-access violations for routing"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Pin\s+Access\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "macro_spacing" {
        "id"          "PLACEMENT_0006"
        "description"             "Macro-to-macro minimum spacing compliance"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Macro\s+Spacing\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "macro_orientation" {
        "id"          "PLACEMENT_0007"
        "description"             "Macros with an illegal orientation"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Macro\s+Orientation\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "macro_channel_width" {
        "id"          "PLACEMENT_0008"
        "description"             "Routing channel width between macros"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Min\s+Macro\s+Channel\s+Width\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "2.0"
    }

    "halo_violations" {
        "id"          "PLACEMENT_0009"
        "description"             "Halo/keepout region violations count"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Halo\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "blockage_overlap" {
        "id"          "PLACEMENT_0010"
        "description"             "Cell-in-blockage placement violations"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Blockage\s+Overlap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "cell_orientation" {
        "id"          "PLACEMENT_0011"
        "description"             "Standard cell orientation violations"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Cell\s+Orientation\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "well_tap_spacing" {
        "id"          "PLACEMENT_0012"
        "description"             "Well-tap spacing violations"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Well\s+Tap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "endcap_placement" {
        "id"          "PLACEMENT_0013"
        "description"             "Endcap cell placement completeness"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Missing\s+Endcap\s+Cells\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "filler_coverage" {
        "id"          "PLACEMENT_0014"
        "description"             "Filler cell coverage ratio percentage"
        "script"                  "check_utilization.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Filler\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "unit"        "%"
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "power_domain_boundary" {
        "id"          "PLACEMENT_0015"
        "description"             "Power domain boundary cell placement violations"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {Power\s+Domain\s+Boundary\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "io_placement_legality" {
        "id"          "PLACEMENT_0016"
        "description"             "IO pad placement legality violations"
        "script"                  "check_legality.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_legality.rpt"
        "metric_pattern"          {IO\s+Placement\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "utilization_uniformity" {
        "id"          "PLACEMENT_0017"
        "description"             "Utilization variance across placement regions"
        "script"                  "check_utilization.tcl"
        "category"                "placement"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_utilization.rpt"
        "metric_pattern"          {Utilization\s+Std\s+Dev\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "10.0"
    }

    "congestion_hotspot" {
        "id"          "PLACEMENT_0018"
        "description"             "Local congestion hotspot overflow percentage"
        "script"                  "check_congestion.tcl"
        "category"                "placement"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_congestion.rpt"
        "metric_pattern"          {Max\s+Overflow\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "unit"        "%"
        "operator"                "<="
        "default_threshold"       "5.0"
    }

    "placement_wirelength" {
        "id"          "PLACEMENT_0019"
        "description"             "Total estimated wirelength within budget"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "minor"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Wire\s+Length\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "1000000"
    }

    "scan_chain_reorder" {
        "id"          "PLACEMENT_0020"
        "description"             "Scan-chain reorder distance"
        "script"                  "check_file_exists.tcl"
        "category"                "placement"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_design.rpt"
        "metric_pattern"          {Scan\s+Chain\s+Reorder\s+Distance\s*:\s*([0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "100.0"
    }
}
