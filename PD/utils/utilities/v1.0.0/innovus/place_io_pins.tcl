#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# IO Pin Placement — Cadence Innovus
# Standalone. Reads technology from Innovus. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source place_io_pins.tcl
#   place_pins -ports <sel> -side <side> -start <um> -layers <list> [options]
#
# ARGUMENTS:
#   -ports <sel>       Port selection:
#                        *           All design ports
#                        "data*"     Glob pattern
#                        {clk rst}   Explicit list (buses auto-expand)
#   -side <side>       left | right | top | bottom
#   -start <um>        Starting offset from corner in microns
#   -layers <list>     {M4} or {M4 M6} (pins alternate layers)
#   -pitch <um>        Override track pitch (default: from technology)
#   -pattern <bits>    8-digit track pattern: 1=place 0=skip (repeats)
#                        "11101110" = 3 on, 1 off, repeat
#                        "10101010" = every other track
#   -out <file>        Write TCL file instead of executing
#
# SIDE REFERENCE:
#                ┌──────── top ────────┐
#   start→      │                     │      ←start
#   offset      left                right     offset
#   bottom→up   │                     │      bottom→up
#                └────── bottom ───────┘
#                         start→ left to right
#
# EXAMPLES:
#   place_pins -ports * -side left -start 10.0 -layers {M4}
#   place_pins -ports "data*" -side left -start 10.0 -layers {M4 M6}
#   place_pins -ports {clk reset_n} -side bottom -start 30.0 -layers {M5}
#   place_pins -ports "data*" -side right -start 10.0 -layers {M4} -pattern 11101110
#   place_pins -ports * -side right -start 5.0 -layers {M4} -out pins.tcl
#
# INNOVUS-SPECIFIC COMMANDS USED:
#   dbGet top.fPlan.box
#   dbGet [dbGet head.layers.name <layer> -p].pitchX / pitchY
#   dbGet [dbGet top.terms.name <port> -p].name
#   editPin / setPinConstraint
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

    if {$ports_arg eq ""} { error "-ports required" }
    if {$side eq ""}      { error "-side required (left/right/top/bottom)" }
    if {[llength $layers] == 0} { error "-layers required" }

    # Validate side
    if {$side ni {left right top bottom}} {
        error "Invalid side: $side"
    }

    # Die boundary — Innovus: dbGet top.fPlan.box
    set fplan_box [dbGet top.fPlan.box]
    if {$fplan_box eq ""} { error "Cannot read floorplan boundary" }
    set llx [lindex [lindex $fplan_box 0] 0]
    set lly [lindex [lindex $fplan_box 0] 1]
    set urx [lindex [lindex $fplan_box 1] 0]
    set ury [lindex [lindex $fplan_box 1] 1]

    # Layer pitch — Innovus: dbGet head.layers pitch
    set pitches [list]
    foreach l $layers {
        if {$pitch_override ne ""} {
            lappend pitches $pitch_override
        } else {
            set layer_ptr [dbGet head.layers.name $l -p]
            if {$layer_ptr eq "0x0" || $layer_ptr eq ""} {
                error "Layer '$l' not found in technology"
            }
            # Use pitchX for vertical layers, pitchY for horizontal
            set dir [dbGet ${layer_ptr}.direction]
            if {$dir eq "Vertical"} {
                set p [dbGet ${layer_ptr}.pitchX]
            } else {
                set p [dbGet ${layer_ptr}.pitchY]
            }
            if {$p eq "" || $p <= 0} {
                error "Cannot read pitch for layer '$l'"
            }
            lappend pitches $p
        }
    }
    set min_pitch [lindex $pitches 0]
    foreach p $pitches { if {$p < $min_pitch} { set min_pitch $p } }

    # Resolve ports — Innovus: dbGet top.terms.name
    set port_list [_resolve_ports_innovus $ports_arg]
    if {[llength $port_list] == 0} { error "No ports resolved" }

    # Track pattern
    set pattern_bits [_parse_pattern $track_pattern]

    # Build constraints — Innovus: editPin
    set layer_count [llength $layers]
    set pattern_len [llength $pattern_bits]
    set lines [list]
    set track_idx 0
    set pin_idx 0

    while {$pin_idx < [llength $port_list]} {
        if {$pattern_len > 0} {
            if {[lindex $pattern_bits [expr {$track_idx % $pattern_len}]] eq "0"} {
                incr track_idx
                continue
            }
        }

        set pin [lindex $port_list $pin_idx]
        set layer [lindex $layers [expr {$pin_idx % $layer_count}]]
        set layer_pitch [lindex $pitches [expr {$pin_idx % $layer_count}]]

        set raw [expr {$start + ($track_idx * $min_pitch)}]
        set snapped [expr {round($raw / $layer_pitch) * $layer_pitch}]

        switch -- $side {
            "left"   { set x $llx; set y [expr {$lly + $snapped}] }
            "right"  { set x $urx; set y [expr {$lly + $snapped}] }
            "bottom" { set x [expr {$llx + $snapped}]; set y $lly }
            "top"    { set x [expr {$llx + $snapped}]; set y $ury }
        }

        # Innovus editPin command
        lappend lines "editPin -pin {$pin} -layer $layer -assign {$x $y} -side $side"
        incr pin_idx
        incr track_idx
    }

    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh [join $lines "\n"]
        close $fh
    } else {
        foreach line $lines { eval $line }
    }
}

# ── Innovus port resolution ───────────────────────────────────────────────
proc _resolve_ports_innovus {ports_arg} {
    set port_list [list]
    if {$ports_arg eq "*"} {
        set port_list [dbGet top.terms.name]
    } elseif {[string match "*\**" $ports_arg] || [string match "*\?*" $ports_arg]} {
        set all_terms [dbGet top.terms.name]
        foreach t $all_terms {
            if {[string match $ports_arg $t]} {
                lappend port_list $t
            }
        }
        if {[llength $port_list] == 0} {
            error "No ports match: $ports_arg"
        }
    } else {
        set all_terms [dbGet top.terms.name]
        foreach name $ports_arg {
            # Exact match
            if {[lsearch -exact $all_terms $name] >= 0} {
                lappend port_list $name
            } else {
                # Bus expansion
                set bus_matches [lsearch -all -inline $all_terms "${name}\[*\]"]
                if {[llength $bus_matches] > 0} {
                    set port_list [concat $port_list $bus_matches]
                } else {
                    error "Port not found: $name"
                }
            }
        }
    }
    return [lsort -dictionary $port_list]
}

# ── Pattern parser ────────────────────────────────────────────────────────
proc _parse_pattern {track_pattern} {
    if {$track_pattern eq ""} { return [list] }
    if {[string length $track_pattern] != 8} {
        error "Track pattern must be exactly 8 digits (e.g., 11101110). Got: $track_pattern"
    }
    set bits [list]
    foreach ch [split $track_pattern ""] {
        if {$ch ne "0" && $ch ne "1"} {
            error "Invalid pattern character '$ch' — use only 0 and 1"
        }
        lappend bits $ch
    }
    return $bits
}
