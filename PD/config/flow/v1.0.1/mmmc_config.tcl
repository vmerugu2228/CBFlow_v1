#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW Multi-Mode Multi-Corner (MMMC) Configuration - Simplified
# User-controlled scenario selection through override.tcl and makefile targets
# ═══════════════════════════════════════════════════════════════════════════════

# Global MMMC configuration
array set mmmc_config {
    enabled                 true
    version                 "3.0"
    timing_derate_early    0.95
    timing_derate_late     1.05
    clock_uncertainty      0.1
    max_transition         0.5
    max_capacitance        2.0
    max_fanout             16
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROCESS CORNERS DEFINITION
# ═══════════════════════════════════════════════════════════════════════════════

array set process_corners {
    ss {
        name                "slow_slow"
        description         "Slow NMOS, Slow PMOS (worst setup timing)"
        voltage_nominal     0.80
        voltage_low         0.76
        voltage_high        0.84
        temperature_hot     150
        temperature_nom     25
        temperature_cold    -40
        process_condition   "slow"
        setup_critical      true
        hold_critical       false
        leakage_critical    false
    }

    tt {
        name                "typical_typical"
        description         "Typical NMOS, Typical PMOS (nominal)"
        voltage_nominal     0.80
        voltage_low         0.76
        voltage_high        0.84
        temperature_hot     150
        temperature_nom     25
        temperature_cold    -40
        process_condition   "typical"
        setup_critical      false
        hold_critical       false
        leakage_critical    false
    }

    ff {
        name                "fast_fast"
        description         "Fast NMOS, Fast PMOS (worst hold timing)"
        voltage_nominal     0.80
        voltage_low         0.76
        voltage_high        0.84
        temperature_hot     150
        temperature_nom     25
        temperature_cold    -40
        process_condition   "fast"
        setup_critical      false
        hold_critical       true
        leakage_critical    true
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# OPERATING MODES DEFINITION
# ═══════════════════════════════════════════════════════════════════════════════

array set operating_modes {
    func {
        name                "functional"
        description         "Normal functional operation mode"
        voltage_nom         0.80
        voltage_low         0.76
        voltage_high        0.84
        clock_frequency     "1000MHz"
        constraint_file     "ravendrive_func.sdc"
    }

    test {
        name                "test"
        description         "DFT scan test mode"
        voltage_nom         0.80
        voltage_low         0.76
        voltage_high        0.84
        clock_frequency     "100MHz"
        constraint_file     "ravendrive_test.sdc"
    }

}

# ═══════════════════════════════════════════════════════════════════════════════
# PREDEFINED SCENARIO SETS FOR MAKEFILE TARGETS
# ═══════════════════════════════════════════════════════════════════════════════

# Predefined scenario sets for different analysis types
# ═══════════════════════════════════════════════════════════════════════════════
# SCENARIO NAMING CONVENTION
# ═══════════════════════════════════════════════════════════════════════════════
# Format: <mode>_<corner>_<voltage>_<rc_corner>_<temperature>
#
# PVT Corners:
#   P = SS (slow)  >= TT (typical) <= FF (fast)
#   V = 0.76V (low, -5%) >= 0.80V (nom) <= 0.84V (high, +5%)
#   T = -40C (cold) <= 25C (nom) <= 150C (hot)
#
# Modes: func (functional), test (DFT), lp (low power)
# RC Corners: rcmax (max parasitic), rctyp (typical), rcmin (min parasitic)
#
# Setup-critical:  SS corner, low voltage, high temp, max RC
# Hold-critical:   FF corner, high voltage, low temp, min RC
# ═══════════════════════════════════════════════════════════════════════════════

array set mmmc_scenario_sets {
    setup {
        scenarios {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            test_ss_0p76v_rcmax_150c
        }
        description "Setup-critical scenarios (slow corner, low voltage, hot/cold)"
    }

    hold {
        scenarios {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p80v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
        }
        description "Hold-critical scenarios (fast corner, high voltage, cold)"
    }

    power {
        scenarios {
            func_ss_0p80v_rctyp_150c
            func_tt_0p80v_rctyp_25c
            func_ff_0p84v_rctyp_25c
        }
        description "Power analysis scenarios (leakage + dynamic)"
    }

    signoff {
        scenarios {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            func_tt_0p80v_rctyp_25c
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p80v_rcmin_m40c
            test_ss_0p76v_rcmax_150c
            test_tt_0p80v_rctyp_25c
            test_ff_0p84v_rcmin_m40c
        }
        description "Complete signoff scenarios (setup + hold + nominal)"
    }

    all {
        scenarios {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            func_ss_0p80v_rcmax_25c
            func_tt_0p80v_rctyp_150c
            func_tt_0p80v_rctyp_25c
            func_tt_0p80v_rctyp_m40c
            func_ff_0p84v_rcmin_150c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
            func_ff_0p80v_rcmin_m40c
            test_ss_0p76v_rcmax_150c
            test_ss_0p80v_rcmax_150c
            test_tt_0p80v_rctyp_25c
            test_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_25c
        }
        description "All available scenarios (22 total)"
    }

    sta_setup {
        scenarios {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            test_ss_0p76v_rcmax_150c
        }
        description "STA setup-critical scenarios"
    }

    sta_hold {
        scenarios {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p80v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
        }
        description "STA hold-critical scenarios (worst-case hold timing)"
    }

    sta_signoff {
        scenarios {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p80v_rcmin_m40c
            func_tt_0p80v_rctyp_25c
            test_ss_0p76v_rcmax_150c
            test_ff_0p84v_rcmin_m40c
            test_tt_0p80v_rctyp_25c
        }
        description "STA full signoff scenarios (13 scenarios: setup + hold + nominal)"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ANALYSIS VIEWS DEFINITION
# ═══════════════════════════════════════════════════════════════════════════════
#
# Each view maps to: corner + mode + voltage + temperature + RC corner
# lib_set_ref maps to the library_sets array in tech_config.tcl
# analysis_type: "setup" (slow/hot), "hold" (fast/cold), "setup_hold" (nominal)

array set analysis_views {
    "func_ss_0p76v_rcmax_150c" {
        corner "ss" mode "func" voltage 0.76 temperature 150
        analysis_type "setup" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ss_0760v_150c" rc_corner "rc_max"
        description "Func worst setup: SS, 0.76V, 150C, max RC"
    }
    "func_ss_0p76v_rcmax_25c" {
        corner "ss" mode "func" voltage 0.76 temperature 25
        analysis_type "setup" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ss_0760v_25c" rc_corner "rc_max"
        description "Func setup: SS, 0.76V, 25C, max RC"
    }
    "func_ss_0p76v_rcmax_m40c" {
        corner "ss" mode "func" voltage 0.76 temperature -40
        analysis_type "setup" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ss_0760v_m40c" rc_corner "rc_max"
        description "Func setup cold: SS, 0.76V, -40C, max RC"
    }
    "func_ss_0p80v_rcmax_150c" {
        corner "ss" mode "func" voltage 0.80 temperature 150
        analysis_type "setup" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ss_0800v_150c" rc_corner "rc_max"
        description "Func setup nom-V: SS, 0.80V, 150C, max RC"
    }
    "func_ss_0p80v_rcmax_25c" {
        corner "ss" mode "func" voltage 0.80 temperature 25
        analysis_type "setup" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ss_0800v_25c" rc_corner "rc_max"
        description "Func setup nom: SS, 0.80V, 25C, max RC"
    }

    "func_tt_0p80v_rctyp_150c" {
        corner "tt" mode "func" voltage 0.80 temperature 150
        analysis_type "setup_hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "tt_0800v_150c" rc_corner "rc_typ"
        description "Func nominal hot: TT, 0.80V, 150C, typ RC"
    }
    "func_tt_0p80v_rctyp_25c" {
        corner "tt" mode "func" voltage 0.80 temperature 25
        analysis_type "setup_hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "tt_0800v_25c" rc_corner "rc_typ"
        description "Func nominal: TT, 0.80V, 25C, typ RC"
    }
    "func_tt_0p80v_rctyp_m40c" {
        corner "tt" mode "func" voltage 0.80 temperature -40
        analysis_type "setup_hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "tt_0800v_m40c" rc_corner "rc_typ"
        description "Func nominal cold: TT, 0.80V, -40C, typ RC"
    }

    "func_ff_0p84v_rcmin_150c" {
        corner "ff" mode "func" voltage 0.84 temperature 150
        analysis_type "hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ff_0840v_150c" rc_corner "rc_min"
        description "Func hold hot: FF, 0.84V, 150C, min RC"
    }
    "func_ff_0p84v_rcmin_25c" {
        corner "ff" mode "func" voltage 0.84 temperature 25
        analysis_type "hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ff_0840v_25c" rc_corner "rc_min"
        description "Func hold nom: FF, 0.84V, 25C, min RC"
    }
    "func_ff_0p84v_rcmin_m40c" {
        corner "ff" mode "func" voltage 0.84 temperature -40
        analysis_type "hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ff_0840v_m40c" rc_corner "rc_min"
        description "Func worst hold: FF, 0.84V, -40C, min RC"
    }
    "func_ff_0p80v_rcmin_m40c" {
        corner "ff" mode "func" voltage 0.80 temperature -40
        analysis_type "hold" constraint_file "ravendrive_func.sdc"
        lib_set_ref "ff_0800v_m40c" rc_corner "rc_min"
        description "Func hold nom-V: FF, 0.80V, -40C, min RC"
    }

    "test_ss_0p76v_rcmax_150c" {
        corner "ss" mode "test" voltage 0.76 temperature 150
        analysis_type "setup" constraint_file "ravendrive_test.sdc"
        lib_set_ref "ss_0760v_150c" rc_corner "rc_max"
        description "Test worst setup: SS, 0.76V, 150C, max RC"
    }
    "test_ss_0p80v_rcmax_150c" {
        corner "ss" mode "test" voltage 0.80 temperature 150
        analysis_type "setup" constraint_file "ravendrive_test.sdc"
        lib_set_ref "ss_0800v_150c" rc_corner "rc_max"
        description "Test setup nom-V: SS, 0.80V, 150C, max RC"
    }

    "test_tt_0p80v_rctyp_25c" {
        corner "tt" mode "test" voltage 0.80 temperature 25
        analysis_type "setup_hold" constraint_file "ravendrive_test.sdc"
        lib_set_ref "tt_0800v_25c" rc_corner "rc_typ"
        description "Test nominal: TT, 0.80V, 25C, typ RC"
    }

    "test_ff_0p84v_rcmin_m40c" {
        corner "ff" mode "test" voltage 0.84 temperature -40
        analysis_type "hold" constraint_file "ravendrive_test.sdc"
        lib_set_ref "ff_0840v_m40c" rc_corner "rc_min"
        description "Test worst hold: FF, 0.84V, -40C, min RC"
    }
    "test_ff_0p84v_rcmin_25c" {
        corner "ff" mode "test" voltage 0.84 temperature 25
        analysis_type "hold" constraint_file "ravendrive_test.sdc"
        lib_set_ref "ff_0840v_25c" rc_corner "rc_min"
        description "Test hold nom: FF, 0.84V, 25C, min RC"
    }

}

# ═══════════════════════════════════════════════════════════════════════════════
# RC CORNERS DEFINITION
# ═══════════════════════════════════════════════════════════════════════════════

array set rc_corners {
    rc_max {
        name                "rc_max"
        description         "Maximum RC (worst setup)"
        temperature         125
        metal_multiplier    1.15
        via_multiplier      1.25
        cap_multiplier      1.10
        res_multiplier      1.15
        usage               "setup_critical"
    }
    
    rc_typ {
        name                "rc_typ"
        description         "Typical RC (nominal)"
        temperature         25
        metal_multiplier    1.00
        via_multiplier      1.00
        cap_multiplier      1.00
        res_multiplier      1.00
        usage               "nominal"
    }
    
    rc_min {
        name                "rc_min"
        description         "Minimum RC (worst hold)"
        temperature         -40
        metal_multiplier    0.85
        via_multiplier      0.75
        cap_multiplier      0.90
        res_multiplier      0.85
        usage               "hold_critical"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# NODE-SPECIFIC MMMC SCENARIO ASSIGNMENTS
# ═══════════════════════════════════════════════════════════════════════════════

# Hardcoded scenario assignments for each PNR node
# User configures specific setup/hold scenarios for each stage
array set mmmc {
    # ── Early PNR stages (fewer scenarios) ────────────────────────────────
    init_design {
        setup {func_tt_0p80v_rctyp_25c}
        hold  {func_tt_0p80v_rctyp_25c}
    }

    floorplan {
        setup {func_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c}
    }

    powerplan {
        setup {func_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c}
    }

    placement {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
        }
        hold {
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
        }
    }

    # ── Mid PNR stages (moderate scenarios) ───────────────────────────────
    cts {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            test_ss_0p76v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
        }
    }

    route {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            test_ss_0p76v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
        }
    }

    # ── Late PNR stages (comprehensive scenarios) ─────────────────────────
    post_route {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p80v_rcmax_150c
            func_tt_0p80v_rctyp_25c
            test_ss_0p76v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
            func_tt_0p80v_rctyp_25c
            test_ff_0p84v_rcmin_m40c
        }
    }

    signoff {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            test_ss_0p76v_rcmax_150c
            test_ss_0p80v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_150c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_m40c
            func_ff_0p80v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_25c
        }
    }

    # ── SYNTH Node Scenarios (multi-corner compile) ──────────────────────────
    synthesis {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            test_ss_0p76v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

proc get_scenario_set {type} {
    global mmmc_scenario_sets
    if {[info exists mmmc_scenario_sets($type)]} {
        array set set_info $mmmc_scenario_sets($type)
        return $set_info(scenarios)
    }
    return {}
}

proc list_scenario_sets {} {
    global mmmc_scenario_sets
    puts "Available MMMC scenario sets:"
    foreach type [lsort [array names mmmc_scenario_sets]] {
        array set set_info $mmmc_scenario_sets($type)
        set count [llength $set_info(scenarios)]
        puts "  $type ($count scenarios): $set_info(description)"
    }
}

proc get_analysis_view {scenario_name} {
    global analysis_views
    if {[info exists analysis_views($scenario_name)]} {
        return $analysis_views($scenario_name)
    }
    return {}
}

proc list_all_scenarios {} {
    global analysis_views
    puts "All available MMMC scenarios:"
    foreach scenario [lsort [array names analysis_views]] {
        array set view_info $analysis_views($scenario)
        puts "  $scenario: $view_info(description)"
    }
}

proc is_mmmc_enabled {} {
    global mmmc_config
    return $mmmc_config(enabled)
}

proc get_node_scenarios {node_name {analysis_type "all"}} {
    # Get MMMC scenarios for a specific flow node (e.g., "placement", "cts", "synthesis")
    # analysis_type: "setup", "hold", or "all" (returns combined unique list)
    global mmmc
    if {![info exists mmmc($node_name)]} {
        return {}
    }
    array set node_info $mmmc($node_name)
    switch $analysis_type {
        "setup" { return $node_info(setup) }
        "hold"  { return $node_info(hold) }
        "all"   {
            set combined $node_info(setup)
            foreach s $node_info(hold) {
                if {$s ni $combined} { lappend combined $s }
            }
            return $combined
        }
    }
    return {}
}

proc list_mmmc_nodes {} {
    # List all nodes with MMMC scenario assignments
    global mmmc
    puts "MMMC Node Scenario Assignments:"
    puts [string repeat "=" 70]
    foreach node [lsort [array names mmmc]] {
        array set node_info $mmmc($node)
        set setup_count [llength $node_info(setup)]
        set hold_count [llength $node_info(hold)]
        puts "  $node: $setup_count setup, $hold_count hold scenarios"
        array unset node_info
    }
    puts [string repeat "=" 70]
}

proc get_node_setup_scenarios {node_name} {
    return [get_node_scenarios $node_name "setup"]
}

proc get_node_hold_scenarios {node_name} {
    return [get_node_scenarios $node_name "hold"]
}

proc create_mmmc_scenarios_for_node {node_name} {
    # FC/Innovus: create analysis views for a node's scenarios
    # Returns list of created scenario names
    global analysis_views
    set scenarios [get_node_scenarios $node_name "all"]
    set created {}
    foreach scenario $scenarios {
        if {[info exists analysis_views($scenario)]} {
            array set view $analysis_views($scenario)
            puts "INFO: Creating scenario: $scenario ($view(description))"
            lappend created $scenario
            array unset view
        } else {
            puts "WARNING: Scenario $scenario not found in analysis_views"
        }
    }
    return $created
}


puts "INFO: MMMC configuration loaded successfully"
puts "INFO: MMMC enabled: $mmmc_config(enabled)"
puts "INFO: Analysis views defined: [llength [array names analysis_views]]"
puts "INFO: Scenario sets available: [join [array names mmmc_scenario_sets] { }]"
puts "INFO: Node scenarios configured: [llength [array names mmmc]] nodes"
puts "INFO: Use list_scenario_sets to see available sets"
puts "INFO: Use list_mmmc_nodes to see node-specific scenarios"
puts "INFO: Use get_node_scenarios <node> to get scenarios for a specific node"