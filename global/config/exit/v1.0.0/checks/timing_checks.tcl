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
        "id"          "TIMING_0001"
        "description"             "Worst negative slack (setup) must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {slack\s+\((?:MET|VIOLATED)\)\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "setup_tns" {
        "id"          "TIMING_0002"
        "description"             "Total negative slack (setup) must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Negative\s+Slack\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_wns" {
        "id"          "TIMING_0003"
        "description"             "Worst negative slack (hold) must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.min.rpt"
        "metric_pattern"          {slack\s+\((?:MET|VIOLATED)\)\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_tns" {
        "id"          "TIMING_0004"
        "description"             "Total negative slack (hold) must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Total\s+Negative\s+Slack\s*\(Hold\)\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "setup_nvp" {
        "id"          "TIMING_0005"
        "description"             "Number of violating paths (setup) within limit"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {No\.\s+of\s+Violating\s+Paths\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "hold_nvp" {
        "id"          "TIMING_0006"
        "description"             "Number of violating paths (hold) within limit"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {No\.\s+of\s+Hold\s+Violating\s+Paths\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_cap_violations" {
        "id"          "TIMING_0007"
        "description"             "Max capacitance violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Cap\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_tran_violations" {
        "id"          "TIMING_0008"
        "description"             "Max transition violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Tran\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "max_fanout_violations" {
        "id"          "TIMING_0009"
        "description"             "Max fanout violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Fanout\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "net_length_violations" {
        "id"          "TIMING_0010"
        "description"             "Nets exceeding max length threshold"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Nets\s+With\s+Length\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "setup_wns_per_group" {
        "id"          "TIMING_0011"
        "description"             "Worst WNS per timing path group must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Timing\s+Path\s+Group\s+\S+\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "hold_wns_per_group" {
        "id"          "TIMING_0012"
        "description"             "Worst hold WNS per timing path group must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Timing\s+Path\s+Group\s+\S+\s+Hold\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "recovery_violations" {
        "id"          "TIMING_0013"
        "description"             "Recovery timing violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Recovery\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "removal_violations" {
        "id"          "TIMING_0014"
        "description"             "Removal timing violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Removal\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "pulse_width_violations" {
        "id"          "TIMING_0015"
        "description"             "Min pulse width violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Min\s+Pulse\s+Width\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clock_gating_check" {
        "id"          "TIMING_0016"
        "description"             "Clock gating timing violations count within limit"
        "script"                  "check_constraints.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Clock\s+Gating\s+Check\s+Violations\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "multicycle_path_check" {
        "id"          "TIMING_0017"
        "description"             "Multicycle path constraint coverage percentage"
        "script"                  "check_file_exists.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Multicycle\s+Paths\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "1"
    }

    "false_path_coverage" {
        "id"          "TIMING_0018"
        "description"             "False path constraint validation count"
        "script"                  "check_file_exists.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {False\s+Paths\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }

    "case_analysis_coverage" {
        "id"          "TIMING_0019"
        "description"             "Case analysis constraint count validated"
        "script"                  "check_file_exists.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Case\s+Analysis\s+Constants\s*:\s*([0-9]+)}
        "operator"                ">="
        "default_threshold"       "0"
    }

    "timing_exception_coverage" {
        "id"          "TIMING_0020"
        "description"             "Timing exception coverage ratio must meet threshold"
        "script"                  "check_file_exists.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Exception\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "95.0"
    }

    "setup_slack_histogram" {
        "id"          "TIMING_0021"
        "description"             "Setup slack distribution — paths with slack below threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Paths\s+with\s+Slack\s+<\s*-0\.100\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "hold_slack_histogram" {
        "id"          "TIMING_0022"
        "description"             "Hold slack distribution — paths with slack below threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Hold\s+Paths\s+with\s+Slack\s+<\s*-0\.050\s*:\s*([0-9]+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "cross_corner_wns" {
        "id"          "TIMING_0023"
        "description"             "Worst WNS across all MMMC corners must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Cross-Corner\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "cross_corner_tns" {
        "id"          "TIMING_0024"
        "description"             "Worst TNS across all MMMC corners must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Cross-Corner\s+TNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "interface_timing" {
        "id"          "TIMING_0025"
        "description"             "I/O timing constraint compliance — interface WNS"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {Group\s+'(in2reg|reg2out|in2out)'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "reg2reg_wns" {
        "id"          "TIMING_0026"
        "description"             "Register-to-register worst setup slack"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "PLACE_EXIT CTS_EXIT PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'reg2reg'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "io2reg_wns" {
        "id"          "TIMING_0027"
        "description"             "IO-to-register worst setup slack"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'in2reg'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "reg2io_wns" {
        "id"          "TIMING_0028"
        "description"             "Register-to-IO worst setup slack"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Group\s+'reg2out'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "memory_timing" {
        "id"          "TIMING_0029"
        "description"             "Memory interface timing slack must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "PRO_EXIT BTO"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {Group\s+'mem2reg|reg2mem'\s+WNS\s+(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "signoff_vs_implementation" {
        "id"          "TIMING_0030"
        "description"             "Signoff/implementation WNS correlation delta within limit"
        "script"                  "check_timing.tcl"
        "category"                "timing"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "BTO"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Signoff\s+Correlation\s+Delta\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "0.050"
    }
}
