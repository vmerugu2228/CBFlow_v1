#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Auto-Generate Blockages Around Macros — Fusion Compiler (fc_shell)
# Standalone. Reads design from FC session. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source add_blockages.tcl
#   add_blockages -halo 5.0
#   add_blockages -halo 5.0 -density_margin 10.0 -density_pct 50
#   add_blockages -macros {RAM_A RAM_B} -halo 3.0 -layers {M4 M5}
#   add_blockages -halo 5.0 -out blockages.tcl
#
# ARGUMENTS:
#   -macros <list>           Specific macro names (default: all hard macros)
#   -halo <um>               Placement keepout halo around each macro (required)
#   -density_margin <um>     Extra margin for routing density blockage (default: 0 = no density blockage)
#   -density_pct <0-100>     Routing density percentage limit (default: 50)
#   -layers <list>           Routing layers for density blockage (default: all routing layers)
#   -out <file>              Write TCL commands to file instead of executing
#
# EXAMPLES:
#   # Placement halo only — all macros
#   add_blockages -halo 5.0
#
#   # Placement halo + routing density blockage
#   add_blockages -halo 5.0 -density_margin 10.0 -density_pct 40
#
#   # Specific macros, specific layers
#   add_blockages -macros {SRAM_256x32 ROM_BLOCK} -halo 3.0 -density_margin 8.0 -layers {M3 M4 M5}
#
#   # Write to file for review before sourcing
#   add_blockages -halo 5.0 -density_margin 10.0 -density_pct 50 -out blockages.tcl
#
# FC-SPECIFIC COMMANDS USED:
#   get_cells -filter is_hard_macro
#   get_attribute (bbox, full_name, ref_name)
#   sizeof_collection
#   create_placement_blockage -boundary
#   create_routing_blockage -boundary -layers -blocked_percentage
# ═══════════════════════════════════════════════════════════════════════════════

proc add_blockages {args} {
    set macro_names [list]
    set halo ""
    set density_margin 0
    set density_pct 50
    set layers [list]
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -macros         { incr i; set macro_names [lindex $args $i] }
            -halo           { incr i; set halo [lindex $args $i] }
            -density_margin { incr i; set density_margin [lindex $args $i] }
            -density_pct    { incr i; set density_pct [lindex $args $i] }
            -layers         { incr i; set layers [lindex $args $i] }
            -out            { incr i; set outfile [lindex $args $i] }
            default         { error "Unknown option: [lindex $args $i]" }
        }
    }

    if {$halo eq ""} { error "-halo required" }
    if {$density_pct < 0 || $density_pct > 100} { error "-density_pct must be 0-100" }

    # Resolve macros — FC: get_cells -filter is_hard_macro
    if {[llength $macro_names] > 0} {
        set macro_cells [list]
        foreach mname $macro_names {
            set cell [get_cells -quiet $mname]
            if {$cell eq "" || [sizeof_collection $cell] == 0} {
                error "Macro not found: $mname"
            }
            set is_macro [get_attribute $cell is_hard_macro]
            if {$is_macro ne "true"} {
                error "Cell '$mname' is not a hard macro"
            }
            lappend macro_cells $cell
        }
    } else {
        set all_macros [get_cells -quiet -filter "is_hard_macro == true"]
        if {$all_macros eq "" || [sizeof_collection $all_macros] == 0} {
            error "No hard macros found in design"
        }
        set macro_cells [list]
        foreach_in_collection m $all_macros {
            lappend macro_cells $m
        }
    }

    set commands [list]
    set placement_count 0
    set density_count 0

    foreach cell $macro_cells {
        set name [get_attribute $cell full_name]
        set ref  [get_attribute $cell ref_name]
        set bbox [get_attribute $cell bbox]

        set m_llx [lindex [lindex $bbox 0] 0]
        set m_lly [lindex [lindex $bbox 0] 1]
        set m_urx [lindex [lindex $bbox 1] 0]
        set m_ury [lindex [lindex $bbox 1] 1]

        # ── Placement blockage (halo) ─────────────────────────────────
        set p_llx [expr {$m_llx - $halo}]
        set p_lly [expr {$m_lly - $halo}]
        set p_urx [expr {$m_urx + $halo}]
        set p_ury [expr {$m_ury + $halo}]

        lappend commands "# Placement blockage: $name ($ref)"
        lappend commands "create_placement_blockage -boundary \{[list $p_llx $p_lly $p_urx $p_ury]\} -type hard"
        incr placement_count

        # ── Routing density blockage ──────────────────────────────────
        if {$density_margin > 0} {
            set d_llx [expr {$m_llx - $density_margin}]
            set d_lly [expr {$m_lly - $density_margin}]
            set d_urx [expr {$m_urx + $density_margin}]
            set d_ury [expr {$m_ury + $density_margin}]

            set layer_arg ""
            if {[llength $layers] > 0} {
                set layer_arg "-layers \{[join $layers " "]\}"
            }

            lappend commands "# Routing density blockage: $name ($ref) — ${density_pct}% max"
            if {$layer_arg ne ""} {
                lappend commands "create_routing_blockage -boundary \{[list $d_llx $d_lly $d_urx $d_ury]\} $layer_arg -blocked_percentage $density_pct"
            } else {
                lappend commands "create_routing_blockage -boundary \{[list $d_llx $d_lly $d_urx $d_ury]\} -blocked_percentage $density_pct"
            }
            incr density_count
        }

        lappend commands ""
    }

    # ── Summary ───────────────────────────────────────────────────────
    set summary [list]
    lappend summary "# ═══════════════════════════════════════════════════════════════"
    lappend summary "# Blockage Summary"
    lappend summary "#   Macros processed       : [llength $macro_cells]"
    lappend summary "#   Placement blockages     : $placement_count (halo: ${halo} um)"
    if {$density_margin > 0} {
        lappend summary "#   Routing density blocks  : $density_count (margin: ${density_margin} um, max: ${density_pct}%)"
        if {[llength $layers] > 0} {
            lappend summary "#   Layers                  : [join $layers ", "]"
        } else {
            lappend summary "#   Layers                  : all routing layers"
        }
    }
    lappend summary "# ═══════════════════════════════════════════════════════════════"

    # ── Output: TCL file ──────────────────────────────────────────────
    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh [join $summary "\n"]
        puts $fh ""
        puts $fh [join $commands "\n"]
        close $fh
        puts "Wrote [llength $macro_cells] macro blockage commands to $outfile"
        return
    }

    # ── Output: Execute directly ──────────────────────────────────────
    puts [join $summary "\n"]
    puts ""
    foreach cmd $commands {
        if {[string index $cmd 0] eq "#" || $cmd eq ""} {
            puts $cmd
            continue
        }
        puts "  $cmd"
        eval $cmd
    }
}
