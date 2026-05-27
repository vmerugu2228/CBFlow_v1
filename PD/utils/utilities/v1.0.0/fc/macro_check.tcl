#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Macro Placement Validator — Fusion Compiler (fc_shell)
# Standalone. Reads design from FC session. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source macro_check.tcl
#   macro_check -min_channel 10.0
#   macro_check -min_channel 10.0 -min_boundary 5.0
#   macro_check -min_channel 10.0 -out macro_report.rpt
#
# ARGUMENTS:
#   -min_channel <um>      Minimum channel spacing between macros (required)
#   -min_boundary <um>     Minimum macro-to-die-boundary spacing (default: same as min_channel)
#   -valid_orient <list>   Allowed orientations (default: {N S FN FS})
#   -out <file>            Write report to file (default: stdout)
#
# CHECKS PERFORMED:
#   1. Macro-to-macro channel spacing (all pairs)
#   2. Macro-to-die-boundary spacing (all edges)
#   3. Macro orientation validity
#   4. Macro pin accessibility (routing channels to pins)
#
# EXAMPLES:
#   macro_check -min_channel 10.0
#   macro_check -min_channel 10.0 -min_boundary 5.0 -out macro_report.rpt
#   macro_check -min_channel 8.0 -valid_orient {N FN}
#
# FC-SPECIFIC COMMANDS USED:
#   get_cells -filter is_hard_macro
#   get_attribute (bbox, orientation, ref_name, full_name)
#   get_pins -of_objects / get_attribute [get_pins] direction layer_name
#   sizeof_collection
#   get_attribute [current_design] boundary
# ═══════════════════════════════════════════════════════════════════════════════

