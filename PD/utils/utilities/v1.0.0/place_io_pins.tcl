#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# IO Pin Placement — Generates set_individual_pin_constraints
#
# Usage:
#   source place_io_pins.tcl
#
#   # All ports
#   place_pins -ports * -side left -start 10.0 -layers {M4}
#
#   # Pattern match
#   place_pins -ports "data_in*" -side left -start 10.0 -layers {M4 M6}
#
#   # Specific ports
#   place_pins -ports {clk reset_n} -side bottom -start 30.0 -layers {M5}
#
#   # Track pattern: 1=place, 0=skip (repeats)
#   # 11101110 = place 3 pins, skip 1 track, place 3 pins, skip 1 track, ...
#   place_pins -ports "data*" -side left -start 10.0 -layers {M4} -pattern 11101110
#
#   # Write to file instead of executing
#   place_pins -ports * -side left -start 10.0 -layers {M4} -out pins.tcl
# ═══════════════════════════════════════════════════════════════════════════════

proc place_pins {args} {
    set ports_arg ""
    set side ""
    set start 0.0
    set layers [list]
    set pitch_override ""
    set outfile ""
    set track_pattern ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -ports   { incr i; set ports_arg [lindex $args $i] }
            -side    { incr i; set side [lindex $args $i] }
            -start   { incr i; set start [lindex $args $i] }
            -layers  { incr i; set layers [lindex $args $i] }
            -layer   { incr i; set layers [list [lindex $args $i]] }
            -pitch   { incr i; set pitch_override [lindex $args $i] }
            -out     { incr i; set outfile [lindex $args $i] }
            -pattern { incr i; set track_pattern [lindex $args $i] }
        }
    }

    if {$ports_arg eq ""} { error "-ports required (* for all, pattern like data*, or list)" }
    if {$side eq ""}      { error "-side required (left/right/top/bottom)" }
    if {[llength $layers] == 0} { error "-layers required (e.g. {M4} or {M4 M6})" }

    # Side number
    switch -- $side {
        "left"   { set side_num 1 }
        "top"    { set side_num 2 }
        "right"  { set side_num 3 }
        "bottom" { set side_num 4 }
        default  { error "Invalid side: $side" }
    }

    # Die boundary
    set bbox [get_attribute [current_design] boundary]
    if {$bbox eq ""} { error "Cannot read design boundary" }
    set llx [lindex [lindex $bbox 0] 0]
    set lly [lindex [lindex $bbox 0] 1]
    set urx [lindex [lindex $bbox 1] 0]
    set ury [lindex [lindex $bbox 1] 1]

    # Get pitch per layer from tool
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

    # Resolve ports
    set port_list [list]
    if {$ports_arg eq "*"} {
        # All ports
        foreach_in_collection p [get_ports *] {
            lappend port_list [get_attribute $p full_name]
        }
    } elseif {[string match "*\**" $ports_arg] || [string match "*\?*" $ports_arg]} {
        # Glob pattern (data_in*, addr*, clk*)
        set matched [get_ports $ports_arg -quiet]
        if {$matched eq "" || [sizeof_collection $matched] == 0} {
            error "No ports match pattern: $ports_arg"
        }
        foreach_in_collection p $matched {
            lappend port_list [get_attribute $p full_name]
        }
    } else {
        # Explicit list or single name — also expand buses
        foreach name $ports_arg {
            set exact [get_ports $name -quiet]
            if {$exact ne "" && [sizeof_collection $exact] > 0} {
                foreach_in_collection p $exact {
                    lappend port_list [get_attribute $p full_name]
                }
            } else {
                # Try bus expansion
                set bus [get_ports "${name}\[*\]" -quiet]
                if {$bus ne "" && [sizeof_collection $bus] > 0} {
                    foreach_in_collection p $bus {
                        lappend port_list [get_attribute $p full_name]
                    }
                } else {
                    error "Port not found: $name"
                }
            }
        }
    }
    set port_list [lsort -dictionary $port_list]

    if {[llength $port_list] == 0} {
        error "No ports resolved"
    }

    # Parse track pattern (e.g., "11101110")
    set pattern_bits [list]
    if {$track_pattern ne ""} {
        foreach ch [split $track_pattern ""] {
            if {$ch ne "0" && $ch ne "1"} {
                error "Invalid pattern character '$ch' — use only 0 and 1"
            }
            lappend pattern_bits $ch
        }
        if {[llength $pattern_bits] == 0} {
            error "Empty track pattern"
        }
    }

    # Build constraints
    set layer_count [llength $layers]
    set pattern_len [llength $pattern_bits]
    set lines [list]
    set track_idx 0
    set pin_idx 0

    while {$pin_idx < [llength $port_list]} {
        # Check track pattern — skip if 0
        if {$pattern_len > 0} {
            set bit [lindex $pattern_bits [expr {$track_idx % $pattern_len}]]
            if {$bit eq "0"} {
                incr track_idx
                continue
            }
        }

        set pin [lindex $port_list $pin_idx]
        set layer [lindex $layers [expr {$pin_idx % $layer_count}]]
        set layer_pitch [lindex $pitches [expr {$pin_idx % $layer_count}]]

        # Snap to track
        set raw [expr {$start + ($track_idx * $min_pitch)}]
        set snapped [expr {round($raw / $layer_pitch) * $layer_pitch}]

        switch -- $side {
            "left"   { set x $llx; set y [expr {$lly + $snapped}] }
            "right"  { set x $urx; set y [expr {$lly + $snapped}] }
            "bottom" { set x [expr {$llx + $snapped}]; set y $lly }
            "top"    { set x [expr {$llx + $snapped}]; set y $ury }
        }

        lappend lines "set_individual_pin_constraints -ports {$pin} -allowed_layers {$layer} -side $side_num -location {$x $y}"

        incr pin_idx
        incr track_idx
    }

    # Write or execute
    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh [join $lines "\n"]
        close $fh
    } else {
        foreach line $lines {
            eval $line
        }
    }
}
