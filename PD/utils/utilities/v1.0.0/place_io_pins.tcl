#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — IO Pin Placement Script for Fusion Compiler
#
# Places pins group-wise on specified sides with user-defined starting points.
# Supports: left, right, top, bottom sides with configurable pitch and layers.
#
# Usage:
#   source place_io_pins.tcl
#   place_io_pins $pin_groups
#
# Pin Group Format:
#   array set pin_groups {
#       group_name {
#           side        "left|right|top|bottom"
#           start       <offset_in_microns>
#           layer       "M4|M5|..."
#           pitch       <spacing_in_microns>
#           direction   "in|out|inout"
#           pins        {pin1 pin2 pin3 ...}
#       }
#   }
#
# Example:
#   array set pin_groups {
#       data_bus {
#           side "left" start 10.0 layer "M4" pitch 2.0 direction "in"
#           pins {data[0] data[1] data[2] data[3] data[4] data[5] data[6] data[7]}
#       }
#       addr_bus {
#           side "left" start 30.0 layer "M4" pitch 2.0 direction "in"
#           pins {addr[0] addr[1] addr[2] addr[3] addr[4] addr[5]}
#       }
#       clk_pins {
#           side "bottom" start 50.0 layer "M5" pitch 5.0 direction "in"
#           pins {clk reset_n scan_en}
#       }
#       output_bus {
#           side "right" start 10.0 layer "M4" pitch 2.0 direction "out"
#           pins {out[0] out[1] out[2] out[3] out[4] out[5] out[6] out[7]}
#       }
#   }
#
#   place_io_pins pin_groups
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::IOPin {

    # ── Get die boundary ──────────────────────────────────────────────────
    proc get_die_boundary {} {
        # Returns {llx lly urx ury} in microns
        set bbox [get_attribute [current_design] boundary]
        if {$bbox eq ""} {
            # Fallback: read from design
            set bbox [get_attribute [get_core_area] bbox]
        }
        set llx [lindex [lindex $bbox 0] 0]
        set lly [lindex [lindex $bbox 0] 1]
        set urx [lindex [lindex $bbox 1] 0]
        set ury [lindex [lindex $bbox 1] 1]
        return [list $llx $lly $urx $ury]
    }

    # ── Compute pin coordinates for a side ────────────────────────────────
    proc compute_pin_locations {side start pitch pin_count die_bbox} {
        set llx [lindex $die_bbox 0]
        set lly [lindex $die_bbox 1]
        set urx [lindex $die_bbox 2]
        set ury [lindex $die_bbox 3]

        set locations [list]
        for {set i 0} {$i < $pin_count} {incr i} {
            set offset [expr {$start + ($i * $pitch)}]
            switch -- $side {
                "left" {
                    lappend locations [list $llx [expr {$lly + $offset}]]
                }
                "right" {
                    lappend locations [list $urx [expr {$lly + $offset}]]
                }
                "bottom" {
                    lappend locations [list [expr {$llx + $offset}] $lly]
                }
                "top" {
                    lappend locations [list [expr {$llx + $offset}] $ury]
                }
                default {
                    error "Invalid side: $side (must be left/right/top/bottom)"
                }
            }
        }
        return $locations
    }

    # ── Place a single pin ────────────────────────────────────────────────
    proc place_pin {pin_name x y layer side} {
        # Determine orientation from side
        switch -- $side {
            "left"   { set orient "W" }
            "right"  { set orient "E" }
            "bottom" { set orient "S" }
            "top"    { set orient "N" }
        }

        # FC command to place the pin
        set port [get_ports $pin_name -quiet]
        if {$port eq ""} {
            puts "WARNING: Port '$pin_name' not found in design — skipping"
            return 0
        }

        set_individual_pin_constraints \
            -ports $pin_name \
            -allowed_layers $layer \
            -side [expr {$side eq "left" ? 1 : ($side eq "top" ? 2 : ($side eq "right" ? 3 : 4))}] \
            -location [list $x $y]

        puts "  PIN: $pin_name → ($x, $y) on $layer [$side]"
        return 1
    }

    # ── Main: place all pin groups ────────────────────────────────────────
    proc place_groups {groups_var} {
        upvar 1 $groups_var groups

        set die_bbox [get_die_boundary]
        set llx [lindex $die_bbox 0]
        set lly [lindex $die_bbox 1]
        set urx [lindex $die_bbox 2]
        set ury [lindex $die_bbox 3]

        puts ""
        puts "═══════════════════════════════════════════════════════════"
        puts "  IO Pin Placement"
        puts "═══════════════════════════════════════════════════════════"
        puts "  Die: ($llx, $lly) to ($urx, $ury)"
        puts "───────────────────────────────────────────────────────────"

        set total_placed 0
        set total_skipped 0

        foreach group_name [array names groups] {
            set cfg $groups($group_name)

            # Parse group config
            array set g {}
            foreach {key val} $cfg {
                set g($key) $val
            }

            set side     $g(side)
            set start    $g(start)
            set layer    $g(layer)
            set pitch    [expr {[info exists g(pitch)] ? $g(pitch) : 2.0}]
            set pins     $g(pins)
            set direction [expr {[info exists g(direction)] ? $g(direction) : "inout"}]

            set pin_count [llength $pins]
            set end_offset [expr {$start + (($pin_count - 1) * $pitch)}]

            puts ""
            puts "  Group: $group_name ($pin_count pins)"
            puts "  Side: $side | Layer: $layer | Start: ${start}um | Pitch: ${pitch}um"
            puts "  Direction: $direction | Range: ${start}um → ${end_offset}um"
            puts "  ─────────────────────────────────────────────────────"

            # Validate range doesn't exceed die boundary
            switch -- $side {
                "left" - "right" {
                    set max_range [expr {$ury - $lly}]
                    if {$end_offset > $max_range} {
                        puts "  WARNING: Pin range ${end_offset}um exceeds die height ${max_range}um"
                    }
                }
                "top" - "bottom" {
                    set max_range [expr {$urx - $llx}]
                    if {$end_offset > $max_range} {
                        puts "  WARNING: Pin range ${end_offset}um exceeds die width ${max_range}um"
                    }
                }
            }

            # Compute locations
            set locations [compute_pin_locations $side $start $pitch $pin_count $die_bbox]

            # Place each pin
            set group_placed 0
            for {set i 0} {$i < $pin_count} {incr i} {
                set pin_name [lindex $pins $i]
                set loc [lindex $locations $i]
                set x [lindex $loc 0]
                set y [lindex $loc 1]

                set ok [place_pin $pin_name $x $y $layer $side]
                if {$ok} {
                    incr group_placed
                } else {
                    incr total_skipped
                }
            }

            set total_placed [expr {$total_placed + $group_placed}]
            puts "  Placed: $group_placed / $pin_count"
        }

        # Run place_pins to legalize
        puts ""
        puts "  Running place_pins to legalize..."
        place_pins -self

        puts ""
        puts "═══════════════════════════════════════════════════════════"
        puts "  IO Pin Placement Complete"
        puts "═══════════════════════════════════════════════════════════"
        puts "  Total placed:  $total_placed"
        puts "  Total skipped: $total_skipped"
        puts "  Groups:        [array size groups]"
        puts "═══════════════════════════════════════════════════════════"
        puts ""

        return $total_placed
    }

    # ── Convenience: place from a config file ─────────────────────────────
    proc place_from_file {config_file} {
        if {![file exists $config_file]} {
            error "Pin config file not found: $config_file"
        }
        puts "  Loading pin config: $config_file"
        source $config_file
        # Expects pin_groups array to be defined in the config file
        if {![array exists ::pin_groups]} {
            error "Config file must define 'pin_groups' array"
        }
        return [place_groups ::pin_groups]
    }

    # ── Generate pin placement report ─────────────────────────────────────
    proc report_pin_placement {{output_file ""}} {
        set report ""
        append report "═══════════════════════════════════════════════════════════\n"
        append report "  IO Pin Placement Report\n"
        append report "  Design: [get_attribute [current_design] full_name]\n"
        append report "═══════════════════════════════════════════════════════════\n"

        foreach side {1 2 3 4} {
            set side_name [lindex {- left top right bottom} $side]
            set pins [get_ports -filter "side==$side" -quiet]
            if {$pins eq ""} continue
            set count [sizeof_collection $pins]

            append report "\n  $side_name side ($count pins):\n"
            append report "  ─────────────────────────────────────────────────────\n"
            foreach_in_collection p $pins {
                set name [get_attribute $p full_name]
                set layer [get_attribute $p layer_name]
                set loc [get_attribute $p location]
                set dir [get_attribute $p direction]
                append report [format "    %-30s %-4s %-6s %s\n" $name $layer $dir $loc]
            }
        }

        append report "\n═══════════════════════════════════════════════════════════\n"

        if {$output_file ne ""} {
            set fh [open $output_file "w"]
            puts $fh $report
            close $fh
            puts "  Report written to: $output_file"
        } else {
            puts $report
        }
    }

    namespace export place_groups place_from_file report_pin_placement
}

