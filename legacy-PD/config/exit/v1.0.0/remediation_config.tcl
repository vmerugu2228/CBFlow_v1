#!/usr/bin/env tclsh
# ============================================================================
# CBFlow Remediation Knowledge Base
# Description: Fix suggestions for common validation failures
# Version: 1.0.0
#
# Maps failure patterns to actionable remediation steps.
# Used by checklist and validation tools to suggest fixes.
# ============================================================================

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     TIMING REMEDIATIONS                                │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    setup_wns,symptom         "Setup WNS violation (negative slack)"
    setup_wns,severity        "high"
    setup_wns,suggestions     {
        "1. Check constraint quality: review SDC for over-constrained paths"
        "2. Optimize critical path: insert buffers, resize cells on critical paths"
        "3. Restructure logic: break long combinational paths with pipeline registers"
        "4. Check clock skew: leverage useful skew to improve setup slack"
        "5. Placement optimization: move critical cells closer together"
        "6. Use higher-drive cells on critical nets"
        "7. Review timing exceptions: false paths, multicycle paths"
    }
    setup_wns,escalation      "If WNS < -200ps after optimization, escalate to timing lead"

    hold_wns,symptom          "Hold WNS violation (negative hold slack)"
    hold_wns,severity         "high"
    hold_wns,suggestions      {
        "1. Insert delay buffers on short paths"
        "2. Check clock tree balance: fix skew causing hold violations"
        "3. Review hold constraints: ensure correct library hold values"
        "4. Post-CTS hold fixing: defer to CTS optimization if pre-CTS"
        "5. Check for min-delay paths through clock gating"
    }
    hold_wns,escalation       "If hold violations persist after CTS_EXIT, escalate to timing lead"

    setup_tns,symptom         "Total Negative Slack exceeds threshold"
    setup_tns,severity        "medium"
    setup_tns,suggestions     {
        "1. Focus on paths with worst slack first (top 10 critical paths)"
        "2. Run incremental optimization with focus on TNS reduction"
        "3. Check for systematic issues: library characterization, PVT corners"
        "4. Review floorplan: macro placement may be causing detours"
        "5. Enable multi-corner optimization if not already active"
    }
    setup_tns,escalation      "If TNS > -5000ps, review floorplan with physical design lead"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     AREA & UTILIZATION REMEDIATIONS                    │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    utilization_high,symptom    "Utilization exceeds maximum threshold"
    utilization_high,severity   "high"
    utilization_high,suggestions {
        "1. Increase die area or reduce blockage areas"
        "2. Review macro placement: consolidate or rearrange"
        "3. Optimize cell selection: use smaller variants where possible"
        "4. Remove redundant logic: scan for unused flip-flops or buffers"
        "5. Check for placement blockages that reduce usable area"
        "6. Review power domain sizing"
    }
    utilization_high,escalation "If utilization > 90%, requires die size review with chip architect"

    utilization_low,symptom     "Utilization below minimum threshold (wasted area)"
    utilization_low,severity    "low"
    utilization_low,suggestions {
        "1. Reduce die area if possible to save cost"
        "2. Add decap cells for better power integrity"
        "3. Tighten placement bounds"
        "4. Review if extra area is reserved for future ECOs"
    }
    utilization_low,escalation  "Informational - no escalation needed unless utilization < 40%"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     CLOCK TREE REMEDIATIONS                            │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    clock_skew,symptom         "Clock skew exceeds threshold"
    clock_skew,severity        "high"
    clock_skew,suggestions     {
        "1. Balance clock tree: adjust buffer sizing and placement"
        "2. Review clock tree exceptions: check for excluded sinks"
        "3. Adjust CTS engine constraints: tighten skew target"
        "4. Check for blockages affecting clock routing"
        "5. Review multi-domain clock interactions"
        "6. Use clock mesh for critical domains"
    }
    clock_skew,escalation      "If skew > 100ps, review clock architecture with clock lead"

    clock_power,symptom        "Clock power exceeds budget"
    clock_power,severity       "medium"
    clock_power,suggestions    {
        "1. Enable clock gating on remaining ungated registers"
        "2. Optimize clock buffer sizing: use minimum-drive where possible"
        "3. Reduce clock tree fanout at higher levels"
        "4. Review clock mesh density if using mesh topology"
        "5. Enable multi-Vt clock cells"
    }
    clock_power,escalation     "If clock power > 40% of total, review with power lead"

    clock_coverage,symptom     "Clock coverage below threshold"
    clock_coverage,severity    "high"
    clock_coverage,suggestions {
        "1. Check for floating clock pins on sequential elements"
        "2. Review clock definitions: ensure all clocks are defined"
        "3. Check for unclocked memories or macros"
        "4. Verify generated clock definitions"
    }
    clock_coverage,escalation  "Must reach 99.5% before CTS_EXIT"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     CONGESTION REMEDIATIONS                            │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    congestion,symptom         "Routing congestion exceeds threshold"
    congestion,severity        "high"
    congestion,suggestions     {
        "1. Improve floorplan: adjust macro placement to reduce routing bottlenecks"
        "2. Add routing blockages in congested areas to force cell spreading"
        "3. Reduce local cell density: add placement blockages"
        "4. Check pin accessibility on macros"
        "5. Increase routing layers if available"
        "6. Enable congestion-aware placement"
        "7. Review power grid density in congested areas"
    }
    congestion,escalation      "If congestion > 95%, requires floorplan revision"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     PHYSICAL VERIFICATION REMEDIATIONS                 │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    drc_violations,symptom     "DRC violations found"
    drc_violations,severity    "high"
    drc_violations,suggestions {
        "1. Run incremental DRC repair in the PNR tool"
        "2. Check for spacing violations: adjust placement or routing"
        "3. Check for width violations: resize wires or vias"
        "4. Review power grid for via/spacing DRC"
        "5. Check for antenna violations: insert diodes"
        "6. Review metal density fill: adjust fill rules"
    }
    drc_violations,escalation  "Must be zero for PRO_EXIT and BTO"

    lvs_mismatch,symptom       "LVS mismatch detected"
    lvs_mismatch,severity      "critical"
    lvs_mismatch,suggestions   {
        "1. Check for missing connections: review open nets"
        "2. Check for shorts: review routing overlap"
        "3. Verify power/ground connections to all cells"
        "4. Check for missing pins on macros"
        "5. Review extracted netlist vs schematic for device mismatches"
        "6. Check for floating gates or dangling wires"
    }
    lvs_mismatch,escalation    "Must resolve before BTO - escalate immediately to design lead"

    ir_drop,symptom            "IR drop exceeds threshold"
    ir_drop,severity           "high"
    ir_drop,suggestions        {
        "1. Strengthen power grid: add stripes or increase width"
        "2. Add decap cells in high drop areas"
        "3. Check power pad placement and bump distribution"
        "4. Reduce switching activity in hot spots"
        "5. Review package model for realistic power delivery"
    }
    ir_drop,escalation         "If IR drop > 50mV, review power grid with power integrity lead"

    em_violations,symptom      "Electromigration violations detected"
    em_violations,severity     "critical"
    em_violations,suggestions  {
        "1. Widen violating wires or add parallel paths"
        "2. Increase via count on high-current connections"
        "3. Review power grid for current density hot spots"
        "4. Check for missing via arrays on power connections"
        "5. Consider metal layer swap for high-current nets"
    }
    em_violations,escalation   "Must be zero for BTO - escalate to reliability lead"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     MANUFACTURING REMEDIATIONS                         │
