#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# IO Pin Placement — Generates set_individual_pin_constraints for all ports
#
# Reads ports from design, snaps to track, writes constraint TCL file.
# No legalizer. No summary. Just constraints.
#
# Usage:
#   source place_io_pins.tcl
#   place_pins_on_side -side left -start 10.0 -layers {M4 M6} -out pins.tcl
#   source pins.tcl
# ═══════════════════════════════════════════════════════════════════════════════

proc place_pins_on_side {args} {
    set side ""
    set start 0.0
    set layers [list]
    set pitch_override ""
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -side   { incr i; set side [lindex $args $i] }
            -start  { incr i; set start [lindex $args $i] }
            -layers { incr i; set layers [lindex $args $i] }
            -layer  { incr i; set layers [list [lindex $args $i]] }
            -pitch  { incr i; set pitch_override [lindex $args $i] }
            -out    { incr i; set outfile [lindex $args $i] }
        }
    }

    if {$side eq ""} { error "-side required (left/right/top/bottom)" }
    if {[llength $layers] == 0} { error "-layers required (e.g. {M4} or {M4 M6})" }

    # Side number: 1=left, 2=top, 3=right, 4=bottom
    switch -- $side {
        "left"   { set side_num 1 }
        "top"    { set side_num 2 }
        "right"  { set side_num 3 }
        "bottom" { set side_num 4 }
        default  { error "Invalid side: $side" }
    }

    # Die boundary
    set bbox [get_attribute [current_design] boundary]
    set llx [lindex [lindex $bbox 0] 0]
    set lly [lindex [lindex $bbox 0] 1]
    set urx [lindex [lindex $bbox 1] 0]
    set ury [lindex [lindex $bbox 1] 1]

    # Get pitch per layer from tool technology
    set pitches [list]
    foreach l $layers {
        if {$pitch_override ne ""} {
            lappend pitches $pitch_override
        } else {
            set _lobj [get_layers $l -quiet]
            if {$_lobj eq "" || [sizeof_collection $_lobj] == 0} {
                error "Layer '$l' not found in technology"
            }
            set p [get_attribute $_lobj pitch]
            if {$p eq "" || $p <= 0} {
                error "Cannot read pitch for layer '$l' from technology"
            }
            lappend pitches $p
        }
    }
    set min_pitch [lindex $pitches 0]
    foreach p $pitches { if {$p < $min_pitch} { set min_pitch $p } }

    # Get all ports sorted
    set port_list [list]
    foreach_in_collection p [get_ports *] {
        lappend port_list [get_attribute $p full_name]
    }
    set port_list [lsort -dictionary $port_list]

    # Build constraint lines
    set layer_count [llength $layers]
    set lines [list]
    lappend lines "# Auto-generated pin constraints"
    lappend lines "# Side: $side | Layers: $layers | Start: $start | Pitch: $min_pitch"
    lappend lines ""

    for {set i 0} {$i < [llength $port_list]} {incr i} {
        set pin [lindex $port_list $i]
        set layer [lindex $layers [expr {$i % $layer_count}]]
        set layer_pitch [lindex $pitches [expr {$i % $layer_count}]]

        # Snap to track
        set raw [expr {$start + ($i * $min_pitch)}]
        set snapped [expr {round($raw / $layer_pitch) * $layer_pitch}]

        switch -- $side {
            "left"   { set x $llx; set y [expr {$lly + $snapped}] }
            "right"  { set x $urx; set y [expr {$lly + $snapped}] }
            "bottom" { set x [expr {$llx + $snapped}]; set y $lly }
            "top"    { set x [expr {$llx + $snapped}]; set y $ury }
        }

        lappend lines "set_individual_pin_constraints -ports {$pin} -allowed_layers {$layer} -side $side_num -location {$x $y}"
    }

    # Write or source directly
    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh [join $lines "\n"]
        close $fh
    } else {
        foreach line $lines {
            if {[string match "set_individual*" $line]} {
                eval $line
            }
        }
    }
}
