#!/usr/bin/env tclsh
# ============================================================================
# CBFlow Per-Project Threshold Overrides
# Description: Project-specific QoR threshold customization
# Version: 1.0.0
#
# Usage: Override default exit milestone thresholds on a per-project,
#        per-phase, or per-block basis. Overrides are layered:
#        default (exit config) -> phase_defaults -> project -> phase -> block
# ============================================================================

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     OVERRIDE POLICY                                    │
# └─────────────────────────────────────────────────────────────────────────┘

array set override_policy {
    allow_relaxation        true
    allow_tightening        true
    require_justification   true
    log_override_usage      true
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     DEFAULT THRESHOLDS                                 │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Fallback values when no project or phase override is specified.
# Units: timing in ps, utilization as ratio, congestion as ratio,
#        power in mW, IR drop in mV, skew in ps.

array set default_thresholds {
    FP_EXIT,utilization_min              0.55
    FP_EXIT,utilization_max              0.85
    FP_EXIT,setup_wns                    -200

    PLACE_EXIT,setup_wns                 -100
    PLACE_EXIT,setup_tns                 -1000
    PLACE_EXIT,hold_wns                  -50
    PLACE_EXIT,max_congestion            0.90
    PLACE_EXIT,density_min               0.65
    PLACE_EXIT,density_max               0.88

    CTS_EXIT,clock_skew                  60
    CTS_EXIT,max_insertion_delay         500
    CTS_EXIT,clock_coverage              99.0
    CTS_EXIT,setup_wns                   -50
    CTS_EXIT,hold_wns                    -20

    PRO_EXIT,setup_wns                   -20
    PRO_EXIT,setup_tns                   -200
    PRO_EXIT,hold_wns                    -10
    PRO_EXIT,hold_tns                    -100
    PRO_EXIT,max_congestion              0.85
    PRO_EXIT,max_ir_drop                 40

    BTO,setup_wns                        0
    BTO,setup_tns                        0
    BTO,hold_wns                         0
    BTO,hold_tns                         0
    BTO,drc_violations                   0
    BTO,max_ir_drop                      30
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     PHASE-PROGRESSIVE DEFAULTS                         │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Phase-specific thresholds applied to ALL projects unless overridden.
# P0 = exploration (relaxed), P1 = convergence, P2 = pre-signoff, P3 = signoff
#
# Format: phase_defaults(<phase>,<milestone>,<metric>) value

array set phase_defaults {
    P0,FP_EXIT,utilization_min           0.45
    P0,FP_EXIT,setup_wns                 -500
    P0,PLACE_EXIT,setup_wns              -200
    P0,PLACE_EXIT,setup_tns              -5000
    P0,PLACE_EXIT,hold_wns              -100
    P0,PLACE_EXIT,max_congestion         0.95
    P0,CTS_EXIT,clock_skew               100
    P0,CTS_EXIT,setup_wns                -100
    P0,CTS_EXIT,hold_wns                 -50
    P0,PRO_EXIT,setup_wns                -100
    P0,PRO_EXIT,hold_wns                 -50
    P0,PRO_EXIT,max_ir_drop              60
    P0,BTO,setup_wns                     -50
    P0,BTO,hold_wns                      -20

    P1,PLACE_EXIT,setup_wns              -80
    P1,PLACE_EXIT,setup_tns              -2000
    P1,PLACE_EXIT,hold_wns              -30
    P1,CTS_EXIT,clock_skew               60
    P1,CTS_EXIT,setup_wns                -50
    P1,CTS_EXIT,hold_wns                 -20
    P1,PRO_EXIT,setup_wns                -30
    P1,PRO_EXIT,hold_wns                 -20
    P1,BTO,setup_wns                     -20
    P1,BTO,hold_wns                      -10

    P2,PLACE_EXIT,setup_wns              -20
    P2,PLACE_EXIT,setup_tns              -500
    P2,CTS_EXIT,clock_skew               40
    P2,CTS_EXIT,setup_wns                -10
    P2,PRO_EXIT,setup_wns                0
    P2,PRO_EXIT,hold_wns                 0
    P2,PRO_EXIT,setup_tns                0
    P2,BTO,setup_wns                     0
    P2,BTO,hold_wns                      0
    P2,BTO,drc_violations                0

    P3,PLACE_EXIT,setup_wns              0
    P3,PLACE_EXIT,setup_tns              0
    P3,CTS_EXIT,clock_skew               30
    P3,CTS_EXIT,setup_wns                0
    P3,CTS_EXIT,hold_wns                 0
    P3,PRO_EXIT,setup_wns                0
    P3,PRO_EXIT,hold_wns                 0
    P3,PRO_EXIT,setup_tns                0
    P3,PRO_EXIT,hold_tns                 0
    P3,BTO,setup_wns                     0
    P3,BTO,hold_wns                      0
    P3,BTO,setup_tns                     0
    P3,BTO,hold_tns                      0
    P3,BTO,drc_violations                0
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     PROJECT-LEVEL OVERRIDES                            │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Format: threshold_override(<project>,<milestone>,<metric>) value
#
# Only specify metrics that differ from the defaults.
# Unspecified metrics fall through to phase_defaults or default_thresholds.

# ── ravendrive (22nm, relaxed early milestones) ───────────────────────────

array set threshold_override {
    ravendrive,FP_EXIT,utilization_min           0.55
    ravendrive,FP_EXIT,utilization_max           0.82
    ravendrive,FP_EXIT,setup_wns                 -300

    ravendrive,PLACE_EXIT,setup_wns              -80
    ravendrive,PLACE_EXIT,setup_tns              -800
    ravendrive,PLACE_EXIT,max_congestion         0.88

    ravendrive,CTS_EXIT,clock_skew               60
    ravendrive,CTS_EXIT,max_insertion_delay       600
    ravendrive,CTS_EXIT,clock_coverage            99.0

    ravendrive,PRO_EXIT,max_ir_drop              40
}

# ── india (5nm, tighter thresholds) ───────────────────────────────────────

array set threshold_override {
    india,FP_EXIT,utilization_min                0.65
    india,FP_EXIT,utilization_max                0.78

    india,PLACE_EXIT,setup_wns                   -30
    india,PLACE_EXIT,setup_tns                   -300
    india,PLACE_EXIT,max_congestion              0.80

    india,CTS_EXIT,clock_skew                    35
    india,CTS_EXIT,max_insertion_delay            350
    india,CTS_EXIT,clock_coverage                 99.8

    india,PRO_EXIT,max_ir_drop                   20
    india,PRO_EXIT,setup_wns                     0
    india,PRO_EXIT,hold_wns                      0
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     PHASE-LEVEL PROJECT OVERRIDES                      │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Format: phase_override(<project>,<phase>,<milestone>,<metric>) value
#
# Phase overrides take precedence over project overrides.
# Common pattern: relax thresholds at P0/P1, tighten at P2/P3.

array set phase_override {
    ravendrive,P0,FP_EXIT,utilization_min        0.50
    ravendrive,P0,PLACE_EXIT,setup_wns           -150
    ravendrive,P0,PLACE_EXIT,setup_tns           -2000
    ravendrive,P0,CTS_EXIT,clock_skew            80

    ravendrive,P1,PLACE_EXIT,setup_wns           -80
    ravendrive,P1,PLACE_EXIT,setup_tns           -800

    ravendrive,P2,PLACE_EXIT,setup_wns           -20
    ravendrive,P2,PRO_EXIT,setup_wns             0
    ravendrive,P2,PRO_EXIT,hold_wns              0

    india,P0,PLACE_EXIT,setup_wns                -80
    india,P0,CTS_EXIT,clock_skew                 50
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     THRESHOLD RESOLUTION PROCEDURES                    │
# └─────────────────────────────────────────────────────────────────────────┘

proc get_threshold {project milestone metric {phase ""} {block ""}} {
    global threshold_override phase_override phase_defaults default_thresholds

    # Priority: block > phase_override (project+phase) > threshold_override (project) >
    #           phase_defaults (phase) > default_thresholds > ""
    # (block overrides not implemented yet — reserved for future use)

    # 1. Check phase-level project override
    if {$phase ne ""} {
        set phase_key "${project},${phase},${milestone},${metric}"
        if {[info exists phase_override($phase_key)]} {
            return $phase_override($phase_key)
        }
    }

    # 2. Check project-level override
    set project_key "${project},${milestone},${metric}"
    if {[info exists threshold_override($project_key)]} {
        return $threshold_override($project_key)
    }

    # 3. Check phase-progressive defaults (applies to all projects)
    if {$phase ne ""} {
        set phase_default_key "${phase},${milestone},${metric}"
        if {[info exists phase_defaults($phase_default_key)]} {
            return $phase_defaults($phase_default_key)
        }
    }

    # 4. Check default thresholds
    set default_key "${milestone},${metric}"
    if {[info exists default_thresholds($default_key)]} {
        return $default_thresholds($default_key)
    }

    # 5. No threshold found — caller should use config default
    return ""
}

proc list_overrides {project {milestone ""}} {
    global threshold_override phase_override phase_defaults default_thresholds

    puts "Threshold overrides for project: $project"
    puts [string repeat "=" 60]

    # Default thresholds
    puts "\nDefault thresholds:"
    foreach key [lsort [array names default_thresholds]] {
        set parts [split $key ","]
        set ms [lindex $parts 0]
        set metric [lindex $parts 1]
        if {$milestone eq "" || $ms eq $milestone} {
            puts "  $ms / $metric = $default_thresholds($key)"
        }
    }

    # Phase defaults
    puts "\nPhase-progressive defaults:"
    foreach key [lsort [array names phase_defaults]] {
        set parts [split $key ","]
        set ph [lindex $parts 0]
        set ms [lindex $parts 1]
        set metric [lindex $parts 2]
        if {$milestone eq "" || $ms eq $milestone} {
            puts "  $ph / $ms / $metric = $phase_defaults($key)"
        }
    }

    # Project-level
    puts "\nProject-level overrides:"
    foreach key [lsort [array names threshold_override "${project},*"]] {
        set parts [split $key ","]
        set ms [lindex $parts 1]
        set metric [lindex $parts 2]
        if {$milestone eq "" || $ms eq $milestone} {
            puts "  $ms / $metric = $threshold_override($key)"
        }
    }

    # Phase-level
    puts "\nPhase-level project overrides:"
    foreach key [lsort [array names phase_override "${project},*"]] {
        set parts [split $key ","]
        set ph [lindex $parts 1]
        set ms [lindex $parts 2]
        set metric [lindex $parts 3]
        if {$milestone eq "" || $ms eq $milestone} {
            puts "  $ph / $ms / $metric = $phase_override($key)"
        }
    }
}

puts "INFO: Threshold overrides loaded — [llength [array names default_thresholds]] defaults, [llength [array names phase_defaults]] phase defaults, [llength [array names threshold_override]] project, [llength [array names phase_override]] phase overrides"
