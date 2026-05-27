#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# DRC Violation Analyzer — Fusion Compiler (fc_shell)
# Standalone. Parses signoff_check_drc.rpt. No CBflow dependency.
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source drc_analyzer.tcl
#   analyze_drc -rpt <file> [-top <N>] [-suggest] [-out <file>]
#
# ARGUMENTS:
#   -rpt <file>        Path to signoff_check_drc.rpt (required)
#   -top <N>           Top violation types to show (default: 10)
#   -suggest           Print fix action for each violation type
#   -out <file>        Write report to file instead of stdout
#
# EXAMPLES:
#   analyze_drc -rpt signoff_check_drc.rpt
#   analyze_drc -rpt signoff_check_drc.rpt -top 20 -suggest
#   analyze_drc -rpt signoff_check_drc.rpt -suggest -out drc_summary.rpt
#
# GROUPING: rule name, layer, violation type (spacing/width/area/via/antenna)
# WORKS AS: tclsh report parser or sourced inside fc_shell
# ═══════════════════════════════════════════════════════════════════════════════

proc analyze_drc {args} {
    set rpt_file ""; set top_n 10; set suggest 0; set outfile ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -rpt     { incr i; set rpt_file [lindex $args $i] }
            -top     { incr i; set top_n [lindex $args $i] }
            -suggest { set suggest 1 }
            -out     { incr i; set outfile [lindex $args $i] }
            default  { error "Unknown option: [lindex $args $i]" }
        }
    }
    if {$rpt_file eq ""} { error "-rpt <file> required" }
    if {![file exists $rpt_file]} { error "Report file not found: $rpt_file" }

    set fh [open $rpt_file "r"]; set lines [split [read $fh] "\n"]; close $fh
    if {[llength $lines] == 0} { error "Report file is empty: $rpt_file" }

    # ── Parse violations ──────────────────────────────────────────────
    array set by_rule {}; array set by_layer {}; array set by_type {}
    set current_rule ""; set current_layer ""; set total 0

    foreach line $lines {
        set t [string trim $line]
        if {[regexp -nocase {^Rule\s*:\s*(\S+)} $t -> r]} { set current_rule $r; continue }
        if {[regexp -nocase {Violation\s+Rule\s*:\s*(\S+)} $t -> r]} { set current_rule $r; continue }
        if {[regexp -nocase {^Layer\s*:\s*(\S+)} $t -> l]} { set current_layer $l; continue }
        if {[regexp -nocase {on\s+layer\s+(\S+)} $t -> l]} { set current_layer $l }
        if {[regexp -nocase {Violation\s+#?\d+} $t] ||
            [regexp {\(\s*[\d\.\-]+\s*,\s*[\d\.\-]+\s*\)} $t]} {
            incr total
            set vtype [_classify_drc $current_rule $t]
            if {$current_rule ne ""} { _incr by_rule $current_rule }
            if {$current_layer ne ""} { _incr by_layer $current_layer }
            if {$vtype ne ""} { _incr by_type $vtype }
        }
    }
    if {$total == 0} { error "No violations parsed from $rpt_file — check report format" }

    # ── Build output ──────────────────────────────────────────────────
    set out [list]
    lappend out "═══════════════════════════════════════════════════════════════"
    lappend out " DRC VIOLATION ANALYSIS — Total: $total"
    lappend out " Source: $rpt_file"
    lappend out "═══════════════════════════════════════════════════════════════"
    lappend out ""

    lappend out "── Top $top_n Violation Rules ──────────────────────────────────"
    lappend out [format "  %-40s %8s" "Rule" "Count"]
    set n 0
    foreach {name val} [_sort_desc [array get by_rule]] {
        if {[incr n] > $top_n} break
        lappend out [format "  %-40s %8d" $name $val]
    }
    lappend out ""

    lappend out "── Violations by Layer ─────────────────────────────────────"
    lappend out [format "  %-20s %8s" "Layer" "Count"]
    foreach {name val} [_sort_desc [array get by_layer]] {
        lappend out [format "  %-20s %8d" $name $val]
    }
    lappend out ""

    lappend out "── Violations by Type ──────────────────────────────────────"
    lappend out [format "  %-20s %8s" "Type" "Count"]
    foreach {name val} [_sort_desc [array get by_type]] {
        lappend out [format "  %-20s %8d" $name $val]
    }
    lappend out ""

    if {$suggest} {
        lappend out "── Fix Suggestions ─────────────────────────────────────────"
        foreach {vtype cnt} [_sort_desc [array get by_type]] {
            lappend out [format "  %-12s (%d) -> %s" $vtype $cnt [_drc_fix $vtype]]
        }
        lappend out ""
    }

    _emit $out $outfile "DRC analysis"
    return $total
}

# ── Classify violation type ───────────────────────────────────────────────
proc _classify_drc {rule line} {
    set r [string tolower $rule]; set l [string tolower $line]
    if {[regexp {spac|sep|dist|gap|enclos} $r$l]} { return "spacing" }
    if {[regexp {wid|min.*w} $r$l]}               { return "width" }
    if {[regexp {antenna|ant} $r$l]}               { return "antenna" }
    if {[regexp {area|density} $r$l]}              { return "area" }
    if {[regexp {via|cut|contact} $r$l]}           { return "via" }
    if {$rule ne ""} { return "other" }
    return ""
}

# ── Fix suggestions ──────────────────────────────────────────────────────
proc _drc_fix {vtype} {
    switch -- $vtype {
        "spacing" { return "Widen track or layer hop — increase routing grid, use NDR, add spacing blockage" }
        "width"   { return "Size up cell or add buffer — check min-width rules, upsize drivers" }
        "antenna" { return "Insert diode or break net — add antenna diodes at gate pins, split long wires" }
        "area"    { return "Increase fill density — run metal fill, check min-area on short stubs" }
        "via"     { return "Add redundant via — enable via optimization, check enclosure and cut spacing" }
        default   { return "Review rule definition — inspect DRC runset for context" }
    }
}

# ── Helpers ───────────────────────────────────────────────────────────────
proc _incr {arr_name key} {
    upvar 1 $arr_name arr
    if {![info exists arr($key)]} { set arr($key) 0 }
    incr arr($key)
}

proc _sort_desc {pairs} {
    set items [list]
    foreach {k v} $pairs { lappend items [list $k $v] }
    set result [list]
    foreach item [lsort -integer -decreasing -index 1 $items] {
        lappend result [lindex $item 0] [lindex $item 1]
    }
    return $result
}

proc _emit {lines outfile label} {
    set report [join $lines "\n"]
    if {$outfile ne ""} {
        set fh [open $outfile "w"]; puts $fh $report; close $fh
        puts "$label written to: $outfile"
    } else { puts $report }
}
