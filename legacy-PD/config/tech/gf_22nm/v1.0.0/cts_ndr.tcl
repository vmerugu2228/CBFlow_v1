#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow CTS NDR (Non-Default Routing) Rules — GF 22FDX
# Sourced by CTS stage via tech(cts_ndr_file)
# Variables come from tech() array in tech_config.tcl
#
# GF 22FDX 11M metal stack:
#   M1-M2:   64nm pitch (local interconnect)
#   M3-M7:   90nm pitch (signal routing — clock routing here)
#   M8-M9:   180nm pitch (semi-global)
#   M10-M11: 720nm pitch (power distribution)
#
# Clock NDR strategy:
#   Root/trunk: 2x width, 2x spacing on M3-M7 (better EM, lower skew)
#   Internal:   2x width, 2x spacing on M3-M7
#   Leaf:       default rules (M2-M5, minimum area)
# ═══════════════════════════════════════════════════════════════════════════════
global tech

# ── Define NDR Rules ─────────────────────────────────────────────────────────

# rm_2w2s: Double width, double spacing — for root and internal clock nets
# Reduces EM risk on continuously switching clock nets
# Reduces crosstalk-induced jitter from adjacent signal nets
if {[info exists tech(cts_ndr,root_rule)] && $tech(cts_ndr,root_rule) ne ""} {

    # Create the 2W2S rule if it doesn't already exist
    if {[catch {get_routing_rules rm_2w2s}]} {
        # Build per-layer width/spacing for GF 22FDX M3-M7
        set ndr_widths {}
        set ndr_spacings {}
        foreach layer_info $tech(metal_stack) {
            set layer [lindex $layer_info 0]
            set pitch [lindex $layer_info 2]
            # Only create NDR for signal routing layers M3-M7
            if {$layer in {M3 M4 M5 M6 M7}} {
                # Min width ~ pitch/2, double it
                set min_w [expr {$pitch / 2.0}]
                lappend ndr_widths $layer [expr {$min_w * 2.0}]
                lappend ndr_spacings $layer [expr {$min_w * 2.0}]
            }
        }

        if {[llength $ndr_widths] > 0} {
            create_routing_rule rm_2w2s \
                -widths $ndr_widths \
                -spacings $ndr_spacings
            handle_info "Created NDR rule rm_2w2s (2x width, 2x spacing on M3-M7)"
        } else {
            # Fallback: use multiplier-based rule
            create_routing_rule rm_2w2s \
                -multiplier_width 2.0 \
                -multiplier_spacing 2.0
            handle_info "Created NDR rule rm_2w2s (2x multiplier, all layers)"
        }
    }

    # Also create a shielded variant if needed
    if {$tech(cts_ndr,root_rule) eq "rm_2w2s_shield"} {
        if {[catch {get_routing_rules rm_2w2s_shield}]} {
            create_routing_rule rm_2w2s_shield \
                -multiplier_width 2.0 \
                -multiplier_spacing 2.0 \
                -default_shield_side both \
                -shield_net VSS
            handle_info "Created NDR rule rm_2w2s_shield (2W2S + VSS shield)"
        }
    }
}

# ── Apply Root Clock NDR ─────────────────────────────────────────────────────
if {[info exists tech(cts_ndr,root_rule)] && $tech(cts_ndr,root_rule) ne ""} {
    set rule $tech(cts_ndr,root_rule)
    set cmd "set_clock_routing_rules -rule $rule -net_type root"

    if {[info exists tech(cts_ndr,min_layer)] && $tech(cts_ndr,min_layer) ne ""} {
        append cmd " -min_routing_layer $tech(cts_ndr,min_layer)"
    }
    if {[info exists tech(cts_ndr,max_layer)] && $tech(cts_ndr,max_layer) ne ""} {
        append cmd " -max_routing_layer $tech(cts_ndr,max_layer)"
    }
    eval $cmd
    handle_info "CTS root NDR: $rule (layers: $tech(cts_ndr,min_layer)-$tech(cts_ndr,max_layer))"
}

# ── Apply Internal Clock NDR ─────────────────────────────────────────────────
if {[info exists tech(cts_ndr,internal_rule)] && $tech(cts_ndr,internal_rule) ne ""} {
    set rule $tech(cts_ndr,internal_rule)
    set cmd "set_clock_routing_rules -rule $rule -net_type internal"

    if {[info exists tech(cts_ndr,min_layer)] && $tech(cts_ndr,min_layer) ne ""} {
        append cmd " -min_routing_layer $tech(cts_ndr,min_layer)"
    }
    if {[info exists tech(cts_ndr,max_layer)] && $tech(cts_ndr,max_layer) ne ""} {
        append cmd " -max_routing_layer $tech(cts_ndr,max_layer)"
    }
    eval $cmd
    handle_info "CTS internal NDR: $rule"
}

# ── Apply Leaf Clock NDR ─────────────────────────────────────────────────────
# Leaf clock nets use default routing rules by default (no NDR)
# This keeps leaf routing compact and avoids congestion near sinks
if {[info exists tech(cts_ndr,leaf_rule)] && $tech(cts_ndr,leaf_rule) ne ""} {
    set rule $tech(cts_ndr,leaf_rule)
    # BUG FIX #8 (init): FC uses 'sink' not 'leaf' for leaf clock nets
    set cmd "set_clock_routing_rules -rule $rule -net_type sink"

    # Leaf typically routes on lower layers (M2-M4)
    if {[info exists tech(cts_ndr,leaf_min_layer)] && $tech(cts_ndr,leaf_min_layer) ne ""} {
        append cmd " -min_routing_layer $tech(cts_ndr,leaf_min_layer)"
    } else {
        append cmd " -min_routing_layer M2"
    }
    if {[info exists tech(cts_ndr,leaf_max_layer)] && $tech(cts_ndr,leaf_max_layer) ne ""} {
        append cmd " -max_routing_layer $tech(cts_ndr,leaf_max_layer)"
    } else {
        append cmd " -max_routing_layer M5"
    }
    eval $cmd
    handle_info "CTS leaf NDR: $rule"
} else {
    handle_info "CTS leaf NDR: default (no NDR applied to leaf nets)"
}

# ── Summary ──────────────────────────────────────────────────────────────────
handle_info "CTS NDR setup complete for GF 22FDX"
handle_info "  Metal stack: 11M (M1-M11)"
handle_info "  Clock routing: $tech(cts_ndr,min_layer)-$tech(cts_ndr,max_layer) (90nm pitch)"
handle_info "  Root/Internal: $tech(cts_ndr,root_rule) (2x width, 2x spacing)"
handle_info "  Leaf: [expr {$tech(cts_ndr,leaf_rule) ne {} ? $tech(cts_ndr,leaf_rule) : {default}}]"
