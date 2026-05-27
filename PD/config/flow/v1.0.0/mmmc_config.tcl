#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW Multi-Mode Multi-Corner (MMMC) Configuration - Simplified
# User-controlled scenario selection through override.tcl and makefile targets
# ═══════════════════════════════════════════════════════════════════════════════

# Global MMMC configuration
array set mmmc_config {
    timing_derate_early    0.95
    timing_derate_late     1.05
    clock_uncertainty      0.1
    max_transition         0.5
    max_capacitance        2.0
    max_fanout             16
}

# ═══════════════════════════════════════════════════════════════════════════════
# VOLTAGE & TEMPERATURE — single source of truth
# Override in project_config or user_config for different operating points
# ═══════════════════════════════════════════════════════════════════════════════

set mmmc(voltage,nom)        0.80
set mmmc(voltage,low)        0.76
set mmmc(voltage,high)       0.84
set mmmc(temperature,hot)    150
set mmmc(temperature,nom)    25
set mmmc(temperature,cold)   -40

# ═══════════════════════════════════════════════════════════════════════════════
# PROCESS CORNERS & OPERATING MODES
# ═══════════════════════════════════════════════════════════════════════════════

set mmmc(process_corners) {ss tt ff}

# ═══════════════════════════════════════════════════════════════════════════════
# OPERATING MODES DEFINITION
# Voltage resolved from mmmc() variables above
# ═══════════════════════════════════════════════════════════════════════════════

array set operating_modes {
    func { constraint_file "${design_name}_func.sdc" }
    test { constraint_file "${design_name}_test.sdc" }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PVT COMBINATIONS & RC PAIRING RULES
# Format: <mode>_<corner>_<voltage>_<rc_corner>_<temperature>
# ═══════════════════════════════════════════════════════════════════════════════

# PVT points per corner — {voltage temperature} pairs that exist in tech_config
# Full PVT combinations: all voltages × all temperatures per corner
set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c} {0p76v m40c} {0p80v 150c} {0p80v 25c} {0p80v m40c} {0p84v 150c} {0p84v 25c} {0p84v m40c}}
set mmmc(pvt,tt) {{0p76v 150c} {0p76v 25c} {0p76v m40c} {0p80v 150c} {0p80v 25c} {0p80v m40c} {0p84v 150c} {0p84v 25c} {0p84v m40c}}
set mmmc(pvt,ff) {{0p76v 150c} {0p76v 25c} {0p76v m40c} {0p80v 150c} {0p80v 25c} {0p80v m40c} {0p84v 150c} {0p84v 25c} {0p84v m40c}}

# Corner → RC corner pairing
set mmmc(rc_pair,ss) "rcmax"
set mmmc(rc_pair,tt) "rctyp"
set mmmc(rc_pair,ff) "rcmin"

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-GENERATE ANALYSIS VIEWS & SCENARIO SETS
# Views generated from: modes × corners × PVT points
# Format: <mode>_<corner>_<voltage>_<rc_corner>_<temperature>
# ═══════════════════════════════════════════════════════════════════════════════

# ── Generate analysis_views from building blocks ──
array set analysis_views {}
foreach _mode [array names operating_modes] {
    set _sdc [dict get $operating_modes($_mode) constraint_file]
    foreach _corner $mmmc(process_corners) {
        set _rc $mmmc(rc_pair,$_corner)
        switch $_corner {
            ss { set _atype "setup" }
            tt { set _atype "setup_hold" }
            ff { set _atype "hold" }
        }
        foreach _pvt $mmmc(pvt,$_corner) {
            set _v [lindex $_pvt 0]
            set _t [lindex $_pvt 1]
            set _name "${_mode}_${_corner}_${_v}_${_rc}_${_t}"
            set _lib_ref "${_corner}_${_v}_${_t}"
            set analysis_views($_name) [list \
                corner $_corner mode $_mode voltage $_v temperature $_t \
                analysis_type $_atype constraint_file $_sdc \
                lib_set_ref $_lib_ref rc_corner $_rc \
            ]
        }
    }
}

# ── Generate scenario sets by filtering views ──
set _all [lsort [array names analysis_views]]

array set mmmc_scenario_sets {}
set mmmc_scenario_sets(setup)       [lsearch -all -inline $_all "*_ss_*"]
set mmmc_scenario_sets(hold)        [lsearch -all -inline $_all "*_ff_*"]
set mmmc_scenario_sets(power)       [concat \
    [lsearch -all -inline $_all "*_tt_*_rctyp_*"] \
    [lsearch -all -inline $_all "*_ss_*_rctyp_*"] \
]
set mmmc_scenario_sets(signoff)     [concat \
    $mmmc_scenario_sets(setup) \
    $mmmc_scenario_sets(hold) \
    [lsearch -all -inline $_all "func_tt_*_rctyp_25c"] \
]
set mmmc_scenario_sets(all)         $_all
set mmmc_scenario_sets(sta_setup)   $mmmc_scenario_sets(setup)
set mmmc_scenario_sets(sta_hold)    $mmmc_scenario_sets(hold)
set mmmc_scenario_sets(sta_signoff) $mmmc_scenario_sets(signoff)

# ═══════════════════════════════════════════════════════════════════════════════
# RC CORNERS DEFINITION
# ═══════════════════════════════════════════════════════════════════════════════

# RC corner definitions — multipliers for parasitic extraction
# Parasitic files resolved from tech(rcx,<corner>,tluplus/qrc/nxtgrd) in tech_config
array set rc_corners {
    rc_max {
        temperature         125
        metal_multiplier    1.15
        via_multiplier      1.25
        cap_multiplier      1.10
        res_multiplier      1.15
    }
    rc_typ {
        temperature         25
        metal_multiplier    1.00
        via_multiplier      1.00
        cap_multiplier      1.00
        res_multiplier      1.00
    }
    rc_min {
        temperature         -40
        metal_multiplier    0.85
        via_multiplier      0.75
        cap_multiplier      0.90
        res_multiplier      0.85
    }
    rc_max_cworst {
        temperature         125
        metal_multiplier    1.15
        via_multiplier      1.25
        cap_multiplier      1.20
        res_multiplier      1.10
    }
}

# Ordered list for dynamic extraction subnodes
set rc_corner_list [lsort [array names rc_corners]]

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

    cts_opt {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
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
    if {[info exists mmmc_scenario_sets($type)]} { return $mmmc_scenario_sets($type) }
    return {}
}

proc get_analysis_view {scenario_name} {
    global analysis_views
    if {[info exists analysis_views($scenario_name)]} { return $analysis_views($scenario_name) }
    return {}
}

proc get_node_scenarios {node_name {analysis_type "all"}} {
    global mmmc
    if {![info exists mmmc($node_name)]} { return {} }
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

puts "INFO: MMMC loaded — [llength [array names analysis_views]] views, [llength [array names mmmc]] node assignments"