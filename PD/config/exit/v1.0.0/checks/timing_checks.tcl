###############################################################################
# CBflow Timing Check Library
# Category: timing
# Version: 1.0.0
#
# Defines 30 timing-related checks for exit milestone validation.
# Used by the checklist engine to evaluate timing quality at each milestone.
###############################################################################

array set timing_checks {

    "setup_wns" {
        "description"             "Worst negative slack (setup) must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {slack\s+\(MET\|VIOLATED\)\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "setup_tns" {
        "description"             "Total negative slack (setup) must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Negative\s+Slack\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_wns" {
        "description"             "Worst negative slack (hold) must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.min.rpt"
        "metric_pattern"          {slack\s+\(MET\|VIOLATED\)\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_tns" {
        "description"             "Total negative slack (hold) must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Negative\s+Slack\s*\(Hold\)\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "setup_nvp" {
        "description"             "Number of violating paths (setup) within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {No\.\s+of\s+Violating\s+Paths\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "hold_nvp" {
        "description"             "Number of violating paths (hold) within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {No\.\s+of\s+Hold\s+Violating\s+Paths\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_cap_violations" {
        "description"             "Max capacitance violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Cap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_tran_violations" {
        "description"             "Max transition violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Tran\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_fanout_violations" {
        "description"             "Max fanout violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Fanout\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "net_length_violations" {
        "description"             "Nets exceeding max length threshold"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Nets\s+With\s+Length\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "setup_wns_per_group" {
        "description"             "Worst WNS per timing path group must meet threshold"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Timing\s+Path\s+Group\s+\S+\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_wns_per_group" {
        "description"             "Worst hold WNS per timing path group must meet threshold"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Timing\s+Path\s+Group\s+\S+\s+Hold\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "recovery_violations" {
        "description"             "Recovery timing violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Recovery\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "removal_violations" {
        "description"             "Removal timing violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Removal\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "pulse_width_violations" {
        "description"             "Min pulse width violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Min\s+Pulse\s+Width\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clock_gating_check" {
        "description"             "Clock gating timing violations count within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Clock\s+Gating\s+Check\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "multicycle_path_check" {
        "description"             "Multicycle path constraint coverage percentage"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Multicycle\s+Paths\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "1"
    }

    "false_path_coverage" {
        "description"             "False path constraint validation count"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {False\s+Paths\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }

    "case_analysis_coverage" {
        "description"             "Case analysis constraint count validated"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Case\s+Analysis\s+Constants\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }

    "timing_exception_coverage" {
        "description"             "Timing exception coverage ratio must meet threshold"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Exception\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "95.0"
    }

    "setup_slack_histogram" {
        "description"             "Setup slack distribution — paths with slack below threshold"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Paths\s+with\s+Slack\s+<\s*-0\.100\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "hold_slack_histogram" {
        "description"             "Hold slack distribution — paths with slack below threshold"
        "category"                "timing"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Hold\s+Paths\s+with\s+Slack\s+<\s*-0\.050\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "cross_corner_wns" {
        "description"             "Worst WNS across all MMMC corners must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Cross-Corner\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "cross_corner_tns" {
        "description"             "Worst TNS across all MMMC corners must meet threshold"
        "category"                "timing"
        "severity"                "critical"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Cross-Corner\s+TNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "interface_timing" {
        "description"             "I/O timing constraint compliance — interface WNS"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {Group\s+'(in2reg|reg2out|in2out)'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "reg2reg_wns" {
        "description"             "Register-to-register worst setup slack"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'reg2reg'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "io2reg_wns" {
        "description"             "IO-to-register worst setup slack"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'in2reg'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "reg2io_wns" {
        "description"             "Register-to-IO worst setup slack"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'reg2out'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "memory_timing" {
        "description"             "Memory interface timing slack must meet threshold"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {Group\s+'mem2reg|reg2mem'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "signoff_vs_implementation" {
        "description"             "Signoff/implementation WNS correlation delta within limit"
        "category"                "timing"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Signoff\s+Correlation\s+Delta\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "0.050"
    }
}
