#!/usr/bin/env tclsh
# =============================================================================
# CBflow MMMC Configuration — Auto-Generated
# Generated: 2026-06-04 20:24 | Tech: gf_28nm | Corners: 10
# Source: lib_config_LIB02.tcl
# Views: 20 | Modes: func test | Process: ff ss tt
# Regenerate: cbflow flow mmmc-manager generate --tech gf_28nm
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

set mmmc(voltage,nom)        0.90
set mmmc(voltage,low)        0.80
set mmmc(voltage,high)       1.10
set mmmc(temperature,hot)    125
set mmmc(temperature,nom)    25
set mmmc(temperature,cold)   -40

# =============================================================================
# PROCESS CORNERS & OPERATING MODES
# =============================================================================

set mmmc(process_corners) {ff ss tt}

array set operating_modes {
    func { constraint_file "${design_name}_func.sdc" }
    test { constraint_file "${design_name}_test.sdc" }
}

# =============================================================================
# PVT POINTS (user-specified, validated against lib_config)
# =============================================================================

set mmmc(pvt,ff) {{1p10v 125c} {1p10v 25c} {1p10v m40c}}
set mmmc(pvt,ss) {{0p80v 125c} {0p80v m40c} {0p90v 125c} {0p90v m40c}}
set mmmc(pvt,tt) {{0p90v 125c} {0p90v 25c} {0p90v m40c}}

# =============================================================================
# RC CORNERS — declared BEFORE analysis-view generation so the full
# Cartesian loop below can iterate [array names rc_corners].
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
# AUTO-GENERATE ANALYSIS VIEWS & SCENARIO SETS
# =============================================================================

# Analysis views — FULL CARTESIAN mode × corner × pvt × rc_corner.
# The tool no longer imposes a role→rc mapping (previously `switch $_corner`
# auto-tagged ss→setup, ff→hold, tt→setup_hold; that was removed because
# (a) extended corners like fff/sfs crashed the switch, and (b) the role
# mapping is a project decision, not a framework assumption). Engineers
# declare which views belong to `setup` / `hold` / `signoff` / etc.
# scenario_sets further down — fully user-controlled.
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

# ── Scenario sets — EXPLICIT, engineer-declared ─────────────────────────────
# Each set is a list of analysis_view names (keys in `analysis_views`
# above). Engineers decide which combinations serve each purpose:
#   setup   : views for setup-time analysis (typically slow + rc_max)
#   hold    : views for hold-time analysis (typically fast + rc_min)
#   power   : views for power analysis (typically typical)
#   signoff : full sign-off set
#   all     : literally every generated view (auto-populated)
# View-name format: ${mode}_${corner}_${voltage}_${rc_corner}_${temp}
array set mmmc_scenario_sets {}
set mmmc_scenario_sets(setup) {
    func_ss_0p80v_rc_max_125c
    func_ss_0p80v_rc_max_m40c
    func_ss_0p90v_rc_max_125c
    func_ss_0p90v_rc_max_m40c
    test_ss_0p80v_rc_max_125c
    test_ss_0p80v_rc_max_m40c
    test_ss_0p90v_rc_max_125c
    test_ss_0p90v_rc_max_m40c
}
set mmmc_scenario_sets(hold) {
    func_ff_1p10v_rc_min_125c
    func_ff_1p10v_rc_min_25c
    func_ff_1p10v_rc_min_m40c
    test_ff_1p10v_rc_min_125c
    test_ff_1p10v_rc_min_25c
    test_ff_1p10v_rc_min_m40c
}
set mmmc_scenario_sets(power) {
    func_tt_0p90v_rc_typ_125c
    func_tt_0p90v_rc_typ_25c
    func_tt_0p90v_rc_typ_m40c
    func_ss_0p80v_rc_typ_125c
    func_ss_0p80v_rc_typ_m40c
}
set mmmc_scenario_sets(signoff) [concat \
    $mmmc_scenario_sets(setup) \
    $mmmc_scenario_sets(hold) \
    {func_tt_0p90v_rc_typ_125c func_tt_0p90v_rc_typ_25c func_tt_0p90v_rc_typ_m40c}]
set mmmc_scenario_sets(all)         [lsort [array names analysis_views]]
set mmmc_scenario_sets(sta_setup)   $mmmc_scenario_sets(setup)
set mmmc_scenario_sets(sta_hold)    $mmmc_scenario_sets(hold)
set mmmc_scenario_sets(sta_signoff) $mmmc_scenario_sets(signoff)

# =============================================================================
# NODE-SPECIFIC SCENARIO ASSIGNMENTS
# Defined in project_config.tcl (project-level decision, not auto-generated)
# =============================================================================