proc macro_check {args} {
    set min_channel ""
    set min_boundary ""
    set valid_orient {N S FN FS}
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -min_channel   { incr i; set min_channel [lindex $args $i] }
            -min_boundary  { incr i; set min_boundary [lindex $args $i] }
            -valid_orient  { incr i; set valid_orient [lindex $args $i] }
            -out           { incr i; set outfile [lindex $args $i] }
            default        { error "Unknown option: [lindex $args $i]" }
        }
    }

    if {$min_channel eq ""} { error "-min_channel required" }
    if {$min_boundary eq ""} { set min_boundary $min_channel }

    # Get all hard macros — FC: get_cells -filter is_hard_macro
    set macros [get_cells -quiet -filter "is_hard_macro == true"]
    if {$macros eq "" || [sizeof_collection $macros] == 0} {
        error "No hard macros found in design"
    }

    # Die boundary — FC: get_attribute [current_design] boundary
    set die_bbox [get_attribute [current_design] boundary]
    if {$die_bbox eq ""} { error "Cannot read design boundary" }
    set die_llx [lindex [lindex $die_bbox 0] 0]
    set die_lly [lindex [lindex $die_bbox 0] 1]
    set die_urx [lindex [lindex $die_bbox 1] 0]
    set die_ury [lindex [lindex $die_bbox 1] 1]

    # Collect macro info
    set macro_info [list]
    foreach_in_collection m $macros {
        set name [get_attribute $m full_name]
        set ref  [get_attribute $m ref_name]
        set bbox [get_attribute $m bbox]
        set orient [get_attribute $m orientation]
        set llx [lindex [lindex $bbox 0] 0]
        set lly [lindex [lindex $bbox 0] 1]
        set urx [lindex [lindex $bbox 1] 0]
        set ury [lindex [lindex $bbox 1] 1]
        lappend macro_info [list $name $ref $llx $lly $urx $ury $orient]
    }

    set violations [list]
    set total_macros [llength $macro_info]

    # ── Check 1: Macro-to-macro channel spacing ───────────────────────
    for {set a 0} {$a < $total_macros} {incr a} {
        set ma [lindex $macro_info $a]
        set na [lindex $ma 0]
        set a_llx [lindex $ma 2]; set a_lly [lindex $ma 3]
        set a_urx [lindex $ma 4]; set a_ury [lindex $ma 5]

        for {set b [expr {$a + 1}]} {$b < $total_macros} {incr b} {
            set mb [lindex $macro_info $b]
            set nb [lindex $mb 0]
            set b_llx [lindex $mb 2]; set b_lly [lindex $mb 3]
            set b_urx [lindex $mb 4]; set b_ury [lindex $mb 5]

            # Compute channel spacing (gap between nearest edges)
            set dx [_macro_gap $a_llx $a_urx $b_llx $b_urx]
            set dy [_macro_gap $a_lly $a_ury $b_lly $b_ury]

            # Overlapping in one axis means channel is in the other axis
            set overlap_x [expr {$a_llx < $b_urx && $b_llx < $a_urx}]
            set overlap_y [expr {$a_lly < $b_ury && $b_lly < $a_ury}]

            if {$overlap_x && $overlap_y} {
                lappend violations [list "OVERLAP" $na $nb \
                    "Macros overlap at ($a_llx,$a_lly)-($a_urx,$a_ury) vs ($b_llx,$b_lly)-($b_urx,$b_ury)"]
            } elseif {$overlap_y && $dx < $min_channel} {
                lappend violations [list "CHANNEL_X" $na $nb \
                    "Horizontal channel [format %.3f $dx] um < min [format %.3f $min_channel] um"]
            } elseif {$overlap_x && $dy < $min_channel} {
                lappend violations [list "CHANNEL_Y" $na $nb \
                    "Vertical channel [format %.3f $dy] um < min [format %.3f $min_channel] um"]
            }
        }
    }

    # ── Check 2: Macro-to-die-boundary spacing ────────────────────────
    foreach mi $macro_info {
        set name [lindex $mi 0]
        set m_llx [lindex $mi 2]; set m_lly [lindex $mi 3]
        set m_urx [lindex $mi 4]; set m_ury [lindex $mi 5]

        set gap_left   [expr {$m_llx - $die_llx}]
        set gap_bottom [expr {$m_lly - $die_lly}]
        set gap_right  [expr {$die_urx - $m_urx}]
        set gap_top    [expr {$die_ury - $m_ury}]

        if {$gap_left < $min_boundary} {
            lappend violations [list "BOUNDARY" $name "left" \
                "Left boundary gap [format %.3f $gap_left] um < min [format %.3f $min_boundary] um"]
        }
        if {$gap_bottom < $min_boundary} {
            lappend violations [list "BOUNDARY" $name "bottom" \
                "Bottom boundary gap [format %.3f $gap_bottom] um < min [format %.3f $min_boundary] um"]
        }
        if {$gap_right < $min_boundary} {
            lappend violations [list "BOUNDARY" $name "right" \
                "Right boundary gap [format %.3f $gap_right] um < min [format %.3f $min_boundary] um"]
        }
        if {$gap_top < $min_boundary} {
            lappend violations [list "BOUNDARY" $name "top" \
                "Top boundary gap [format %.3f $gap_top] um < min [format %.3f $min_boundary] um"]
        }
    }

    # ── Check 3: Orientation validity ─────────────────────────────────
    foreach mi $macro_info {
        set name [lindex $mi 0]
        set orient [lindex $mi 6]
        if {[lsearch -exact $valid_orient $orient] < 0} {
            lappend violations [list "ORIENT" $name $orient \
                "Orientation '$orient' not in allowed list: $valid_orient"]
        }
    }

    # ── Check 4: Pin accessibility ────────────────────────────────────
    foreach mi $macro_info {
        set name [lindex $mi 0]
        set m_llx [lindex $mi 2]; set m_lly [lindex $mi 3]
        set m_urx [lindex $mi 4]; set m_ury [lindex $mi 5]

        set pins [get_pins -quiet -of_objects [get_cells $name] -filter "direction == in || direction == out"]
        if {$pins eq "" || [sizeof_collection $pins] == 0} { continue }

        foreach_in_collection pin $pins {
            set pin_name [get_attribute $pin full_name]
            set pin_layer [get_attribute $pin layer_name]
            set pin_bbox [get_attribute $pin bbox]
            if {$pin_bbox eq ""} { continue }

            set pin_cx [expr {([lindex [lindex $pin_bbox 0] 0] + [lindex [lindex $pin_bbox 1] 0]) / 2.0}]
            set pin_cy [expr {([lindex [lindex $pin_bbox 0] 1] + [lindex [lindex $pin_bbox 1] 1]) / 2.0}]

            # Pin on left or right edge — needs horizontal channel
            set on_left  [expr {abs($pin_cx - $m_llx) < 0.1}]
            set on_right [expr {abs($pin_cx - $m_urx) < 0.1}]
            set on_bot   [expr {abs($pin_cy - $m_lly) < 0.1}]
            set on_top   [expr {abs($pin_cy - $m_ury) < 0.1}]

            if {$on_left} {
                set gap [expr {$m_llx - $die_llx}]
                if {$gap < $min_channel} {
                    lappend violations [list "PIN_ACCESS" $pin_name "left" \
                        "Pin on left edge, only [format %.3f $gap] um to boundary (need $min_channel um)"]
                }
            }
            if {$on_right} {
                set gap [expr {$die_urx - $m_urx}]
                if {$gap < $min_channel} {
                    lappend violations [list "PIN_ACCESS" $pin_name "right" \
                        "Pin on right edge, only [format %.3f $gap] um to boundary (need $min_channel um)"]
                }
            }
        }
    }

    # ── Report ────────────────────────────────────────────────────────
    set report [list]
    lappend report "═══════════════════════════════════════════════════════════════════"
    lappend report "  Macro Placement Check Report"
    lappend report "═══════════════════════════════════════════════════════════════════"
    lappend report "  Total macros       : $total_macros"
    lappend report "  Min channel        : $min_channel um"
    lappend report "  Min boundary       : $min_boundary um"
    lappend report "  Valid orientations : $valid_orient"
    lappend report "  Die boundary       : ($die_llx, $die_lly) - ($die_urx, $die_ury)"
    lappend report "───────────────────────────────────────────────────────────────────"

    if {[llength $violations] == 0} {
        lappend report "  PASS — No violations found"
    } else {
        lappend report "  FAIL — [llength $violations] violation(s) found"
        lappend report ""
        foreach v $violations {
            set vtype [lindex $v 0]
            switch -- $vtype {
                "OVERLAP"    { lappend report "  \[OVERLAP\]    [lindex $v 1] <-> [lindex $v 2]: [lindex $v 3]" }
                "CHANNEL_X"  { lappend report "  \[CHANNEL\]    [lindex $v 1] <-> [lindex $v 2]: [lindex $v 3]" }
                "CHANNEL_Y"  { lappend report "  \[CHANNEL\]    [lindex $v 1] <-> [lindex $v 2]: [lindex $v 3]" }
                "BOUNDARY"   { lappend report "  \[BOUNDARY\]   [lindex $v 1] ([lindex $v 2]): [lindex $v 3]" }
                "ORIENT"     { lappend report "  \[ORIENT\]     [lindex $v 1] ([lindex $v 2]): [lindex $v 3]" }
                "PIN_ACCESS" { lappend report "  \[PIN_ACCESS\] [lindex $v 1] ([lindex $v 2]): [lindex $v 3]" }
            }
        }
    }
    lappend report "═══════════════════════════════════════════════════════════════════"

    set report_text [join $report "\n"]

    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh $report_text
        close $fh
    } else {
        puts $report_text
    }

    return [llength $violations]
}

# ── Gap between two 1D intervals ─────────────────────────────────────────────
proc _macro_gap {a_lo a_hi b_lo b_hi} {
    if {$a_hi <= $b_lo} {
        return [expr {$b_lo - $a_hi}]
    } elseif {$b_hi <= $a_lo} {
        return [expr {$a_lo - $b_hi}]
    } else {
        return 0.0
    }
}
