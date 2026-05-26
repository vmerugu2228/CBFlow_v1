#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — IO Pin Placement Script for Fusion Compiler
#
# Auto-detects port groups from design netlist by naming convention.
# User only specifies: group name, side, starting point.
# Buses (name[N]) are auto-detected and placed in bit order.
#
# Usage:
#   source place_io_pins.tcl
#
#   # Place a bus — auto-detects data_in[0] through data_in[15]
#   place_pin_group "data_in" -side left -start 10.0
#
#   # Place with custom layer and pitch
#   place_pin_group "addr" -side left -start 50.0 -layer M6 -pitch 3.0
#
#   # Place a scalar pin
#   place_pin_group "clk" -side bottom -start 30.0
#
#   # Place all remaining unplaced ports automatically
#   place_remaining -side top -start 5.0
#
#   # Report
#   report_pin_placement
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::IOPin {

    variable default_layer "M4"
    variable default_pitch 2.0
    variable placed_pins [list]

    # ── Get die boundary ──────────────────────────────────────────────────
    proc get_die_boundary {} {
        set bbox [get_attribute [current_design] boundary]
        set llx [lindex [lindex $bbox 0] 0]
        set lly [lindex [lindex $bbox 0] 1]
        set urx [lindex [lindex $bbox 1] 0]
        set ury [lindex [lindex $bbox 1] 1]
        return [list $llx $lly $urx $ury]
    }

    # ── Find all ports matching a group name ──────────────────────────────
    # "data_in" matches: data_in, data_in[0], data_in[1], ..., data_in[31]
    # Returns sorted list: scalars first, then bus bits in ascending order
    proc find_ports_for_group {group_name} {
        set all_ports [list]

        # Try exact scalar match
        set scalar [get_ports $group_name -quiet]
        if {$scalar ne "" && [sizeof_collection $scalar] > 0} {
            lappend all_ports $group_name
        }

        # Try bus match: group_name[*]
        set bus_ports [get_ports "${group_name}\[*\]" -quiet]
        if {$bus_ports ne "" && [sizeof_collection $bus_ports] > 0} {
            # Collect names and sort by bit index
            set bus_list [list]
            foreach_in_collection p $bus_ports {
                set pname [get_attribute $p full_name]
                lappend bus_list $pname
            }
            # Sort by bit index numerically
            set bus_list [lsort -command [list apply {{a b} {
                regexp {\[(\d+)\]} $a -> ai
                regexp {\[(\d+)\]} $b -> bi
                return [expr {$ai - $bi}]
            }}] $bus_list]
            set all_ports [concat $all_ports $bus_list]
        }

        return $all_ports
    }

    # ── Place a group of pins ─────────────────────────────────────────────
    proc place_pin_group {group_name args} {
        variable default_layer
        variable default_pitch
        variable placed_pins

        # Parse arguments
        set side ""
        set start 0.0
        set layer $default_layer
        set pitch $default_pitch

        for {set i 0} {$i < [llength $args]} {incr i} {
            set arg [lindex $args $i]
            switch -- $arg {
                -side   { incr i; set side [lindex $args $i] }
                -start  { incr i; set start [lindex $args $i] }
                -layer  { incr i; set layer [lindex $args $i] }
                -pitch  { incr i; set pitch [lindex $args $i] }
            }
        }

        if {$side eq ""} {
            error "place_pin_group: -side is required (left/right/top/bottom)"
        }

        # Find matching ports
        set pins [find_ports_for_group $group_name]
        if {[llength $pins] == 0} {
            puts "WARNING: No ports found matching '$group_name' or '${group_name}\[*\]'"
            return 0
        }

        set pin_count [llength $pins]
        set die_bbox [get_die_boundary]
        set llx [lindex $die_bbox 0]
        set lly [lindex $die_bbox 1]
        set urx [lindex $die_bbox 2]
        set ury [lindex $die_bbox 3]

        # Map side to FC side number: 1=left, 2=top, 3=right, 4=bottom
        switch -- $side {
            "left"   { set side_num 1 }
            "top"    { set side_num 2 }
            "right"  { set side_num 3 }
            "bottom" { set side_num 4 }
            default  { error "Invalid side: $side" }
        }

        set end_offset [expr {$start + (($pin_count - 1) * $pitch)}]

        puts ""
        puts "  Placing: $group_name ($pin_count pins)"
        puts "  Side: $side | Layer: $layer | Start: ${start}um | Pitch: ${pitch}um | End: ${end_offset}um"
        puts "  ─────────────────────────────────────────────────────"

        # Place each pin
        set count 0
        for {set i 0} {$i < $pin_count} {incr i} {
            set pin_name [lindex $pins $i]
            set offset [expr {$start + ($i * $pitch)}]

            # Compute coordinates
            switch -- $side {
                "left"   { set x $llx; set y [expr {$lly + $offset}] }
                "right"  { set x $urx; set y [expr {$lly + $offset}] }
                "bottom" { set x [expr {$llx + $offset}]; set y $lly }
                "top"    { set x [expr {$llx + $offset}]; set y $ury }
            }

            # Set pin constraint
            set port [get_ports $pin_name -quiet]
            if {$port eq "" || [sizeof_collection $port] == 0} {
                puts "    SKIP: $pin_name (not found)"
                continue
            }

            set_individual_pin_constraints \
                -ports $pin_name \
                -allowed_layers $layer \
                -side $side_num \
                -location [list $x $y]

            lappend placed_pins $pin_name
            incr count
        }

        puts "  Placed: $count / $pin_count"
        return $count
    }

    # ── Place all remaining unplaced ports ────────────────────────────────
    proc place_remaining {args} {
        variable placed_pins
        variable default_layer
        variable default_pitch

        set side "top"
        set start 5.0
        set layer $default_layer
        set pitch $default_pitch

        for {set i 0} {$i < [llength $args]} {incr i} {
            set arg [lindex $args $i]
            switch -- $arg {
                -side   { incr i; set side [lindex $args $i] }
                -start  { incr i; set start [lindex $args $i] }
                -layer  { incr i; set layer [lindex $args $i] }
                -pitch  { incr i; set pitch [lindex $args $i] }
            }
        }

        # Get all ports
        set all_ports [get_ports * -quiet]
        if {$all_ports eq "" || [sizeof_collection $all_ports] == 0} {
            puts "  No ports in design"
            return 0
        }

        # Find unplaced
        set unplaced [list]
        foreach_in_collection p $all_ports {
            set pname [get_attribute $p full_name]
            if {[lsearch -exact $placed_pins $pname] < 0} {
                lappend unplaced $pname
            }
        }

        if {[llength $unplaced] == 0} {
            puts "  All ports already placed"
            return 0
        }

        set unplaced [lsort $unplaced]

        switch -- $side {
            "left"   { set side_num 1 }
            "top"    { set side_num 2 }
            "right"  { set side_num 3 }
            "bottom" { set side_num 4 }
        }

        set die_bbox [get_die_boundary]
        set llx [lindex $die_bbox 0]
        set lly [lindex $die_bbox 1]
        set urx [lindex $die_bbox 2]
        set ury [lindex $die_bbox 3]

        puts ""
        puts "  Placing remaining: [llength $unplaced] ports on $side"
        puts "  ─────────────────────────────────────────────────────"

        set count 0
        for {set i 0} {$i < [llength $unplaced]} {incr i} {
            set pin_name [lindex $unplaced $i]
            set offset [expr {$start + ($i * $pitch)}]

            switch -- $side {
                "left"   { set x $llx; set y [expr {$lly + $offset}] }
                "right"  { set x $urx; set y [expr {$lly + $offset}] }
                "bottom" { set x [expr {$llx + $offset}]; set y $lly }
                "top"    { set x [expr {$llx + $offset}]; set y $ury }
            }

            set_individual_pin_constraints \
                -ports $pin_name \
                -allowed_layers $layer \
                -side $side_num \
                -location [list $x $y]

            lappend placed_pins $pin_name
            incr count
        }

        puts "  Placed: $count"
        return $count
    }

    # ── Legalize all pin placements ───────────────────────────────────────
    proc legalize {} {
        puts "\n  Legalizing pin placement..."
        place_pins -self
        puts "  Done."
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

            # Sort by location
            foreach item [lsort -index 0 $pin_list] {
                lappend lines [format "  %-30s %-6s %-6s %s" \
                    [lindex $item 0] [lindex $item 1] [lindex $item 2] [lindex $item 3]]
            }
        }

        lappend lines ""
        lappend lines "  Total: $total ports placed"
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

    # ── Set defaults ──────────────────────────────────────────────────────
    proc set_defaults {args} {
        variable default_layer
        variable default_pitch
        for {set i 0} {$i < [llength $args]} {incr i} {
            switch -- [lindex $args $i] {
                -layer { incr i; set default_layer [lindex $args $i] }
                -pitch { incr i; set default_pitch [lindex $args $i] }
            }
        }
        puts "  Defaults: layer=$default_layer pitch=${default_pitch}um"
    }

    # ── Reset placed pin tracking ─────────────────────────────────────────
    proc reset {} {
        variable placed_pins
        set placed_pins [list]
        puts "  Pin tracking reset"
    }

    namespace export place_pin_group place_remaining legalize \
                     report_pin_placement set_defaults reset
}

namespace import ::CBFlow::IOPin::*

# ═══════════════════════════════════════════════════════════════════════════════
# USAGE EXAMPLE (in FC shell):
#
#   source place_io_pins.tcl
#
#   # Set defaults (optional)
#   set_defaults -layer M4 -pitch 2.0
#
#   # Place by group name — auto-finds data_in[0..15], addr[0..11], etc.
#   place_pin_group "data_in"  -side left   -start 10.0
#   place_pin_group "addr"     -side left   -start 50.0
#   place_pin_group "data_out" -side right  -start 10.0
#   place_pin_group "clk"      -side bottom -start 30.0
#   place_pin_group "reset_n"  -side bottom -start 40.0
#   place_pin_group "scan"     -side top    -start 20.0 -layer M5 -pitch 5.0
#
#   # Place everything else on top
#   place_remaining -side top -start 60.0
#
#   # Legalize
#   legalize
#
#   # Report
#   report_pin_placement "reports/pin_placement.rpt"
# ═══════════════════════════════════════════════════════════════════════════════
