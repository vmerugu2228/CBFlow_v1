#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — IO Pin Placement Script for Fusion Compiler
#
# Places ALL design ports on a specified side, starting from a given offset.
# Pins are placed ON TRACK using the metal pitch from tech config.
# Supports multiple layers — pins alternate across layers.
#
# Usage:
#   source place_io_pins.tcl
#
#   # Place all ports on the left side starting at 10um, on M4
#   place_pins_on_side -side left -start 10.0 -layers {M4}
#
#   # Multiple layers — pins alternate M4/M6 (horizontal/vertical)
#   place_pins_on_side -side left -start 10.0 -layers {M4 M6}
#
#   # Custom pitch (overrides track pitch)
#   place_pins_on_side -side right -start 5.0 -layers {M4} -pitch 3.0
#
#   # Report
#   report_pin_placement
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::IOPin {

    # ── Get die boundary ──────────────────────────────────────────────────
    proc get_die_boundary {} {
        set bbox [get_attribute [current_design] boundary]
        set llx [lindex [lindex $bbox 0] 0]
        set lly [lindex [lindex $bbox 0] 1]
        set urx [lindex [lindex $bbox 1] 0]
        set ury [lindex [lindex $bbox 1] 1]
        return [list $llx $lly $urx $ury]
    }

    # ── Get track pitch for a metal layer (from tool's loaded technology) ──
    proc get_layer_pitch {layer_name} {
        # Read directly from the EDA tool's technology database
        set layer_obj [get_layers $layer_name -quiet]
        if {$layer_obj ne "" && [sizeof_collection $layer_obj] > 0} {
            set pitch [get_attribute $layer_obj pitch]
            if {$pitch ne "" && $pitch > 0} {
                return $pitch
            }
            # Try min_pitch if pitch not available
            set min_pitch [get_attribute $layer_obj min_pitch -quiet]
            if {$min_pitch ne "" && $min_pitch > 0} {
                return $min_pitch
            }
        }
        puts "WARNING: Cannot read pitch for $layer_name from tool — using 0.080um"
        return 0.080
    }

    # ── Snap coordinate to nearest track ──────────────────────────────────
    proc snap_to_track {coord pitch {offset 0.0}} {
        if {$pitch <= 0} { return $coord }
        set adjusted [expr {$coord - $offset}]
        set track_num [expr {round($adjusted / $pitch)}]
        return [expr {($track_num * $pitch) + $offset}]
    }

    # ── Get all design ports sorted by name ───────────────────────────────
    proc get_all_ports_sorted {} {
        set all_ports [get_ports * -quiet]
        if {$all_ports eq "" || [sizeof_collection $all_ports] == 0} {
            return [list]
        }
        set port_list [list]
        foreach_in_collection p $all_ports {
            lappend port_list [get_attribute $p full_name]
        }
        # Sort: group buses together, then by bit index
        return [lsort -dictionary $port_list]
    }

    # ── Main: place all ports on a side ───────────────────────────────────
    proc place_pins_on_side {args} {
        # Parse arguments
        set side ""
        set start 0.0
        set layers [list]
        set pitch_override ""
        set track_offset 0.0

        for {set i 0} {$i < [llength $args]} {incr i} {
            set arg [lindex $args $i]
            switch -- $arg {
                -side    { incr i; set side [lindex $args $i] }
                -start   { incr i; set start [lindex $args $i] }
                -layers  { incr i; set layers [lindex $args $i] }
                -layer   { incr i; set layers [list [lindex $args $i]] }
                -pitch   { incr i; set pitch_override [lindex $args $i] }
                -offset  { incr i; set track_offset [lindex $args $i] }
            }
        }

        if {$side eq ""} {
            error "place_pins_on_side: -side required (left/right/top/bottom)"
        }
        if {[llength $layers] == 0} {
            error "place_pins_on_side: -layers required (e.g., {M4} or {M4 M6})"
        }

        # Get die boundary
        set die_bbox [get_die_boundary]
        set llx [lindex $die_bbox 0]
        set lly [lindex $die_bbox 1]
        set urx [lindex $die_bbox 2]
        set ury [lindex $die_bbox 3]

        # Side number for FC
        switch -- $side {
            "left"   { set side_num 1 }
            "top"    { set side_num 2 }
            "right"  { set side_num 3 }
            "bottom" { set side_num 4 }
            default  { error "Invalid side: $side" }
        }

        # Get all ports
        set ports [get_all_ports_sorted]
        set port_count [llength $ports]
        if {$port_count == 0} {
            puts "  No ports found in design"
            return 0
        }

        # Determine pitch per layer
        set layer_count [llength $layers]
        set pitches [list]
        foreach l $layers {
            if {$pitch_override ne ""} {
                lappend pitches $pitch_override
            } else {
                lappend pitches [get_layer_pitch $l]
            }
        }

        # For multiple layers, effective pitch = min pitch across layers
        # Pins alternate layers: pin0→layer0, pin1→layer1, pin2→layer0, ...
        # Spacing between pins on SAME layer = pitch * layer_count
        set min_pitch [lindex $pitches 0]
        foreach p $pitches {
            if {$p < $min_pitch} { set min_pitch $p }
        }

        # Pin spacing: if 1 layer, use that pitch. If N layers, use min_pitch.
        set pin_spacing $min_pitch

        set end_offset [expr {$start + (($port_count - 1) * $pin_spacing)}]

        # Check boundary
        switch -- $side {
            "left" - "right" { set max_range [expr {$ury - $lly}] }
            "top" - "bottom" { set max_range [expr {$urx - $llx}] }
        }

        puts ""
        puts "  ═══════════════════════════════════════════════════════════"
        puts "  IO Pin Placement"
        puts "  ═══════════════════════════════════════════════════════════"
        puts "  Die:    ($llx, $lly) to ($urx, $ury)"
        puts "  Side:   $side"
        puts "  Layers: $layers"
        puts "  Ports:  $port_count"
        puts "  Start:  ${start}um"
        puts "  Pitch:  ${pin_spacing}um (on track)"
        puts "  Range:  ${start}um → ${end_offset}um (max: ${max_range}um)"
        if {$end_offset > $max_range} {
            puts "  WARNING: Pins exceed die boundary!"
        }
        puts "  ───────────────────────────────────────────────────────────"

        # Place each port
        set count 0
        for {set i 0} {$i < $port_count} {incr i} {
            set pin_name [lindex $ports $i]
            set raw_offset [expr {$start + ($i * $pin_spacing)}]

            # Select layer (round-robin across provided layers)
            set layer_idx [expr {$i % $layer_count}]
            set layer [lindex $layers $layer_idx]
            set layer_pitch [lindex $pitches $layer_idx]

            # Snap to track for this layer
            set snapped_offset [snap_to_track $raw_offset $layer_pitch $track_offset]

            # Compute coordinates
            switch -- $side {
                "left"   { set x $llx; set y [expr {$lly + $snapped_offset}] }
                "right"  { set x $urx; set y [expr {$lly + $snapped_offset}] }
                "bottom" { set x [expr {$llx + $snapped_offset}]; set y $lly }
                "top"    { set x [expr {$llx + $snapped_offset}]; set y $ury }
            }

            # Verify port exists
            set port [get_ports $pin_name -quiet]
            if {$port eq "" || [sizeof_collection $port] == 0} {
                continue
            }

            # Set constraint
            set_individual_pin_constraints \
                -ports $pin_name \
                -allowed_layers $layer \
                -side $side_num \
                -location [list $x $y]

            incr count
        }

        # Legalize
        puts "  Legalizing..."
        place_pins -self

        puts ""
        puts "  Placed: $count / $port_count ports"
        puts "  ═══════════════════════════════════════════════════════════"
        puts ""
        return $count
    }

    # ── Report pin placement ──────────────────────────────────────────────
    proc report_pin_placement {{output_file ""}} {
        set lines [list]
        lappend lines "═══════════════════════════════════════════════════════════"
        lappend lines "  IO Pin Placement Report"
        lappend lines "  Design: [get_attribute [current_design] full_name]"
        lappend lines "═══════════════════════════════════════════════════════════"

        set total 0
        foreach {side_num side_name} {1 LEFT 2 TOP 3 RIGHT 4 BOTTOM} {
            set pins [get_ports -filter "side==$side_num" -quiet]
            if {$pins eq "" || [sizeof_collection $pins] == 0} continue
            set count [sizeof_collection $pins]
            set total [expr {$total + $count}]

            lappend lines ""
            lappend lines "  $side_name ($count pins):"
            lappend lines "  ─────────────────────────────────────────────────────"
            lappend lines [format "  %-30s %-6s %-6s %s" "Port" "Layer" "Dir" "Location"]

            set pin_list [list]
            foreach_in_collection p $pins {
                set name [get_attribute $p full_name]
                set layer [get_attribute $p layer_name]
                set dir [get_attribute $p direction]
                set loc [get_attribute $p location]
                lappend pin_list [list $name $layer $dir $loc]
            }
            foreach item [lsort -index 0 $pin_list] {
                lappend lines [format "  %-30s %-6s %-6s %s" \
                    [lindex $item 0] [lindex $item 1] [lindex $item 2] [lindex $item 3]]
            }
        }

        lappend lines ""
        lappend lines "  Total: $total ports"
        lappend lines "═══════════════════════════════════════════════════════════"

        set report [join $lines "\n"]
        if {$output_file ne ""} {
            set fh [open $output_file "w"]
            puts $fh $report
            close $fh
            puts "  Report: $output_file"
        } else {
            puts $report
        }
    }

    namespace export place_pins_on_side report_pin_placement
}

namespace import ::CBFlow::IOPin::*

# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#
#   source place_io_pins.tcl
#
#   # All ports on left, single layer
#   place_pins_on_side -side left -start 10.0 -layers {M4}
#
#   # All ports on left, two layers (pins alternate M4/M6, on track)
#   place_pins_on_side -side left -start 10.0 -layers {M4 M6}
#
#   # Custom pitch override
#   place_pins_on_side -side bottom -start 5.0 -layers {M5} -pitch 5.0
#
#   # Report
#   report_pin_placement "reports/pin_placement.rpt"
# ═══════════════════════════════════════════════════════════════════════════════
