# ═══════════════════════════════════════════════════════════════════════════════
# CTS_EXIT Milestone Configuration
# Clock Tree Synthesis Exit - Design ready for Routing
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "CTS_EXIT"
set milestone_info(stage) "clock_tree_synthesis"
set milestone_info(description) "Clock Tree Synthesis Exit - Design ready for Routing"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "clock_tree_quality" {
        "script" "check_clock_tree_quality.tcl"
        "description" "Validate clock tree structure and quality"
        "criteria" "clock_skew <= 50ps && max_insertion_delay <= 500ps"
    }
    "clock_timing" {
        "script" "validate_clock_timing.tcl" 
        "description" "Check clock timing meets setup/hold requirements"
        "criteria" "setup_wns >= -30ps && hold_wns >= -10ps"
    }
    "clock_power" {
        "script" "check_clock_power.tcl"
        "description" "Verify clock tree power consumption"
        "criteria" "clock_power <= clock_power_budget"
    }
    "clock_coverage" {
        "script" "validate_clock_coverage.tcl"
        "description" "Check all sequential elements are properly clocked"
        "criteria" "clock_coverage >= 99.5%"
    }
    "useful_skew" {
        "script" "check_useful_skew.tcl"
        "description" "Validate useful skew optimization"
        "criteria" "useful_skew_benefit >= 20ps"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "clock_latency" {
        "script" "check_clock_latency.tcl"
        "description" "Clock latency analysis"
        "criteria" "max_clock_latency <= 400ps"
    }
    "clock_transition" {
        "script" "check_clock_transitions.tcl"
        "description" "Clock transition time analysis"
        "criteria" "max_clock_transition <= 100ps"
    }
    "cts_congestion" {
        "script" "check_cts_congestion.tcl"
        "description" "Congestion impact from clock tree"
        "criteria" "cts_congestion_impact <= 0.1"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "work/PNR/cts.enc"
    "reports/cts/clock_tree_summary.rpt"
    "reports/timing/cts_timing.rpt"
    "reports/power/clock_power.rpt"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "cts_def" {
        "source" "work/PNR/cts.enc"
        "target" "def/cts_exit.def"
        "type" "design_file"
    }
    "clock_tree_report" {
        "source" "reports/cts/clock_tree_summary.rpt"
        "target" "reports/cts_exit_summary.rpt"
        "type" "report"
    }
    "cts_timing_report" {
        "source" "reports/timing/cts_timing.rpt"
        "target" "reports/cts_timing_exit.rpt"
        "type" "report"
    }
    "clock_power_report" {
        "source" "reports/power/clock_power.rpt"
        "target" "reports/clock_power_exit.rpt"
        "type" "report"
    }
    "cts_script" {
        "source" "setup/cts_constraints.tcl"
        "target" "utils/cts_constraints.tcl"
        "type" "script"
    }
    "clock_spec" {
        "source" "setup/clock_specification.tcl"
        "target" "specs/clock_specification.tcl"
        "type" "specification"
    }
}