namespace import ::CBFlow::IOPin::*

# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE USAGE (uncomment to test)
# ═══════════════════════════════════════════════════════════════════════════════
#
# array set pin_groups {
#     data_in {
#         side "left" start 10.0 layer "M4" pitch 2.0 direction "in"
#         pins {data_in[0] data_in[1] data_in[2] data_in[3]
#               data_in[4] data_in[5] data_in[6] data_in[7]}
#     }
#     addr_in {
#         side "left" start 30.0 layer "M4" pitch 2.0 direction "in"
#         pins {addr[0] addr[1] addr[2] addr[3]
#               addr[4] addr[5] addr[6] addr[7]
#               addr[8] addr[9] addr[10] addr[11]}
#     }
#     control {
#         side "bottom" start 20.0 layer "M5" pitch 5.0 direction "in"
#         pins {clk reset_n scan_en scan_in test_mode}
#     }
#     data_out {
#         side "right" start 10.0 layer "M4" pitch 2.0 direction "out"
#         pins {data_out[0] data_out[1] data_out[2] data_out[3]
#               data_out[4] data_out[5] data_out[6] data_out[7]}
#     }
#     scan_out {
#         side "top" start 50.0 layer "M5" pitch 3.0 direction "out"
#         pins {scan_out[0] scan_out[1] scan_out[2] scan_out[3]}
#     }
# }
#
# place_io_pins pin_groups
# report_pin_placement "reports/pin_placement.rpt"
