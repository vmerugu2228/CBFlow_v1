#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Power Grid Checker — Fusion Compiler (fc_shell)
# Standalone. Parses report_power / IR drop data. No CBflow dependency.
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source power_grid_check.tcl
#   check_power -rpt <file> [-ir <file>] [-ir_threshold <mV>] [-budget <mW>]
#               [-suggest] [-out <file>]
#   check_power -live [-ir_threshold <mV>] [-budget <mW>] [-suggest] [-out <file>]
#
# ARGUMENTS:
#   -rpt <file>          Path to report_power output (report mode)
#   -ir <file>           Path to IR drop report (optional)
#   -live                Run report_power inside FC (FC mode)
#   -ir_threshold <mV>   Warn if IR drop exceeds this (default: 20 mV)
#   -budget <mW>         Flag domains exceeding this total power budget
#   -suggest             Print fix suggestions for power/IR issues
#   -out <file>          Write report to file instead of stdout
#
# EXAMPLES:
#   check_power -rpt power.rpt -ir ir_drop.rpt -ir_threshold 15 -suggest
#   check_power -rpt power.rpt -budget 500 -suggest -out pg_summary.rpt
#   check_power -live -ir_threshold 10 -suggest
#
# FC-SPECIFIC COMMANDS USED (live mode only):
#   redirect -variable v { report_power -nosplit }
# ═══════════════════════════════════════════════════════════════════════════════

