###############################################################################
# CBflow Physical Verification Check Library
# Category: pv
# Version: 1.0.0
#
# Defines 30 physical-verification-related checks for exit milestone validation.
# Covers DRC, LVS, ERC, PERC, fill, and merge checks.
# Used by the checklist engine to evaluate PV quality at each milestone.
###############################################################################

array set pv_flow_checks {

    "pv_drc_total" {
        "description"             "Total DRC violations must be zero"
        "category"                "drc"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Total\s+DRC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_spacing" {
        "description"             "Metal spacing violations must be zero"
        "category"                "drc"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Spacing\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_width" {
        "description"             "Min width violations must be zero"
        "category"                "drc"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Min\s+Width\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_enclosure" {
        "description"             "Via enclosure violations must be zero"
        "category"                "drc"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Enclosure\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_area" {
        "description"             "Min area violations must be zero"
        "category"                "drc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Min\s+Area\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_density" {
        "description"             "Density rule violations must be zero"
        "category"                "drc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Density\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_antenna" {
        "description"             "Antenna DRC violations must be zero"
        "category"                "drc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Antenna\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_off_grid" {
        "description"             "Off-grid violations must be zero"
        "category"                "drc"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Off-Grid\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_overlap" {
        "description"             "Metal overlap violations must be zero"
        "category"                "drc"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Overlap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_notch" {
        "description"             "Notch violations must be zero"
        "category"                "drc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Notch\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_match" {
        "description"             "LVS comparison result must be MATCH"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {LVS\s+Result\s*:\s*(MATCH|INCORRECT)}
        "operator"                "=="
        "default_threshold"       "MATCH"
    }

    "pv_lvs_shorts" {
        "description"             "LVS short circuits must be zero"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Short\s+Circuits\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_opens" {
        "description"             "LVS open circuits must be zero"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Open\s+Circuits\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_device_mismatch" {
        "description"             "Device count mismatch must be zero"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Device\s+Count\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_net_mismatch" {
        "description"             "Net count mismatch must be zero"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Net\s+Count\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_property_mismatch" {
        "description"             "Device property mismatch must be zero"
        "category"                "lvs"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Property\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_floating_nets" {
        "description"             "Floating nets in layout must be zero"
        "category"                "lvs"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Floating\s+Nets\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_missing_connections" {
        "description"             "Missing connections must be zero"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Missing\s+Connections\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_erc_total" {
        "description"             "Total ERC violations must be zero"
        "category"                "erc"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "erc_summary.rpt"
        "metric_pattern"          {Total\s+ERC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_erc_well_contact" {
        "description"             "Well contact violations must be zero"
        "category"                "erc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "erc_summary.rpt"
        "metric_pattern"          {Well\s+Contact\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_erc_floating_gate" {
        "description"             "Floating gate violations must be zero"
        "category"                "erc"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "erc_summary.rpt"
        "metric_pattern"          {Floating\s+Gate\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_erc_latchup" {
        "description"             "Latch-up violations must be zero"
        "category"                "erc"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "erc_summary.rpt"
        "metric_pattern"          {Latch-up\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_esd" {
        "description"             "ESD protection path violations must be zero"
        "category"                "perc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {ESD\s+Path\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_voltage" {
        "description"             "Voltage-aware DRC violations must be zero"
        "category"                "perc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {Voltage-Aware\s+DRC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_latchup" {
        "description"             "PERC latch-up check violations must be zero"
        "category"                "perc"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {PERC\s+Latch-up\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_fill_complete" {
        "description"             "Metal fill generation completed successfully"
        "category"                "fill"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "fill_summary.rpt"
        "metric_pattern"          {Fill\s+Status\s*:\s*(COMPLETED|FAILED)}
        "operator"                "=="
        "default_threshold"       "COMPLETED"
    }

    "pv_fill_density" {
        "description"             "Post-fill density within foundry limits"
        "category"                "fill"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "fill_summary.rpt"
        "metric_pattern"          {Density\s+Violations\s+Post-Fill\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_xor_clean" {
        "description"             "XOR comparison (pre/post fill) must be clean"
        "category"                "fill"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "xor_summary.rpt"
        "metric_pattern"          {XOR\s+Differences\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_merge_complete" {
        "description"             "Layout merge completed without errors"
        "category"                "fill"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "fill_summary.rpt"
        "metric_pattern"          {Merge\s+Status\s*:\s*(COMPLETED|FAILED)}
        "operator"                "=="
        "default_threshold"       "COMPLETED"
    }

    "pv_summary_report" {
        "description"             "Complete PV summary report generated"
        "category"                "pv"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {PV\s+Summary\s+Report\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }
}
