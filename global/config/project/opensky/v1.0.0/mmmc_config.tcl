#!/usr/bin/env tclsh
# =============================================================================
# CBflow MMMC Configuration — Auto-Generated
# Generated: 2026-11-21 22:03 | Tech: skywater_130nm | Corners: 6
# Source: lib_config.tcl
# Views: 18 | Modes: func | Process: ff ss tt
# Regenerate: cbflow flow mmmc-manager generate --tech skywater_130nm
# =============================================================================

# Global MMMC configuration
array set mmmc_config {
    timing_derate_early    0.95
    timing_derate_late     1.05
    clock_uncertainty      0.1
    max_transition         0.5
    max_capacitance        2.0
    max_fanout             16
}

# =============================================================================
# VOLTAGE & TEMPERATURE (discovered from lib_config corners)
# =============================================================================

set mmmc(voltage,nom)        1.80
set mmmc(voltage,low)        1.60
set mmmc(voltage,high)       1.95
set mmmc(temperature,hot)    100
set mmmc(temperature,nom)    25
set mmmc(temperature,cold)   -40

# =============================================================================
# PROCESS CORNERS & OPERATING MODES
# =============================================================================

set mmmc(process_corners) {ff ss tt}

array set operating_modes {
    func { constraint_file "${design_name}_func.sdc" }
}

# =============================================================================
# PVT POINTS (user-specified, validated against lib_config)
# =============================================================================

set mmmc(pvt,ff) {{1p95v 100c} {1p95v m40c}}
set mmmc(pvt,ss) {{1p60v 100c} {1p60v m40c}}
set mmmc(pvt,tt) {{1p80v 100c} {1p80v 25c}}

# =============================================================================
# RC CORNERS
# =============================================================================

array set rc_corners {
    rc_max {
        temperature             125
        metal_multiplier        1.15
        via_multiplier          1.25
        cap_multiplier          1.10
        res_multiplier          1.15
    }
    rc_min {
        temperature             -40
        metal_multiplier        0.85
        via_multiplier          0.75
        cap_multiplier          0.90
        res_multiplier          0.85
    }
    rc_typ {
        temperature             25
        metal_multiplier        1.00
        via_multiplier          1.00
        cap_multiplier          1.00
        res_multiplier          1.00
    }
}

set rc_corner_list [lsort [array names rc_corners]]

# =============================================================================
# ANALYSIS VIEWS — FULL CARTESIAN: mode x corner x pvt x rc_corner
# The framework imposes no setup/hold role and no corner -> RC pairing.
# Engineers pick the views for each purpose in mmmc_scenario_sets below.
# View name: ${mode}_${corner}_${voltage}_${rc_corner}_${temp}
# =============================================================================

array set analysis_views {}
foreach _mode [array names operating_modes] {
    set _sdc [dict get $operating_modes($_mode) constraint_file]
    foreach _corner $mmmc(process_corners) {
        if {![info exists mmmc(pvt,$_corner)]} continue
        foreach _pvt $mmmc(pvt,$_corner) {
            set _v [lindex $_pvt 0]
            set _t [lindex $_pvt 1]
            foreach _rc_name [array names rc_corners] {
                set _name "${_mode}_${_corner}_${_v}_${_rc_name}_${_t}"
                set _lib_ref "${_corner}_${_v}_${_t}"
                set analysis_views($_name) [list \
                    corner $_corner mode $_mode voltage $_v temperature $_t \
                    constraint_file $_sdc \
                    lib_set_ref $_lib_ref rc_corner $_rc_name]
            }
        }
    }
}

# ── Scenario sets — EXPLICIT, engineer-declared ──
# Each set lists analysis-view names (keys of analysis_views above).
#   setup / hold : drive setup/hold roles in FC, DMSA and Cadence views
#   power        : views for power analysis
#   signoff      : full sign-off set (STA fans out over this by default)
#   all          : every generated view (auto)
# List names with: cbflow flow mmmc-manager list-views
# Check for stale names after changing PVT/modes/RC corners with:
#   cbflow flow mmmc-manager validate
array set mmmc_scenario_sets {}
set mmmc_scenario_sets(setup) {
    func_ss_1p60v_rc_max_100c
    func_ss_1p60v_rc_max_m40c
}
set mmmc_scenario_sets(hold) {
    func_ff_1p95v_rc_min_m40c
    func_ff_1p95v_rc_min_100c
}
set mmmc_scenario_sets(power) {
    func_tt_1p80v_rc_typ_25c
}
set mmmc_scenario_sets(signoff) [concat \
    $mmmc_scenario_sets(setup) $mmmc_scenario_sets(hold)]
set mmmc_scenario_sets(all)         [lsort [array names analysis_views]]
set mmmc_scenario_sets(sta_setup)   $mmmc_scenario_sets(setup)
set mmmc_scenario_sets(sta_hold)    $mmmc_scenario_sets(hold)
set mmmc_scenario_sets(sta_signoff) $mmmc_scenario_sets(signoff)

# =============================================================================
# NODE-SPECIFIC SCENARIO ASSIGNMENTS
# Declared in mmmc_node_scenarios.tcl next to this file (engineer-managed;
# edit with: cbflow flow mmmc-manager set-node)
# =============================================================================

