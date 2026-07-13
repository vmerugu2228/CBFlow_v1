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
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Total\s+DRC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_spacing" {
        "description"             "Metal spacing violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Spacing\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_width" {
        "description"             "Min width violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Min\s+Width\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_enclosure" {
        "description"             "Via enclosure violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Enclosure\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_area" {
        "description"             "Min area violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Min\s+Area\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_density" {
        "description"             "Density rule violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Density\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_antenna" {
        "description"             "Antenna DRC violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Antenna\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_off_grid" {
        "description"             "Off-grid violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Off-Grid\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_overlap" {
        "description"             "Metal overlap violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Overlap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_drc_notch" {
        "description"             "Notch violations must be zero"
        "script"                  "check_drc.tcl"
        "category"                "drc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {Notch\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_match" {
        "description"             "LVS comparison result must be MATCH"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {LVS\s+Result\s*:\s*(MATCH|INCORRECT)}
        "operator"                "=="
        "default_threshold"       "MATCH"
    }

    "pv_lvs_shorts" {
        "description"             "LVS short circuits must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Short\s+Circuits\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_opens" {
        "description"             "LVS open circuits must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Open\s+Circuits\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_device_mismatch" {
        "description"             "Device count mismatch must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Device\s+Count\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_net_mismatch" {
        "description"             "Net count mismatch must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Net\s+Count\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_property_mismatch" {
        "description"             "Device property mismatch must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Property\s+Mismatch\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_floating_nets" {
        "description"             "Floating nets in layout must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Floating\s+Nets\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_lvs_missing_connections" {
        "description"             "Missing connections must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "lvs"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "lvs_summary.rpt"
        "metric_pattern"          {Missing\s+Connections\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_ldl_total" {
        "description"             "PERC-LDL aggregate violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc_ldl"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_ldl_summary.rpt"
        "metric_pattern"          {Total\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_ldl_well_contact" {
        "description"             "PERC-LDL well-contact spacing violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc_ldl"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_ldl_summary.rpt"
        "metric_pattern"          {Well\s+Contact\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_ldl_floating_gate" {
        "description"             "PERC-LDL floating-gate detection violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc_ldl"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_ldl_summary.rpt"
        "metric_pattern"          {Floating\s+Gate\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_ldl_latchup" {
        "description"             "PERC-LDL latch-up violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc_ldl"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_ldl_summary.rpt"
        "metric_pattern"          {Latch-up\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_esd" {
        "description"             "ESD protection path violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {ESD\s+Path\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_voltage" {
        "description"             "Voltage-aware DRC violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {Voltage-Aware\s+DRC\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_perc_latchup" {
        "description"             "PERC latch-up check violations must be zero"
        "script"                  "check_file_exists.tcl"
        "category"                "perc"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "perc_summary.rpt"
        "metric_pattern"          {PERC\s+Latch-up\s+Violations\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_fill_merge_complete" {
        "description"             "Fill-merged GDS validation completed successfully"
        "script"                  "check_file_exists.tcl"
        "category"                "fill_merge_gds"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "fill_merge_gds_summary.rpt"
        "metric_pattern"          {Status\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "pv_fill_merge_density" {
        "description"             "Post-fill density within foundry limits"
        "script"                  "check_file_exists.tcl"
        "category"                "fill_merge_gds"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "fill_merge_gds_summary.rpt"
        "metric_pattern"          {Density\s+Violations\s+Post-Fill\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_xor_clean" {
        "description"             "XOR comparison (pre/post fill) must be clean"
        "script"                  "check_file_exists.tcl"
        "category"                "fill"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "xor_summary.rpt"
        "metric_pattern"          {XOR\s+Differences\s*:\s*([0-9]+)}
        "operator"                "=="
        "default_threshold"       "0"
    }

    "pv_merge_complete" {
        "description"             "Signoff GDS merge completed without errors"
        "script"                  "check_file_exists.tcl"
        "category"                "decomp_merge_gds"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "decomp_merge_gds_summary.rpt"
        "metric_pattern"          {Status\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "pv_summary_report" {
        "description"             "Complete PV summary report generated"
        "script"                  "check_file_exists.tcl"
        "category"                "pv"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "PV_SIGNOFF"
        "report_pattern"          "drc_summary.rpt"
        "metric_pattern"          {PV\s+Summary\s+Report\s*:\s*(GENERATED|MISSING)}
        "operator"                "=="
        "default_threshold"       "GENERATED"
    }
}
