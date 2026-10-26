#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Congestion Analysis — Fusion Compiler (fc_shell)
# Standalone. Parses report_congestion output. No CBflow dependency.
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source congestion_debug.tcl
#   analyze_congestion -rpt <file> [-top <N>] [-suggest] [-out <file>]
#   analyze_congestion -live [-top <N>] [-suggest] [-out <file>]
#
# ARGUMENTS:
#   -rpt <file>     Path to report_congestion output (report mode, tclsh)
#   -live           Run report_congestion -nosplit inside FC (FC mode)
#   -top <N>        Top congested regions to show (default: 10)
#   -suggest        Print fix actions for congested layers/regions
#   -out <file>     Write report to file instead of stdout
#
# EXAMPLES:
#   analyze_congestion -rpt congestion.rpt -top 20 -suggest
#   analyze_congestion -live -suggest -out cong_summary.rpt
#
# FC-SPECIFIC COMMANDS USED (live mode only):
#   redirect -variable v { report_congestion -nosplit }
# ═══════════════════════════════════════════════════════════════════════════════

proc analyze_congestion {args} {
    set rpt_file ""; set live 0; set top_n 10; set suggest 0; set outfile ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -rpt     { incr i; set rpt_file [lindex $args $i] }
            -live    { set live 1 }
            -top     { incr i; set top_n [lindex $args $i] }
            -suggest { set suggest 1 }
            -out     { incr i; set outfile [lindex $args $i] }
            default  { error "Unknown option: [lindex $args $i]" }
        }
    }
    if {$rpt_file eq "" && !$live} { error "Either -rpt <file> or -live required" }
    if {$rpt_file ne "" && $live}  { error "Cannot use both -rpt and -live" }

    if {$live} {
        if {[catch {redirect -variable content { report_congestion -nosplit }} err]} {
            error "Failed to run report_congestion: $err"
        }
    } else {
        if {![file exists $rpt_file]} { error "Report not found: $rpt_file" }
        set fh [open $rpt_file "r"]; set content [read $fh]; close $fh
    }
    set lines [split $content "\n"]
    if {[llength $lines] == 0} { error "Report content is empty" }

    # ── Parse per-layer overflow (H and V separately) ─────────────────
    array set h_ovfl {}; array set v_ovfl {}
    array set h_trk {};  array set v_trk {}
    set regions [list]; set in_layer 0; set in_region 0

    foreach line $lines {
        set t [string trim $line]
        if {$t eq "" || [regexp {^[-=]+$} $t]} continue
        if {[regexp -nocase {Layer.*Dir.*Overflow|Layer.*Tracks.*Overflow} $t]} {
            set in_layer 1; set in_region 0; continue
        }
        if {[regexp -nocase {Hotspot|Region|Congested.*Area|GRC} $t]} {
            set in_region 1; set in_layer 0; continue
        }
        if {$in_layer && [regexp {^\s*(\S+)\s+(H|V|Horizontal|Vertical)\s+(\d+)\s+(\d+)} $t -> ly dir trk ovf]} {
            set d [string toupper [string index $dir 0]]
            if {$d eq "H"} { set h_ovfl($ly) $ovf; set h_trk($ly) $trk
            } else          { set v_ovfl($ly) $ovf; set v_trk($ly) $trk }
            continue
        }
        if {$in_region && [regexp {([\d\.\-]+)\s*[,\s]\s*([\d\.\-]+)\s*\)?\s*\(?\s*([\d\.\-]+)\s*[,\s]\s*([\d\.\-]+)\s*\)?\s+(\d+)} \
                $t -> x1 y1 x2 y2 ovf]} {
            set rl ""; regexp {(M\d+|METAL\d+)\s*$} $t -> rl
            lappend regions [list $x1 $y1 $x2 $y2 $ovf $rl]
        }
    }
    set has_layers [expr {[array size h_ovfl] > 0 || [array size v_ovfl] > 0}]
    if {!$has_layers && [llength $regions] == 0} { error "No congestion data parsed" }

    # ── Build output ──────────────────────────────────────────────────
    set out [list]
    lappend out "═══════════════════════════════════════════════════════════════"
    lappend out " CONGESTION ANALYSIS"
    lappend out " Source: [expr {$rpt_file ne {} ? $rpt_file : {live FC session}}]"
    lappend out "═══════════════════════════════════════════════════════════════"
    lappend out ""

    foreach {label arr_o arr_t} [list "Horizontal (H)" h_ovfl h_trk "Vertical (V)" v_ovfl v_trk] {
        upvar 0 $arr_o ovfl_arr; upvar 0 $arr_t trk_arr
        if {[array size ovfl_arr] == 0} continue
        lappend out "── $label Overflow by Layer ─────────────────────────────"
        lappend out [format "  %-12s %10s %10s %8s" "Layer" "Tracks" "Overflow" "Pct"]
        set tot_t 0; set tot_o 0
        foreach ly [lsort [array names ovfl_arr]] {
            set tk $trk_arr($ly); set ov $ovfl_arr($ly)
            incr tot_t $tk; incr tot_o $ov
            set p [expr {$tk > 0 ? [format "%.2f%%" [expr {100.0*$ov/$tk}]] : "N/A"}]
            lappend out [format "  %-12s %10d %10d %8s" $ly $tk $ov $p]
        }
        set tp [expr {$tot_t > 0 ? [format "%.2f%%" [expr {100.0*$tot_o/$tot_t}]] : "N/A"}]
        lappend out [format "  %-12s %10d %10d %8s" "TOTAL" $tot_t $tot_o $tp]
        lappend out ""
    }

    if {[llength $regions] > 0} {
        set sorted [lsort -integer -decreasing -index 4 $regions]
        lappend out "── Top $top_n Congested Regions ────────────────────────────"
        lappend out [format "  %-4s %-36s %10s %8s" "#" "Coordinates" "Overflow" "Layer"]
        set n 0
        foreach reg $sorted {
            if {[incr n] > $top_n} break
            set c "([lindex $reg 0],[lindex $reg 1])-([lindex $reg 2],[lindex $reg 3])"
            set rl [lindex $reg 5]; if {$rl eq ""} { set rl "-" }
            lappend out [format "  %-4d %-36s %10d %8s" $n $c [lindex $reg 4] $rl]
        }
        lappend out ""
    }

    if {$suggest} {
        lappend out "── Fix Suggestions ─────────────────────────────────────────"
        set wh [_worst_layer [array get h_ovfl]]
        set wv [_worst_layer [array get v_ovfl]]
        if {$wh ne ""} {
            lappend out "  Worst H layer: $wh ($h_ovfl($wh) overflows)"
            lappend out "    -> Add routing blockage on $wh in dense regions"
            lappend out "    -> Promote long H routes to higher metal layers"
        }
        if {$wv ne ""} {
            lappend out "  Worst V layer: $wv ($v_ovfl($wv) overflows)"
            lappend out "    -> Move macros to reduce V channel blockage"
            lappend out "    -> Change layer assignment for V-dominant nets"
        }
        if {[llength $regions] > 0} {
            lappend out "  Region fixes:"
            lappend out "    -> Add partial placement blockage in hotspot regions"
            lappend out "    -> Move nearby macros to open routing channels"
            lappend out "    -> Re-run placement with congestion effort: high"
        }
        lappend out ""
    }
    _cong_emit $out $outfile
}

proc _worst_layer {pairs} {
    set best ""; set best_v 0
    foreach {k v} $pairs { if {$v > $best_v} { set best_v $v; set best $k } }
    return $best
}

proc _cong_emit {lines outfile} {
    set rpt [join $lines "\n"]
    if {$outfile ne ""} {
        set fh [open $outfile "w"]; puts $fh $rpt; close $fh
        puts "Congestion analysis written to: $outfile"
    } else { puts $rpt }
}
