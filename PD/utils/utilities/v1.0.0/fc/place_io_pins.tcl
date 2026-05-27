#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# IO Pin Placement — Fusion Compiler (fc_shell)
# Standalone. Reads technology from FC. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source place_io_pins.tcl
#   place_io -ports <sel> -side <side> -start <um> -layers <list> [options]
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
#   place_io -ports * -side left -start 10.0 -layers {M4}
#   place_io -ports "data*" -side left -start 10.0 -layers {M4 M6}
#   place_io -ports {clk reset_n} -side bottom -start 30.0 -layers {M5}
#   place_io -ports "data*" -side right -start 10.0 -layers {M4} -pattern 11101110
#   place_io -ports * -side right -start 5.0 -layers {M4} -out pins.tcl
#
# FC-SPECIFIC COMMANDS USED:
#   get_attribute [current_design] boundary
#   get_layers / get_attribute [get_layers] pitch
#   get_ports / get_attribute [get_ports] full_name / sizeof_collection
#   set_pin_physical_constraints (places immediately — no place_pins needed)
# ═══════════════════════════════════════════════════════════════════════════════

proc place_io {args} {
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

    # FC side: 1=left, 2=top, 3=right, 4=bottom
    switch -- $side {
        "left"   { set side_num 1 }
        "top"    { set side_num 2 }
        "right"  { set side_num 3 }
        "bottom" { set side_num 4 }
        default  { error "Invalid side: $side" }
    }

    # Die boundary — FC: get_attribute [current_design] boundary
    set bbox [get_attribute [current_design] boundary]
    if {$bbox eq ""} { error "Cannot read design boundary" }
    set llx [lindex [lindex $bbox 0] 0]
    set lly [lindex [lindex $bbox 0] 1]
    set urx [lindex [lindex $bbox 1] 0]
    set ury [lindex [lindex $bbox 1] 1]

    # Layer pitch — FC: get_attribute [get_layers] pitch
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
                error "Cannot read pitch for layer '$l'"
            }
            lappend pitches $p
        }
    }
    set min_pitch [lindex $pitches 0]
    foreach p $pitches { if {$p < $min_pitch} { set min_pitch $p } }

    # Resolve ports — FC: get_ports, foreach_in_collection, sizeof_collection
    set port_list [_resolve_ports_fc $ports_arg]
    if {[llength $port_list] == 0} { error "No ports resolved" }

    # Track pattern
    set pattern_bits [_parse_pattern $track_pattern]

    # Build constraints — FC: set_individual_pin_constraints
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

        lappend lines "set_pin_physical_constraints -pin_name {$pin} -layers {$layer} -side $side_num -offset $snapped"
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

# ── FC port resolution ────────────────────────────────────────────────────
proc _resolve_ports_fc {ports_arg} {
    set port_list [list]
    if {$ports_arg eq "*"} {
        foreach_in_collection p [get_ports *] {
            lappend port_list [get_attribute $p full_name]
        }
    } elseif {[string match "*\**" $ports_arg] || [string match "*\?*" $ports_arg]} {
        set matched [get_ports $ports_arg -quiet]
        if {$matched eq "" || [sizeof_collection $matched] == 0} {
            error "No ports match: $ports_arg"
        }
        foreach_in_collection p $matched {
            lappend port_list [get_attribute $p full_name]
        }
    } else {
        foreach name $ports_arg {
            set exact [get_ports $name -quiet]
            if {$exact ne "" && [sizeof_collection $exact] > 0} {
                foreach_in_collection p $exact {
                    lappend port_list [get_attribute $p full_name]
                }
            } else {
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
    return [lsort -dictionary $port_list]
}

# ── Pattern parser (shared) ──────────────────────────────────────────────
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
