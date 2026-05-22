##############################################################################
# Manufacturing / DFM Check Library
# CBflow v2.0.0 — Exit Milestone Checks
##############################################################################

array set manufacturing_checks {
    "metal_density_m1" {
        "description"             "Metal 1 density within foundry limits"
        "category"                "manufacturing"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "M1 density\\s*:\\s*([0-9.]+)%"
        "operator"                ">="
        "default_threshold"       "20.0"
    }
    "metal_density_m2" {
        "description"             "Metal 2 density within foundry limits"
        "category"                "manufacturing"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "M2 density\\s*:\\s*([0-9.]+)%"
        "operator"                ">="
        "default_threshold"       "20.0"
    }
    "metal_density_upper" {
        "description"             "Upper metal density compliance"
        "category"                "manufacturing"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "Upper metal density violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "metal_density_uniformity" {
        "description"             "Density window uniformity within limits"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "Density uniformity violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "via_density_check" {
        "description"             "Via density per layer within limits"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "Via density violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "critical_area_analysis" {
        "description"             "Random defect critical area analysis"
        "category"                "manufacturing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_manufacturing.rpt"
        "metric_pattern"          "Critical area score\\s*:\\s*([0-9.]+)"
        "operator"                "<="
        "default_threshold"       "1.0"
    }
    "antenna_per_layer" {
        "description"             "Per-layer antenna ratio check"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO MTO"
        "report_pattern"          "report_antenna.rpt"
        "metric_pattern"          "Antenna violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "double_patterning" {
        "description"             "Double patterning compliance (advanced nodes)"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "Double patterning violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "minimum_density_fill" {
        "description"             "Post-fill minimum density check"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "Min density violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "filler_metal_check" {
        "description"             "Dummy metal fill coverage"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_density.rpt"
        "metric_pattern"          "Filler metal coverage\\s*:\\s*([0-9.]+)%"
        "operator"                ">="
        "default_threshold"       "80.0"
    }
    "opc_friendly_check" {
        "description"             "OPC-friendly routing patterns"
        "category"                "manufacturing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_manufacturing.rpt"
        "metric_pattern"          "OPC unfriendly patterns\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "lithography_hotspot" {
        "description"             "Lithography hotspot detection"
        "category"                "manufacturing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_manufacturing.rpt"
        "metric_pattern"          "Lithography hotspots\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "etch_proximity" {
        "description"             "Etch proximity effect violations"
        "category"                "manufacturing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_manufacturing.rpt"
        "metric_pattern"          "Etch proximity violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "cmp_uniformity" {
        "description"             "CMP planarity and uniformity analysis"
        "category"                "manufacturing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "report_manufacturing.rpt"
        "metric_pattern"          "CMP uniformity violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
    "esd_protection" {
        "description"             "ESD structure completeness check"
        "category"                "manufacturing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO MTO"
        "report_pattern"          "signoff_check_drc.rpt"
        "metric_pattern"          "ESD violations\\s*:\\s*(\\d+)"
        "operator"                "=="
        "default_threshold"       "0"
    }
}
