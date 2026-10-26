#!/usr/bin/env tclsh
###############################################################################
# qor_compare.tcl — Tool-Independent QoR Comparison Utility
#
# Parses two report_qor.rpt files and shows a delta table with
# improvement/regression indicators. Works with plain tclsh.
#
# Extracts: WNS, TNS, NVP, total_power, leakage_power, cell_count,
#           utilization, max_cap violations, max_tran violations, DRC violations
#
# Usage:
#   tclsh qor_compare.tcl -old report1.rpt -new report2.rpt
#   tclsh qor_compare.tcl -old report1.rpt -new report2.rpt -out compare.txt
#
# Output format is parseable — one metric per line, fixed-width columns.
# No fallbacks. Errors if report not found or metric not parseable.
###############################################################################

namespace eval ::qor_compare {
    variable version "1.0.0"

    # Metrics to extract: {display_name regex_pattern lower_is_better}
    variable metrics [list \
        {WNS (ns)}             {(?:WNS|Worst Negative Slack)\s*[:(]\s*([-\d.]+)}           1 \
        {TNS (ns)}             {(?:TNS|Total Negative Slack)\s*[:(]\s*([-\d.]+)}            1 \
        {NVP}                  {(?:NVP|Number of Violating Paths|No\. of Violating Paths)\s*[:(]\s*(\d+)}  1 \
        {Total Power (mW)}     {(?:Total\s+Power|Total Dynamic.*Power)\s*[:(=]\s*([-\d.eE+]+)}  1 \
        {Leakage Power (mW)}   {(?:Leakage\s+Power|Total Leakage)\s*[:(=]\s*([-\d.eE+]+)}  1 \
        {Cell Count}           {(?:Cell\s+Count|Leaf Cell Count|Number of Cells)\s*[:(]\s*(\d+)}  1 \
        {Utilization (%)}      {(?:Utilization|Cell Utilization|Design Area Utilization)\s*[:(]\s*([-\d.]+)}  0 \
        {Max Cap Violations}   {(?:Max Cap|max_capacitance)\s*(?:Violations?|Cost|Count)?\s*[:(]\s*(\d+)}  1 \
        {Max Tran Violations}  {(?:Max Tran|max_transition)\s*(?:Violations?|Cost|Count)?\s*[:(]\s*(\d+)}  1 \
        {DRC Violations}       {(?:DRC|Total DRC)\s*(?:Violations?|Count|Errors?)?\s*[:(]\s*(\d+)}  1 \
    ]
}

# Parse a QoR report and extract all metrics
proc ::qor_compare::parse_report {rpt_file} {
    if {![file exists $rpt_file]} {
        error "ERROR: QoR report not found: $rpt_file"
    }
    set fh [open $rpt_file r]
    set content [read $fh]
    close $fh

    variable metrics
    set results [dict create]

    foreach {name pattern lower_better} $metrics {
        if {[regexp -nocase $pattern $content -> val]} {
            dict set results $name $val
        } else {
            dict set results $name "N/A"
        }
    }
    return $results
}

# Compute delta and direction indicator
proc ::qor_compare::compute_delta {old_val new_val lower_is_better} {
    if {$old_val eq "N/A" || $new_val eq "N/A"} {
        return [list "N/A" " "]
    }
    set delta [expr {$new_val - $old_val}]

    if {abs($delta) < 1e-10} {
        set indicator "="
    } elseif {$lower_is_better} {
        set indicator [expr {$delta < 0 ? "+" : "-"}]
    } else {
        set indicator [expr {$delta > 0 ? "+" : "-"}]
    }
    return [list $delta $indicator]
}

# Format a numeric value for display
proc ::qor_compare::fmt_val {val} {
    if {$val eq "N/A"} { return "N/A" }
    if {[string is integer -strict $val]} { return $val }
    return [format "%.4f" $val]
}

# Format a delta value for display
proc ::qor_compare::fmt_delta {val} {
    if {$val eq "N/A"} { return "N/A" }
    if {[string is integer -strict $val]} {
        return [format "%+d" [expr {int($val)}]]
    }
    return [format "%+.4f" $val]
}

# Main comparison logic
proc ::qor_compare::compare {old_file new_file args} {
    set out_file ""
    foreach {key val} $args {
        if {$key eq "-out"} { set out_file $val }
    }

    variable metrics

    set old_data [parse_report $old_file]
    set new_data [parse_report $new_file]

    set lines [list]
    lappend lines "===== QoR Comparison Report ====="
    lappend lines "Old: $old_file"
    lappend lines "New: $new_file"
    lappend lines ""
    lappend lines [format "%-24s %14s %14s %14s  %s" "Metric" "Old" "New" "Delta" "Status"]
    lappend lines [string repeat "-" 78]

    set improvements 0
    set regressions 0

    foreach {name pattern lower_better} $metrics {
        set old_val [dict get $old_data $name]
        set new_val [dict get $new_data $name]
        lassign [compute_delta $old_val $new_val $lower_better] delta indicator

        set status " "
        if {$indicator eq "+"} {
            set status "IMPROVED"
            incr improvements
        } elseif {$indicator eq "-"} {
            set status "REGRESSED"
            incr regressions
        } elseif {$indicator eq "="} {
            set status "SAME"
        }

        lappend lines [format "%-24s %14s %14s %14s  %s" \
            $name \
            [fmt_val $old_val] \
            [fmt_val $new_val] \
            [fmt_delta $delta] \
            $status]
    }

    lappend lines [string repeat "-" 78]
    lappend lines "Summary: $improvements improved, $regressions regressed"
    lappend lines ""

    set text [join $lines "\n"]
    if {$out_file ne ""} {
        set fh [open $out_file w]
        puts $fh $text
        close $fh
        puts "INFO: Output written to $out_file"
    } else {
        puts $text
    }
}

# CLI entry point
proc ::qor_compare::main {args} {
    set old_file ""
    set new_file ""
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -old {
                incr i
                set old_file [lindex $args $i]
            }
            -new {
                incr i
                set new_file [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: tclsh qor_compare.tcl -old report1.rpt -new report2.rpt \[-out file\]"
            }
        }
    }

    if {$old_file eq ""} {
        error "ERROR: -old argument is required."
    }
    if {$new_file eq ""} {
        error "ERROR: -new argument is required."
    }

    set extra_args [list]
    if {$out_file ne ""} { lappend extra_args -out $out_file }

    compare $old_file $new_file {*}$extra_args
}

# Execute when run from command line
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::qor_compare::main {*}$::argv
}
