# ═══════════════════════════════════════════════════════════════════════════════
# BTO Milestone Configuration
# Backend Tape Out - Design ready for Mask Generation
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "BTO"
set milestone_info(stage) "backend_tapeout"
set milestone_info(description) "Backend Tape Out - Design ready for Mask Generation"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "gds_integrity" {
        "script" "check_gds_integrity.tcl"
        "description" "Validate GDS file integrity and completeness"
        "criteria" "gds_errors == 0 && gds_completeness == 100%"
    }
    "drc_clean" {
        "script" "validate_drc_clean.tcl" 
        "description" "Final DRC verification - must be completely clean"
        "criteria" "drc_violations == 0"
    }
    "lvs_clean" {
        "script" "validate_lvs_clean.tcl"
        "description" "Layout vs Schematic verification - must match"
        "criteria" "lvs_match == true && lvs_errors == 0"
    }
    "antenna_clean" {
        "script" "check_antenna_final.tcl"
        "description" "Final antenna rule compliance"
        "criteria" "antenna_violations == 0"
    }
    "metal_density" {
        "script" "validate_metal_density.tcl"
        "description" "Metal density compliance for all layers"
        "criteria" "metal_density_violations == 0"
    }
    "timing_closure" {
        "script" "final_timing_signoff.tcl"
        "description" "Final timing signoff with SPEF"
        "criteria" "setup_wns >= 0ps && hold_wns >= 0ps"
    }
    "power_signoff" {
        "script" "final_power_signoff.tcl"
        "description" "Final power analysis and signoff"
        "criteria" "power_violations == 0 && em_violations == 0"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "reliability_check" {
        "script" "check_reliability.tcl"
        "description" "Reliability analysis including aging effects"
        "criteria" "reliability_margin >= 10%"
    }
    "yield_analysis" {
        "script" "check_yield_impact.tcl"
        "description" "Yield impact analysis"
        "criteria" "yield_loss <= 5%"
    }
    "thermal_analysis" {
        "script" "check_thermal.tcl"
        "description" "Thermal hotspot analysis"
        "criteria" "max_temperature <= thermal_limit"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "results/gds/final.gds"
    "results/netlist/final_lvs.v"
    "results/sdc/final_signoff.sdc"
    "results/spef/final_signoff.spef"
    "reports/drc/final_drc.rpt"
    "reports/lvs/final_lvs.rpt"
    "reports/timing/final_timing.rpt"
    "reports/power/final_power.rpt"
    "outputs/${design_name}.gds"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "final_gds" {
        "source" "results/gds/final.gds"
        "target" "tapeout/final_design.gds"
        "type" "layout"
    }
    "final_netlist" {
        "source" "results/netlist/final_lvs.v"
        "target" "tapeout/final_design.v"
        "type" "netlist"
    }
    "final_lef" {
        "source" "results/lef/final.lef"
        "target" "tapeout/final_design.lef"
        "type" "abstract"
    }
    "timing_constraints" {
        "source" "results/sdc/final_signoff.sdc"
        "target" "tapeout/timing_constraints.sdc"
        "type" "constraint"
    }
    "parasitics" {
        "source" "results/spef/final_signoff.spef"
        "target" "tapeout/parasitics.spef"
        "type" "parasitic"
    }
    "drc_signoff" {
        "source" "reports/drc/final_drc.rpt"
        "target" "tapeout/drc_signoff.rpt"
        "type" "verification"
    }
    "lvs_signoff" {
        "source" "reports/lvs/final_lvs.rpt"
        "target" "tapeout/lvs_signoff.rpt"
        "type" "verification"
    }
    "timing_signoff" {
        "source" "reports/timing/final_timing.rpt"
        "target" "tapeout/timing_signoff.rpt"
        "type" "report"
    }
    "power_signoff" {
        "source" "reports/power/final_power.rpt"
        "target" "tapeout/power_signoff.rpt"
        "type" "report"
    }
    "tapeout_checklist" {
        "source" "docs/tapeout_checklist.md"
        "target" "tapeout/tapeout_checklist.md"
        "type" "documentation"
    }
}