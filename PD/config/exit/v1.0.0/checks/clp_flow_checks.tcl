###############################################################################
# CBflow CLP Flow Check Library
# Category: clp_flow
# Version: 1.0.0
#
# Defines 20 CLP-specific checks for low-power verification signoff.
# Used by the checklist engine to evaluate CLP quality at the CLP_SIGNOFF
# milestone.
###############################################################################

array set clp_flow_checks {

    "clp_isolation_check" {
        "description"             "All isolation cells present at power domain crossings"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "isolation_check.rpt"
        "metric_pattern"          {Missing\s+Isolation\s+Cells\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_level_shifter_check" {
        "description"             "All level shifters present at voltage domain crossings"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "level_shifter_check.rpt"
        "metric_pattern"          {Missing\s+Level\s+Shifters\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_retention_check" {
        "description"             "Retention save and restore paths verified correctly"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "retention_check.rpt"
        "metric_pattern"          {Retention\s+Path\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_power_domain_check" {
        "description"             "All power domains correctly defined and connected"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P0"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {Power\s+Domain\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_always_on_check" {
        "description"             "Always-on logic properly connected to always-on supply"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Always-On\s+Connection\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_voltage_area_check" {
        "description"             "Voltage areas correctly bounded and non-overlapping"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {Voltage\s+Area\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_supply_check" {
        "description"             "Supply net connections verified for all power domains"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {Supply\s+Net\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_isolation_enable" {
        "description"             "Isolation enable signal timing verified for all domains"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "isolation_check.rpt"
        "metric_pattern"          {Isolation\s+Enable\s+Timing\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_level_shifter_placement" {
        "description"             "Level shifters placed in correct voltage area"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "level_shifter_check.rpt"
        "metric_pattern"          {Level\s+Shifter\s+Placement\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_power_switch_check" {
        "description"             "Power switch chain integrity and connectivity verified"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Power\s+Switch\s+Chain\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_corruption_check" {
        "description"             "State corruption during power transitions must be zero"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Corruption\s+Risks\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_upf_syntax" {
        "description"             "UPF file lint and syntax check must be clean"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {UPF\s+Syntax\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_upf_vs_impl" {
        "description"             "UPF power intent must match physical implementation"
        "category"                "clp_flow"
        "severity"                "critical"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {UPF\s+Implementation\s+Mismatches\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_multi_driver" {
        "description"             "Multi-driver net checks at power domain boundaries"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {Multi-Driver\s+Violations\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_hanging_crossover" {
        "description"             "Hanging crossover signal detection at domain boundaries"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P1"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {Hanging\s+Crossover\s+Signals\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_sleep_wakeup" {
        "description"             "Sleep and wakeup sequence verification for all domains"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P3"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Sleep\s+Wakeup\s+Sequence\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_ao_buffer" {
        "description"             "Always-on buffer chain verification for power-gated domains"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {AO\s+Buffer\s+Chain\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_power_state_table" {
        "description"             "Power state table completeness across all defined states"
        "category"                "clp_flow"
        "severity"                "minor"
        "min_phase"               "P2"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Power\s+State\s+Coverage\s*:\s*([0-9]+\.[0-9]+)\s*%}
        "operator"                ">="
        "default_threshold"       "100.0"
    }

    "clp_esd_domain" {
        "description"             "ESD discharge path integrity through power domains"
        "category"                "clp_flow"
        "severity"                "minor"
        "min_phase"               "P3"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_domain_check.rpt"
        "metric_pattern"          {ESD\s+Path\s+Errors\s*:\s*(\d+)}
        "operator"                "<="
        "default_threshold"       "0"
    }

    "clp_summary_report" {
        "description"             "Complete CLP verification summary report generated"
        "category"                "clp_flow"
        "severity"                "major"
        "min_phase"               "P0"
        "applicable_milestones"   "CLP_SIGNOFF"
        "report_pattern"          "power_verification_summary.rpt"
        "metric_pattern"          {Summary\s+Report\s+Generated\s*:\s*(yes|no)}
        "operator"                "=="
        "default_threshold"       "yes"
    }
}
