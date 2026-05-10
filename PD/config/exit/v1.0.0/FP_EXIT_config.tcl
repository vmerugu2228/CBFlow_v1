# ═══════════════════════════════════════════════════════════════════════════════
# FP_EXIT Milestone Configuration
# Floorplan Exit - Design ready for placement
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "FP_EXIT"
set milestone_info(stage) "floorplan"
set milestone_info(description) "Floorplan Exit - Design ready for placement"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "floorplan_utilization" {
        "script" "check_utilization.tcl"
        "description" "Validate floorplan utilization is within target range"
        "criteria" "utilization >= 0.6 && utilization <= 0.8"}
}
    "macro_placement" {
        "script" "validate_macro_placement.tcl" 
        "description" "Verify all macros are legally placed"
        "criteria" "all_macros_legal == true"
    }
    "pin_assignment" {
        "script" "validate_pin_assignment.tcl"
        "description" "Check pin assignment and accessibility"
        "criteria" "pin_accessibility >= 0.95"
    }
    "power_domains" {
        "script" "check_power_domains.tcl"
        "description" "Validate power domain setup"
        "criteria" "power_domains_defined == true"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "congestion_analysis" {
        "script" "check_congestion.tcl"
        "description" "Early congestion analysis"
        "criteria" "max_congestion <= 0.8"
    }
    "timing_estimate" {
        "script" "early_timing_check.tcl"
        "description" "Early timing estimation"
        "criteria" "estimated_wns >= -200ps"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "work/FP/floorplan.enc"
    "reports/floorplan/floorplan.rpt"
    "reports/floorplan/utilization.rpt"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "floorplan_def" {
        "source" "work/FP/floorplan.enc"
        "target" "def/floorplan_exit.def"
        "type" "design_file"
    }
    "floorplan_report" {
        "source" "reports/floorplan/floorplan.rpt"
        "target" "reports/floorplan_exit_summary.rpt"
        "type" "report"
    }
    "constraint_script" {
        "source" "setup/floorplan_constraints.tcl"
        "target" "utils/floorplan_constraints.tcl"
        "type" "script"
    }
}