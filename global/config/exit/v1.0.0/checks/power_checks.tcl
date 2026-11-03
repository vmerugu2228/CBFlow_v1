########################################################################
# CBflow Exit Check Library — Power / UPF Checks
# 20 low-power and UPF implementation checks
########################################################################

array set power_checks {
    "missing_isolation" {
        "description"             "Missing isolation cells at power domain crossings"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Missing\s+Isolation\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "missing_level_shifters" {
        "description"             "Missing level shifter cells at voltage domain crossings"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Missing\s+Level\s+Shifters\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_switch_distance" {
        "description"             "Maximum distance from power switch to controlled logic"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Max\s+Switch\s+Distance\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "50.0"
    }
    "always_on_violations" {
        "description"             "Always-on path violations in power-gated domains"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Always-On\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "retention_check" {
        "description"             "Retention register save and restore path verification"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Retention\s+Errors\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "upf_implementation_match" {
        "description"             "Mismatch count between UPF intent and implementation"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_upf.rpt"
        "metric_pattern"          {UPF\s+Mismatches\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_domain_crossing" {
        "description"             "Unprotected signals crossing power domain boundaries"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Unprotected\s+Crossings\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "supply_net_connectivity" {
        "description"             "VDD and VSS supply net connectivity integrity"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Supply\s+Connectivity\s+Errors\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_switch_chain" {
        "description"             "Power switch daisy-chain connectivity and ordering integrity"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Switch\s+Chain\s+Errors\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "isolation_enable_timing" {
        "description"             "Isolation cell enable signal timing verification"
        "script"                  "check_timing.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Isolation\s+Enable\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "level_shifter_placement" {
        "description"             "Level shifter placement location compliance"
        "script"                  "check_legality.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Level\s+Shifter\s+Placement\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_state_coverage" {
        "description"             "Percentage of defined power states exercised in verification"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_upf.rpt"
        "metric_pattern"          {Power\s+State\s+Coverage\s*:\s*([\d.]+)\s*%}
        "operator"                ">="
        "default_threshold"       "100.0"
    }
    "corruption_analysis" {
        "description"             "State corruption risk analysis during power transitions"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {Corruption\s+Risks\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "sleep_wakeup_sequence" {
        "description"             "Sleep and wakeup power sequence verification"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Sequence\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_intent_lint" {
        "description"             "UPF power intent lint and syntax check violations"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_upf.rpt"
        "metric_pattern"          {UPF\s+Lint\s+Errors\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "voltage_area_overlap" {
        "description"             "Overlapping voltage area boundary violations"
        "script"                  "check_legality.tcl"
        "category"                "power"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Voltage\s+Area\s+Overlaps\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "ao_buffer_usage" {
        "description"             "Always-on buffer insertion and usage verification"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_mv.rpt"
        "metric_pattern"          {AO\s+Buffer\s+Violations\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_domain_boundary_cells" {
        "description"             "Completeness of boundary cells at power domain edges"
        "script"                  "check_legality.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {Missing\s+Boundary\s+Cells\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "esd_path_check" {
        "description"             "ESD discharge path integrity through power domains"
        "script"                  "check_file_exists.tcl"
        "category"                "power"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "check_power_domains.rpt"
        "metric_pattern"          {ESD\s+Path\s+Errors\s*:\s*(\d+)}
        "operator"                "=="
        "default_threshold"       "0"
    }
    "power_gating_leakage" {
        "description"             "Residual leakage current in power-gated domains"
        "script"                  "check_power.tcl"
        "category"                "power"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_power.rpt"
        "metric_pattern"          {Gated\s+Domain\s+Leakage\s*:\s*([\d.]+)}
        "operator"                "<="
        "default_threshold"       "1.0"
    }
}