# └─────────────────────────────────────────────────────────────────────────┘

array set remediation {
    gds_errors,symptom         "GDS integrity errors"
    gds_errors,severity        "critical"
    gds_errors,suggestions     {
        "1. Re-export GDS from PNR database"
        "2. Verify layer mapping table"
        "3. Check for missing cells in GDS library"
        "4. Validate hierarchy flatten settings"
        "5. Check disk space - incomplete write"
    }
    gds_errors,escalation      "Block tapeout until resolved"

    antenna_violations,symptom  "Antenna rule violations"
    antenna_violations,severity "medium"
    antenna_violations,suggestions {
        "1. Insert antenna diodes on violating nets"
        "2. Re-route violating nets through metal jumps"
        "3. Enable antenna-aware routing in PNR tool"
        "4. Check for long wires without breaks"
    }
    antenna_violations,escalation "Must be zero for BTO"

    metal_density,symptom       "Metal density violations"
    metal_density,severity      "medium"
    metal_density,suggestions   {
        "1. Adjust metal fill rules and re-run fill insertion"
        "2. Check for excluded fill areas that are too large"
        "3. Review fill density targets per layer"
        "4. Add manual fill in sparse areas"
    }
    metal_density,escalation    "Must be zero for BTO"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     LOOKUP PROCEDURE                                   │
# └─────────────────────────────────────────────────────────────────────────┘

proc get_remediation {failure_type} {
    global remediation

    set result {}
    foreach field {symptom severity suggestions escalation} {
        set key "${failure_type},${field}"
        if {[info exists remediation($key)]} {
            dict set result $field $remediation($key)
        }
    }

    if {[dict size $result] == 0} {
        dict set result symptom "Unknown failure type: $failure_type"
        dict set result severity "unknown"
        dict set result suggestions {"1. Review log files for detailed error messages" "2. Contact design methodology team"}
        dict set result escalation "Escalate to flow owner"
    }

    return $result
}

proc list_all_remediations {} {
    global remediation
    set types {}

    foreach key [array names remediation "*,symptom"] {
        set type [lindex [split $key ","] 0]
        lappend types $type
    }

    return [lsort -unique $types]
}

puts "INFO: Remediation knowledge base loaded - [llength [list_all_remediations]] failure types defined"
