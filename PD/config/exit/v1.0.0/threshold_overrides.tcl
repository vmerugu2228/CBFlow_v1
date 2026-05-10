#!/usr/bin/env tclsh
# ============================================================================
# CBFlow Per-Project Threshold Overrides
# Description: Project-specific QoR threshold customization
# Version: 1.0.0
#
# Usage: Override default exit milestone thresholds on a per-project,
#        per-phase, or per-block basis. Overrides are layered:
#        default (exit config) -> project -> phase -> block
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
# │                     PROJECT-LEVEL OVERRIDES                            │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Format: threshold_override(<project>,<milestone>,<metric>) value
#
# Only specify metrics that differ from the defaults in the exit configs.
# Unspecified metrics fall through to the default exit config values.

# ── ravendrive (22nm, relaxed early milestones) ───────────────────────────

array set threshold_override {
    ravendrive,FP_EXIT,utilization_min           0.55
    ravendrive,FP_EXIT,utilization_max           0.82
    ravendrive,FP_EXIT,pin_accessibility         0.90

    ravendrive,PLACE_EXIT,setup_wns              -80
    ravendrive,PLACE_EXIT,setup_tns              -800
    ravendrive,PLACE_EXIT,max_congestion         0.88

    ravendrive,CTS_EXIT,clock_skew               60
    ravendrive,CTS_EXIT,max_insertion_delay      600
    ravendrive,CTS_EXIT,clock_coverage           99.0

    ravendrive,PRO_EXIT,max_ir_drop              40
}

# ── india (5nm, tighter thresholds) ───────────────────────────────────────

array set threshold_override {
    india,FP_EXIT,utilization_min                0.65
    india,FP_EXIT,utilization_max                0.78
    india,FP_EXIT,pin_accessibility              0.98

    india,PLACE_EXIT,setup_wns                   -30
    india,PLACE_EXIT,setup_tns                   -300
    india,PLACE_EXIT,max_congestion              0.80

    india,CTS_EXIT,clock_skew                    35
    india,CTS_EXIT,max_insertion_delay           350
    india,CTS_EXIT,clock_coverage                99.8

    india,PRO_EXIT,max_ir_drop                   20
    india,PRO_EXIT,setup_wns                     0
    india,PRO_EXIT,hold_wns                      0
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     PHASE-LEVEL OVERRIDES                              │
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
    global threshold_override phase_override

    # Priority: block > phase > project > default
    # (block overrides not implemented yet - reserved for future use)

    # Check phase-level override
    if {$phase ne ""} {
        set phase_key "${project},${phase},${milestone},${metric}"
        if {[info exists phase_override($phase_key)]} {
            return $phase_override($phase_key)
        }
    }

    # Check project-level override
    set project_key "${project},${milestone},${metric}"
    if {[info exists threshold_override($project_key)]} {
        return $threshold_override($project_key)
    }

    # Return empty - caller should use default from exit config
    return ""
}

proc list_overrides {project {milestone ""}} {
    global threshold_override phase_override

    puts "Threshold overrides for project: $project"
    puts [string repeat "=" 60]

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
    puts "\nPhase-level overrides:"
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

puts "INFO: Threshold overrides loaded for [llength [array names threshold_override]] project-level, [llength [array names phase_override]] phase-level overrides"
