# ═══════════════════════════════════════════════════════════════════════════════
# MTO Milestone Configuration
# Mask Tape Out - Final delivery for Mask Shop
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone information
set milestone_info(name) "MTO"
set milestone_info(stage) "mask_tapeout"
set milestone_info(description) "Mask Tape Out - Final delivery for Mask Shop"

# Mandatory checks that must pass for milestone exit
array set mandatory_checks {
    "mask_shop_drc" {
        "script" "check_mask_shop_drc.tcl"
        "description" "Mask shop specific DRC rules compliance"
        "criteria" "mask_drc_violations == 0"
    }
    "opc_readiness" {
        "script" "validate_opc_readiness.tcl" 
        "description" "Optical Proximity Correction readiness check"
        "criteria" "opc_compatibility == 100%"
    }
    "fracture_check" {
        "script" "check_fracture_compliance.tcl"
        "description" "E-beam fracture and shot count optimization"
        "criteria" "fracture_violations == 0 && shot_count_optimized == true"
    }
    "datapath_integrity" {
        "script" "validate_datapath_integrity.tcl"
        "description" "GDS datapath and hierarchy integrity"
        "criteria" "datapath_errors == 0 && hierarchy_intact == true"
    }
    "mask_layers" {
        "script" "check_mask_layers.tcl"
        "description" "All required mask layers present and correct"
        "criteria" "missing_layers == 0 && layer_mapping_correct == true"
    }
    "reticle_placement" {
        "script" "validate_reticle_placement.tcl"
        "description" "Reticle placement and stepping verification"
        "criteria" "reticle_violations == 0"
    }
    "jobdeck_validation" {
        "script" "check_jobdeck.tcl"
        "description" "Mask generation jobdeck validation"
        "criteria" "jobdeck_errors == 0"
    }
}

# Optional checks (warnings if failed, but don't block exit)
array set optional_checks {
    "mask_cost_optimization" {
        "script" "check_mask_cost.tcl"
        "description" "Mask cost optimization analysis"
        "criteria" "cost_optimized == true"
    }
    "cycle_time_check" {
        "script" "check_cycle_time.tcl"
        "description" "Mask manufacturing cycle time estimate"
        "criteria" "cycle_time <= target_time"
    }
    "defect_analysis" {
        "script" "check_defect_sensitivity.tcl"
        "description" "Critical area and defect sensitivity analysis"
        "criteria" "critical_area <= threshold"
    }
}

# Mandatory files that must exist for milestone exit
set mandatory_files {
    "tapeout/final_design.gds"
    "tapeout/mask_jobdeck.txt"
    "tapeout/layer_mapping.txt"
    "tapeout/reticle_floorplan.gds"
    "reports/mask_drc/final_mask_drc.rpt"
    "reports/fracture/fracture_analysis.rpt"
    "docs/mask_specifications.pdf"
}

# Deliverables to be generated for this milestone
array set deliverables {
    "mask_gds" {
        "source" "tapeout/final_design.gds"
        "target" "delivery/mask_ready.gds"
        "type" "layout"
    }
    "jobdeck" {
        "source" "tapeout/mask_jobdeck.txt"
        "target" "delivery/mask_jobdeck.txt"
        "type" "jobdeck"
    }
    "layer_map" {
        "source" "tapeout/layer_mapping.txt"
        "target" "delivery/layer_mapping.txt"
        "type" "mapping"
    }
    "reticle_plan" {
        "source" "tapeout/reticle_floorplan.gds"
        "target" "delivery/reticle_floorplan.gds"
        "type" "layout"
    }
    "mask_specifications" {
        "source" "docs/mask_specifications.pdf"
        "target" "delivery/mask_specifications.pdf"
        "type" "documentation"
    }
    "drc_deck" {
        "source" "setup/mask_drc.deck"
        "target" "delivery/drc_runset.deck"
        "type" "runset"
    }
    "mask_drc_report" {
        "source" "reports/mask_drc/final_mask_drc.rpt"
        "target" "delivery/mask_drc_clean.rpt"
        "type" "verification"
    }
    "fracture_report" {
        "source" "reports/fracture/fracture_analysis.rpt"
        "target" "delivery/fracture_summary.rpt"
        "type" "report"
    }
    "delivery_checklist" {
        "source" "docs/mask_delivery_checklist.md"
        "target" "delivery/mask_delivery_checklist.md"
        "type" "documentation"
    }
    "contact_info" {
        "source" "docs/mask_contact_info.txt"
        "target" "delivery/contact_information.txt"
        "type" "documentation"
    }
}