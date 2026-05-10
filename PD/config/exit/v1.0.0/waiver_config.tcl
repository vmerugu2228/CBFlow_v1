#!/usr/bin/env tclsh
# ============================================================================
# CBFlow Waiver Configuration
# Description: Approved exceptions to exit milestone criteria
# Version: 1.0.0
#
# Usage: Waivers allow specific checks to be bypassed when approved by leads.
#        Each waiver records: who approved, why, expiry date, and scope.
# ============================================================================

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                        WAIVER POLICY                                   │
# └─────────────────────────────────────────────────────────────────────────┘

array set waiver_policy {
    require_approval        true
    require_expiry_date     true
    max_waiver_duration_days 90
    allow_bto_waivers       false
    allow_mto_waivers       false
    notify_on_waiver_use    true
    audit_log_path          "logs/waiver_audit.log"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                        WAIVER DATABASE                                 │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Each waiver entry format:
#   waiver(<ID>,field) value
#
# Fields:
#   milestone   - Which exit milestone (FP_EXIT, PLACE_EXIT, etc.)
#   check       - Which check to waive (must match mandatory_checks key)
#   project     - Project scope (* for all projects)
#   block       - Block scope (* for all blocks)
#   reason      - Business justification
#   approved_by - Name of approver
#   approved_date - Date of approval (YYYY-MM-DD)
#   expiry_date - Expiry date (YYYY-MM-DD)
#   status      - active | expired | revoked
#   risk_level  - low | medium | high
#   conditions  - Any conditions attached to the waiver

# ── Example Waivers ───────────────────────────────────────────────────────

array set waiver {
    W001,milestone      "FP_EXIT"
    W001,check          "congestion_analysis"
    W001,project        "ravendrive"
    W001,block          "*"
    W001,reason         "Congestion acceptable at P0 phase, will re-evaluate at P1"
    W001,approved_by    "chip_lead"
    W001,approved_date  "2026-04-01"
    W001,expiry_date    "2026-07-01"
    W001,status         "active"
    W001,risk_level     "low"
    W001,conditions     "Must meet congestion target by PLACE_EXIT"

    W002,milestone      "PLACE_EXIT"
    W002,check          "hold_timing"
    W002,project        "ravendrive"
    W002,block          "*"
    W002,reason         "Hold fixing deferred to CTS stage per methodology"
    W002,approved_by    "timing_lead"
    W002,approved_date  "2026-04-15"
    W002,expiry_date    "2026-06-30"
    W002,status         "active"
    W002,risk_level     "low"
    W002,conditions     "Hold WNS must be >= -50ps"
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     WAIVER ERROR PATTERN OVERRIDES                     │
# └─────────────────────────────────────────────────────────────────────────┘
# Patterns that should be treated as waivered (not flagged as critical)

array set waiver_patterns {
    global {
        ".*IMPOPT-200.*"
        ".*WARNING.*clock.*reconvergence.*"
    }

    FP_EXIT {
        ".*estimated.*timing.*not.*met.*"
    }

    PLACE_EXIT {
        ".*hold.*slack.*negative.*pre_cts.*"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                        WAIVER PROCEDURES                               │
# └─────────────────────────────────────────────────────────────────────────┘

proc get_active_waivers {milestone {project "*"} {block "*"}} {
    global waiver
    set active_waivers {}

    foreach key [array names waiver "*,milestone"] {
        set id [lindex [split $key ","] 0]
        if {$waiver($key) eq $milestone} {
            if {[info exists waiver($id,status)] && $waiver($id,status) eq "active"} {
                # Check project scope
                if {$waiver($id,project) eq "*" || $waiver($id,project) eq $project} {
                    # Check block scope
                    if {$waiver($id,block) eq "*" || $waiver($id,block) eq $block} {
                        lappend active_waivers $id
                    }
                }
            }
        }
    }

    return $active_waivers
}

proc is_check_waivered {milestone check {project "*"} {block "*"}} {
    global waiver
    set waivers [get_active_waivers $milestone $project $block]

    foreach id $waivers {
        if {[info exists waiver($id,check)] && $waiver($id,check) eq $check} {
            return 1
        }
    }

    return 0
}

proc get_waiver_info {waiver_id} {
    global waiver
    set info {}

    foreach field {milestone check project block reason approved_by approved_date expiry_date status risk_level conditions} {
        set key "${waiver_id},${field}"
        if {[info exists waiver($key)]} {
            dict set info $field $waiver($key)
        }
    }

    return $info
}

puts "INFO: Waiver configuration loaded - [llength [array names waiver *,milestone]] waiver(s) defined"
