###############################################################################
# CBflow STA Flow Check Library
# Category: sta_flow
# Version: 1.0.0
#
# Defines 25 STA-specific checks for timing signoff exit milestone validation.
# These are checks unique to the standalone STA flow — not generic timing
# checks (see timing_checks.tcl for those).
###############################################################################

array set sta_flow_checks {

    "sta_scenario_complete" {
        "description"             "All MMMC scenarios ran to completion without errors"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "mmmc_timing_summary.rpt"
        "metric_pattern"          {Scenarios\s+Completed\s*:\s*(\d+)/(\d+)}
        "operator"                "=="
        "default_threshold"       "1"
    }

    "sta_setup_signoff" {
        "description"             "Setup WNS across all scenarios must be non-negative"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "0"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {Worst\s+Setup\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_hold_signoff" {
        "description"             "Hold WNS across all scenarios must be non-negative"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.min.rpt"
        "metric_pattern"          {Worst\s+Hold\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_cross_corner_setup" {
        "description"             "Worst setup WNS across all corners must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "mmmc_timing_summary.rpt"
        "metric_pattern"          {Cross-Corner\s+Setup\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_cross_corner_hold" {
        "description"             "Worst hold WNS across all corners must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "mmmc_timing_summary.rpt"
        "metric_pattern"          {Cross-Corner\s+Hold\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_pba_setup" {
        "description"             "Path-based analysis setup timing must be clean"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {PBA\s+Setup\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_pba_hold" {
        "description"             "Path-based analysis hold timing must be clean"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.min.rpt"
        "metric_pattern"          {PBA\s+Hold\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_epba_setup" {
        "description"             "Exhaustive PBA setup analysis WNS must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.max.rpt"
        "metric_pattern"          {EPBA\s+Setup\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_epba_hold" {
        "description"             "Exhaustive PBA hold analysis WNS must meet threshold"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_timing.min.rpt"
        "metric_pattern"          {EPBA\s+Hold\s+WNS\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                ">="
        "default_threshold"       "0.0"
    }

    "sta_si_delta" {
        "description"             "SI-aware timing delta must be within acceptable limit"
        "script"                  "check_signal_integrity.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {SI\s+Timing\s+Delta\s*:\s*(-?[0-9]+\.[0-9]+)}
        "operator"                "<="
        "default_threshold"       "0.050"
    }

    "sta_clock_reconvergence" {
        "description"             "CRPR (clock reconvergence pessimism removal) applied correctly"
        "script"                  "check_timing.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {CRPR\s+Applied\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "sta_constraint_coverage" {
        "description"             "All SDC constraints must be exercised in timing analysis"
        "script"                  "check_constraints.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_constraint.rpt"
        "metric_pattern"          {Constraint\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "sta_unconstrained_paths" {
        "description"             "Zero unconstrained timing paths must remain"
        "script"                  "check_constraints.tcl"
        "category"                "sta_flow"
        "severity"                "critical"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Unconstrained\s+Paths\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_max_cap_clean" {
        "description"             "Max capacitance violations must be zero across all scenarios"
        "script"                  "check_constraints.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Cap\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_max_tran_clean" {
        "description"             "Max transition violations must be zero across all scenarios"
        "script"                  "check_constraints.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Tran\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_max_fanout_clean" {
        "description"             "Max fanout violations must be zero across all scenarios"
        "script"                  "check_constraints.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Max\s+Fanout\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_clock_uncertainty" {
        "description"             "Clock uncertainty properly set for all clock domains"
        "script"                  "check_clock_quality.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "1"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Clocks\s+Without\s+Uncertainty\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_input_delay_coverage" {
        "description"             "All input ports must have input delay constraints defined"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Inputs\s+Without\s+Delay\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_output_delay_coverage" {
        "description"             "All output ports must have output delay constraints defined"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "check_timing.rpt"
        "metric_pattern"          {Outputs\s+Without\s+Delay\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_mmmc_summary" {
        "description"             "Cross-scenario MMMC summary report must be generated"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "0"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "mmmc_timing_summary.rpt"
        "metric_pattern"          {Summary\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "sta_power_report" {
        "description"             "Power analysis report must be generated during STA"
        "script"                  "check_power.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Power\s+Report\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "sta_noise_analysis" {
        "description"             "Noise and glitch analysis must be clean"
        "script"                  "check_signal_integrity.tcl"
        "category"                "sta_flow"
        "severity"                "major"
        "min_phase_index"               "3"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Noise\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "sta_sdf_generated" {
        "description"             "SDF timing annotation file must be generated for gate-sim"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {SDF\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "sta_bottleneck_report" {
        "description"             "Timing bottleneck analysis report must be complete"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "2"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {Bottleneck\s+Report\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }

    "sta_eco_guidance" {
        "description"             "ECO guidance report must be generated for timing closure"
        "script"                  "check_file_exists.tcl"
        "category"                "sta_flow"
        "severity"                "minor"
        "min_phase_index"               "3"
        "applicable_milestones"   "STA_SIGNOFF"
        "report_pattern"          "report_qor.rpt"
        "metric_pattern"          {ECO\s+Guidance\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }
}