proc check_power {args} {
    set rpt ""; set irf ""; set live 0; set ir_thr 20.0
    set budget ""; set suggest 0; set outfile ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -rpt          { incr i; set rpt [lindex $args $i] }
            -ir           { incr i; set irf [lindex $args $i] }
            -live         { set live 1 }
            -ir_threshold { incr i; set ir_thr [lindex $args $i] }
            -budget       { incr i; set budget [lindex $args $i] }
            -suggest      { set suggest 1 }
            -out          { incr i; set outfile [lindex $args $i] }
            default       { error "Unknown option: [lindex $args $i]" }
        }
    }
    if {$rpt eq "" && !$live} { error "Either -rpt <file> or -live required" }
    if {$rpt ne "" && $live}  { error "Cannot use both -rpt and -live" }

    if {$live} {
        if {[catch {redirect -variable pc { report_power -nosplit }} err]} { error "report_power failed: $err" }
    } else {
        if {![file exists $rpt]} { error "Not found: $rpt" }
        set fh [open $rpt r]; set pc [read $fh]; close $fh
    }

    # ── Parse power breakdown + domains + PG coverage ─────────────────
    set tp ""; set lk ""; set dy ""; set ck ""
    array set dom {}; array set pgc {}
    foreach line [split $pc "\n"] {
        set t [string trim $line]
        if {[regexp -nocase {Total\s+Power\s*[=:]\s*([\d\.eE\+\-]+)\s*(\S*)} $t -> v u]}   { set tp [_pw $v $u] }
        if {[regexp -nocase {Leakage\s+Power\s*[=:]\s*([\d\.eE\+\-]+)\s*(\S*)} $t -> v u]} { set lk [_pw $v $u] }
        if {[regexp -nocase {Dynamic\s+Power\s*[=:]\s*([\d\.eE\+\-]+)\s*(\S*)} $t -> v u]}  { set dy [_pw $v $u] }
        if {[regexp -nocase {Clock\s+(Network\s+)?Power\s*[=:]\s*([\d\.eE\+\-]+)\s*(\S*)} $t -> _ v u]} { set ck [_pw $v $u] }
        if {[regexp -nocase {Power\s+Domain\s*[=:]\s*(\S+)} $t -> d]} { set _cd $d }
        if {[info exists _cd] && [regexp -nocase {Total\s*[=:]\s*([\d\.eE\+\-]+)\s*(\S*)} $t -> v u]} {
            set dom($_cd) [_pw $v $u]; unset _cd
        }
        if {[regexp -nocase {(M\d+|METAL\d+)\s+[\d\.]+\s+[\d\.]+\s+([\d\.]+)\s*%} $t -> ly pct]} { set pgc($ly) $pct }
    }
    if {$tp eq ""} { error "Could not parse total power — check report format" }

    # ── Parse IR drop ─────────────────────────────────────────────────
    set ird [list]; set irviol 0
    if {$irf ne ""} {
        if {![file exists $irf]} { error "IR file not found: $irf" }
        set fh [open $irf r]; set ic [read $fh]; close $fh
        foreach line [split $ic "\n"] {
            set t [string trim $line]
            if {[regexp {(\S+)\s+(\S*)\s*([\d\.eE\+\-]+)\s*m?V?\s+.*?([\d\.]+)\s*[,\s]\s*([\d\.]+)} $t -> n l d x y]} {
                set mv [_ir $d $t]; lappend ird [list $n $l $mv $x $y]
                if {$mv > $ir_thr} { incr irviol }
            } elseif {[regexp -nocase {worst\s+(ir|drop)\s*[=:]\s*([\d\.eE\+\-]+)} $t -> _ v] && [llength $ird]==0} {
                set mv [_ir $v $t]; lappend ird [list VDD - $mv 0 0]
                if {$mv > $ir_thr} { incr irviol }
            }
        }
    }

    # ── Build output ──────────────────────────────────────────────────
    set o [list]
    lappend o "═══════════════════════════════════════════════════════════════"
    lappend o " POWER GRID CHECK — [expr {$rpt ne {} ? $rpt : {live FC}}]"
    lappend o "═══════════════════════════════════════════════════════════════"
    lappend o ""
    lappend o "── Power Breakdown (mW) ────────────────────────────────────"
    foreach {lbl val} [list Total $tp Dynamic $dy Leakage $lk "Clock Net" $ck] {
        if {$val ne ""} { lappend o [format "  %-16s %12.4f" $lbl $val] }
    }
    if {$budget ne ""} {
        set m [expr {$budget - $tp}]; set s [expr {$m >= 0 ? "PASS" : "FAIL"}]
        lappend o [format "  Budget: %.2f | Margin: %.2f (%s)" $budget $m $s]
    }
    lappend o ""
    if {[array size dom] > 0} {
        lappend o "── Power by Domain ─────────────────────────────────────────"
        foreach d [lsort [array names dom]] {
            set st [expr {$budget ne "" && $dom($d) > $budget ? "OVER" : "OK"}]
            lappend o [format "  %-26s %10.4f mW  %s" $d $dom($d) $st]
        }
        lappend o ""
    }
    if {[array size pgc] > 0} {
        lappend o "── PG Strap Coverage ───────────────────────────────────────"
        foreach ly [lsort [array names pgc]] {
            lappend o [format "  %-10s %7s%%%s" $ly $pgc($ly) [expr {$pgc($ly)<5.0 ? " LOW" : ""}]]
        }
        lappend o ""
    }
    if {[llength $ird] > 0} {
        lappend o "── IR Drop (threshold: ${ir_thr} mV) ──────────────────────"
        foreach e [lsort -real -decreasing -index 2 $ird] {
            set f [expr {[lindex $e 2] > $ir_thr ? " FAIL" : ""}]
            lappend o [format "  %-12s %-6s %8.3f mV (%s,%s)%s" {*}$e $f]
        }
        lappend o [expr {$irviol > 0 ? "  WARNING: $irviol violation(s) exceed ${ir_thr} mV" : "  IR drop PASS"}]
        lappend o ""
    }
    if {$suggest} {
        lappend o "── Suggestions ─────────────────────────────────────────────"
        if {$budget ne "" && $tp > $budget} { lappend o "  BUDGET: increase clock gating, HVT swap, add power domains" }
        if {$ck ne "" && $tp > 0 && [expr {100.0*$ck/$tp}] > 40} { lappend o "  CLOCK: resize buffers, add ICG, reduce CTS stages" }
        if {$irviol > 0}   { lappend o "  IR DROP: add straps, widen straps, add via arrays at intersections" }
        foreach ly [lsort [array names pgc]] {
            if {$pgc($ly) < 5.0} { lappend o "  PG $ly: add straps, check via stack continuity" }
        }
        if {$lk ne "" && $tp > 0 && [expr {100.0*$lk/$tp}] > 30} { lappend o "  LEAKAGE: increase HVT ratio, add power shut-off" }
        lappend o ""
    }
    set r [join $o "\n"]
    if {$outfile ne ""} { set fh [open $outfile w]; puts $fh $r; close $fh; puts "Written: $outfile"
    } else { puts $r }
}

proc _pw {val unit} {
    set v [expr {double($val)}]
    switch -glob [string tolower $unit] {
        "uw" - "u*w*" { expr {$v/1e3} } "nw" - "n*w*" { expr {$v/1e6} }
        "w" - "watt*" { expr {$v*1e3} } default { return $v }
    }
}
proc _ir {val ctx} {
    set v [expr {double($val)}]
    if {[regexp -nocase {mV} $ctx]} { return $v }
    if {$v < 1.0 && [regexp -nocase {V} $ctx]} { return [expr {$v*1e3}] }
    return $v
}
