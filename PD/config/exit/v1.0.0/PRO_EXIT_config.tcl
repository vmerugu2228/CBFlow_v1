# ═══════════════════════════════════════════════════════════════════════════════
# PRO_EXIT Milestone Configuration
# Post Route Optimization Exit - Design ready for Physical Verification
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "PRO_EXIT"
set milestone_info(stage) "post_route_optimization"
set milestone_info(description) "Post Route Optimization Exit - Design ready for Physical Verification"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "routing_completion" {
        "script" "check_routing_completion.tcl"
        "description" "Validate routing is 100% complete with no opens/shorts"
        "criteria" "routing_completion == 100% && opens == 0 && shorts == 0"
    "timing_closure" {
        "description" "Setup WNS must be non-negative"
        "script" "check_timing_closure.tcl"
        "criteria" "setup_wns >= 0"
    "hold_timing_clean" {
        "description" "Hold WNS must be non-negative after route_opt"
        "grep_file" "work/SYNTH_PNR/pro1/reports/report_timing.min.rpt"
        "grep_pattern" "slack.*MET"
        "grep_pass_if" "found"
        "script" "grep_check"
        "criteria" "grep found: slack.*MET"
    }
}
}
    "timing_signoff" {
        "script" "validate_timing_signoff.tcl" 
        "description" "Check timing meets signoff requirements"
        "criteria" "setup_wns >= 0ps && hold_wns >= 0ps"
    }
    "design_rule_check" {
        "script" "check_design_rules.tcl"
        "description" "Verify design rule compliance"
        "criteria" "drc_violations == 0"
    }
    "power_integrity" {
        "script" "check_power_integrity.tcl"
        "description" "Validate power integrity and IR drop"
        "criteria" "max_ir_drop <= 30mV && em_violations == 0"
    }
    "signal_integrity" {
        "script" "check_signal_integrity.tcl"
        "description" "Check crosstalk and signal integrity"
        "criteria" "crosstalk_violations == 0 && si_violations == 0"
    }
    "area_utilization" {
        "script" "check_final_utilization.tcl"
        "description" "Final area utilization check"
        "criteria" "utilization <= target_utilization"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "antenna_check" {
        "script" "check_antenna_violations.tcl"
        "description" "Antenna rule violations check"
        "criteria" "antenna_violations == 0"
    }
    "metal_density" {
        "script" "check_metal_density.tcl"
        "description" "Metal density uniformity check"
        "criteria" "metal_density_variance <= 0.1"
    }
    "via_resistance" {
        "script" "check_via_resistance.tcl"
        "description" "Via resistance and reliability check"
        "criteria" "max_via_resistance <= via_limit"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "work/PNR/route_opt.enc"
    "reports/route/routing_summary.rpt"
    "reports/timing/signoff_timing.rpt"
    "reports/power/power_analysis.rpt"
    "reports/drc/drc_summary.rpt"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "routed_def" {
        "source" "work/PNR/route_opt.enc"
        "target" "def/pro_exit.def"
        "type" "design_file"
    }
    "routed_netlist" {
        "source" "results/netlist/routed.v"
        "target" "netlist/pro_exit.v"
        "type" "netlist"
    }
    "final_sdc" {
        "source" "results/sdc/final.sdc"
        "target" "sdc/pro_exit.sdc"
        "type" "constraint"
    }
    "spef_file" {
        "source" "results/spef/final.spef"
        "target" "spef/pro_exit.spef"
        "type" "parasitic"
    }
    "routing_report" {
        "source" "reports/route/routing_summary.rpt"
        "target" "reports/pro_routing_summary.rpt"
        "type" "report"
    }
    "timing_report" {
        "source" "reports/timing/signoff_timing.rpt"
        "target" "reports/pro_timing_signoff.rpt"
        "type" "report"
    }
    "power_report" {
        "source" "reports/power/power_analysis.rpt"
        "target" "reports/pro_power_analysis.rpt"
        "type" "report"
    }
    "drc_report" {
        "source" "reports/drc/drc_summary.rpt"
        "target" "reports/pro_drc_summary.rpt"
        "type" "report"
    }
}