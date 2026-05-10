# ═══════════════════════════════════════════════════════════════════════════════
# PLACE_EXIT Milestone Configuration
# Placement Exit - Design ready for Clock Tree Synthesis (CTS)
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "PLACE_EXIT"
set milestone_info(stage) "placement"
set milestone_info(description) "Placement Exit - Design ready for Clock Tree Synthesis (CTS)"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "placement_legality" {
        "script" "check_placement_legality.tcl"
        "description" "Validate all cells are legally placed"
        "criteria" "illegal_cells == 0"
    }
    "placement_density" {
        "script" "check_placement_density.tcl" 
        "description" "Verify placement density is within acceptable range"
        "criteria" "density >= 0.7 && density <= 0.85"
    }
    "timing_closure" {
        "script" "validate_timing_closure.tcl"
        "description" "Check timing meets setup requirements"
        "criteria" "setup_wns >= -50ps && setup_tns >= -500ps"
    }
    "congestion_analysis" {
        "script" "check_congestion.tcl"
        "description" "Validate congestion levels are acceptable"
        "criteria" "max_congestion <= 0.85"
    }
    "power_analysis" {
        "script" "check_power.tcl"
        "description" "Verify power consumption is within budget"
        "criteria" "total_power <= power_budget"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "hold_timing" {
        "script" "check_hold_timing.tcl"
        "description" "Early hold timing analysis"
        "criteria" "hold_wns >= -10ps"
    }
    "IR_drop_analysis" {
        "script" "check_ir_drop.tcl"
        "description" "Early IR drop analysis"
        "criteria" "max_ir_drop <= 50mV"
    }
    "placement_quality" {
        "script" "check_placement_quality.tcl"
        "description" "Placement quality metrics"
        "criteria" "displacement_quality >= 0.8"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "work/PNR/placement.enc"
    "reports/place/placement_summary.rpt"
    "reports/timing/setup_timing.rpt"
    "reports/congestion/congestion_map.rpt"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "placement_def" {
        "source" "work/PNR/placement.enc"
        "target" "def/placement_exit.def"
        "type" "design_file"
    }
    "placement_report" {
        "source" "reports/place/placement_summary.rpt"
        "target" "reports/placement_exit_summary.rpt"
        "type" "report"
    }
    "timing_report" {
        "source" "reports/timing/setup_timing.rpt"
        "target" "reports/timing_exit_summary.rpt"
        "type" "report"
    }
    "congestion_report" {
        "source" "reports/congestion/congestion_map.rpt"
        "target" "reports/congestion_exit_summary.rpt"
        "type" "report"
    }
    "placement_script" {
        "source" "setup/placement_constraints.tcl"
        "target" "utils/placement_constraints.tcl"
        "type" "script"
    }
}