###############################################################################
# CBflow LEC Flow Check Library
# Category: lec_flow
# Version: 1.0.0
#
# Defines 15 LEC-specific checks for logical equivalence signoff validation.
# Used by the checklist engine to evaluate LEC quality at the LEC_SIGNOFF
# milestone.
###############################################################################

array set lec_flow_checks {

    "lec_equivalence" {
        "description"             "Overall logical equivalence verification must SUCCEED"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "comparison_summary.rpt"
        "metric_pattern"          {Equivalence\s+Result\s*:\s*(SUCCEEDED|FAILED)}
        "operator"                "=="
        "default_threshold"       "SUCCEEDED"
    }

    "lec_non_equivalent" {
        "description"             "Zero non-equivalent comparison points"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "comparison_summary.rpt"
        "metric_pattern"          {Non-Equivalent\s+Points\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_unmapped_points" {
        "description"             "Zero unmapped comparison points between golden and revised"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "comparison_summary.rpt"
        "metric_pattern"          {Unmapped\s+Points\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_abort_points" {
        "description"             "Zero aborted comparison points during verification"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "comparison_summary.rpt"
        "metric_pattern"          {Aborted\s+Points\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_black_box" {
        "description"             "Zero unresolved black boxes in the design hierarchy"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "setup_summary.rpt"
        "metric_pattern"          {Unresolved\s+Black\s+Boxes\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_setup_warnings" {
        "description"             "Zero setup and configuration warnings during LEC run"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "setup_summary.rpt"
        "metric_pattern"          {Setup\s+Warnings\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_failing_points_report" {
        "description"             "Failing points detailed report generated if any failures exist"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "failing_points.rpt"
        "metric_pattern"          {Failing\s+Points\s+Report\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "lec_golden_netlist_read" {
        "description"             "Golden (reference) netlist read without errors"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "setup_summary.rpt"
        "metric_pattern"          {Golden\s+Read\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_revised_netlist_read" {
        "description"             "Revised (implementation) netlist read without errors"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "setup_summary.rpt"
        "metric_pattern"          {Revised\s+Read\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_datapath_verify" {
        "description"             "Datapath equivalence verification completed successfully"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "equivalence_analysis.rpt"
        "metric_pattern"          {Datapath\s+Verification\s*:\s*(PASS|FAIL)}
        "operator"                "=="
        "default_threshold"       "PASS"
    }

    "lec_multibit_matching" {
        "description"             "Multi-bit register matching verified correctly"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "equivalence_analysis.rpt"
        "metric_pattern"          {Multibit\s+Matching\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_scan_chain_verify" {
        "description"             "Scan chain logic equivalence verified between golden and revised"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "equivalence_analysis.rpt"
        "metric_pattern"          {Scan\s+Chain\s+Mismatches\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_power_domain_verify" {
        "description"             "Power domain logic equivalence verified across UPF domains"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "equivalence_analysis.rpt"
        "metric_pattern"          {Power\s+Domain\s+Mismatches\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "lec_svf_applied" {
        "description"             "SVF guidance file applied correctly during comparison"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "setup_summary.rpt"
        "metric_pattern"          {SVF\s+Applied\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "lec_summary_report" {
        "description"             "Complete comparison summary report generated successfully"
        "script"                  "check_file_exists.tcl"
        "category"                "lec_flow"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "LEC_SIGNOFF"
        "report_pattern"          "comparison_summary.rpt"
        "metric_pattern"          {Summary\s+Report\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }
}
