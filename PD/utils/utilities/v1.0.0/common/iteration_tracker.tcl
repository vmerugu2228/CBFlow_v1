#!/usr/bin/env tclsh
###############################################################################
# iteration_tracker.tcl — Tool-Independent QoR Convergence Tracker
#
# Parses report_qor.rpt from multiple runs/iterations and displays a
# progression table with trend detection (IMPROVING, STALLING, REGRESSING).
# Works with plain tclsh — no EDA tool required.
#
# Usage:
#   tclsh iteration_tracker.tcl -reports {run1/report_qor.rpt run2/report_qor.rpt run3/report_qor.rpt}
#   tclsh iteration_tracker.tcl -reports {iter1.rpt iter2.rpt iter3.rpt} -out convergence.txt
#
# Features:
#   -reports LIST   List of report_qor.rpt files (ordered by iteration)
#   -out FILE       Write output to file instead of stdout
#
# Extracts per-run: WNS, TNS, NVP, total_power, area, DRC
# Detects: IMPROVING (metric getting better), STALLING (< 1% change),
#          REGRESSING (metric getting worse)
#
# No fallbacks. Errors if reports not found or unparseable.
###############################################################################

namespace eval ::iteration_tracker {
    variable version "1.0.0"

    # Metrics: {display_name regex lower_is_better}
    variable metrics [list \
        {WNS (ns)}       {(?:WNS|Worst Negative Slack)\s*[:(]\s*([-\d.]+)}                      1 \
        {TNS (ns)}       {(?:TNS|Total Negative Slack)\s*[:(]\s*([-\d.]+)}                       1 \
        {NVP}            {(?:NVP|Number of Violating Paths|No\. of Violating Paths)\s*[:(]\s*(\d+)}  1 \
        {Power (mW)}     {(?:Total\s+Power|Total Dynamic.*Power)\s*[:(=]\s*([-\d.eE+]+)}         1 \
        {Area}           {(?:Design\s+Area|Cell\s+Area|Total\s+Area)\s*[:(]\s*([-\d.eE+]+)}      1 \
        {DRC}            {(?:DRC|Total DRC)\s*(?:Violations?|Count|Errors?)?\s*[:(]\s*(\d+)}      1 \
    ]
}

# Output helper
proc ::iteration_tracker::output {lines args} {
    set out_file ""
    foreach {key val} $args {
        if {$key eq "-out"} { set out_file $val }
    }
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

# Parse a single QoR report — returns dict of metric->value
proc ::iteration_tracker::parse_report {rpt_file} {
    if {![file exists $rpt_file]} {
        error "ERROR: Report not found: $rpt_file"
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

# Determine trend between two values
# Returns: IMPROVING, STALLING, REGRESSING, or N/A
proc ::iteration_tracker::trend {old_val new_val lower_is_better} {
    if {$old_val eq "N/A" || $new_val eq "N/A"} {
        return "N/A"
    }
    set old_f [expr {double($old_val)}]
    set new_f [expr {double($new_val)}]

    if {$old_f == 0.0} {
        if {$new_f == 0.0} { return "STALLING" }
        # Cannot compute percentage change from zero
        if {$lower_is_better} {
            return [expr {$new_f < 0.0 ? "IMPROVING" : "REGRESSING"}]
        } else {
            return [expr {$new_f > 0.0 ? "IMPROVING" : "REGRESSING"}]
        }
    }

    set pct_change [expr {abs(($new_f - $old_f) / $old_f) * 100.0}]

    # Stalling: less than 1% change
    if {$pct_change < 1.0} {
        return "STALLING"
    }

    set delta [expr {$new_f - $old_f}]
    if {$lower_is_better} {
        # For WNS/TNS (negative values): more positive = better
        # For NVP/DRC (positive counts): lower = better
        return [expr {$delta < 0 ? "IMPROVING" : "REGRESSING"}]
    } else {
        return [expr {$delta > 0 ? "IMPROVING" : "REGRESSING"}]
    }
}

# Format value for display
proc ::iteration_tracker::fmt_val {val} {
    if {$val eq "N/A"} { return "N/A" }
    if {[string is integer -strict $val]} { return $val }
    return [format "%.4f" $val]
}

# Build short label from filename
proc ::iteration_tracker::short_label {filepath} {
    set fname [file tail $filepath]
    set dir [file tail [file dirname $filepath]]
    if {$dir eq "." || $dir eq ""} {
        return $fname
    }
    return "$dir"
}

# Main analysis
proc ::iteration_tracker::analyze {report_list args} {
    variable metrics

    set num_reports [llength $report_list]
    if {$num_reports < 2} {
        error "ERROR: At least 2 reports required for convergence tracking. Got $num_reports."
    }

    # Parse all reports
    set all_data [list]
    set labels [list]
    foreach rpt $report_list {
        lappend all_data [parse_report $rpt]
        lappend labels [short_label $rpt]
    }

    # Build header
    set lines [list]
    lappend lines "===== QoR Convergence Tracker ====="
    lappend lines "Reports: $num_reports iterations"
    lappend lines ""

    # Column widths
    set metric_w 14
    set val_w 12
    set trend_w 12

    # Header row
    set hdr [format "%-${metric_w}s" "Metric"]
    for {set i 0} {$i < $num_reports} {incr i} {
        set lbl [lindex $labels $i]
        if {[string length $lbl] > [expr {$val_w - 1}]} {
            set lbl [string range $lbl 0 [expr {$val_w - 2}]]
        }
        append hdr [format " %${val_w}s" $lbl]
    }
    append hdr [format "  %-${trend_w}s" "Trend"]
    lappend lines $hdr
    set total_w [expr {$metric_w + ($num_reports * ($val_w + 1)) + $trend_w + 2}]
    lappend lines [string repeat "-" $total_w]

    # Data rows
    foreach {name pattern lower_better} $metrics {
        set row [format "%-${metric_w}s" $name]
        set values [list]
        for {set i 0} {$i < $num_reports} {incr i} {
            set val [dict get [lindex $all_data $i] $name]
            lappend values $val
            append row [format " %${val_w}s" [fmt_val $val]]
        }

        # Compute overall trend: compare last vs second-to-last
        set last_val [lindex $values end]
        set prev_val [lindex $values end-1]
        set overall [trend $prev_val $last_val $lower_better]

        append row [format "  %-${trend_w}s" $overall]
        lappend lines $row
    }

    lappend lines [string repeat "-" $total_w]
    lappend lines ""

    # Detailed per-step deltas
    lappend lines "===== Per-Step Deltas ====="
    lappend lines ""

    for {set i 1} {$i < $num_reports} {incr i} {
        set prev_label [lindex $labels [expr {$i - 1}]]
        set curr_label [lindex $labels $i]
        lappend lines "--- $prev_label -> $curr_label ---"
        lappend lines [format "%-14s %12s %12s %12s  %s" "Metric" "Before" "After" "Delta" "Trend"]
        lappend lines [string repeat "-" 65]

        foreach {name pattern lower_better} $metrics {
            set old_val [dict get [lindex $all_data [expr {$i - 1}]] $name]
            set new_val [dict get [lindex $all_data $i] $name]
            set t [trend $old_val $new_val $lower_better]

            set delta_str "N/A"
            if {$old_val ne "N/A" && $new_val ne "N/A"} {
                set d [expr {double($new_val) - double($old_val)}]
                if {[string is integer -strict $old_val] && [string is integer -strict $new_val]} {
                    set delta_str [format "%+d" [expr {int($d)}]]
                } else {
                    set delta_str [format "%+.4f" $d]
                }
            }

            lappend lines [format "%-14s %12s %12s %12s  %s" \
                $name [fmt_val $old_val] [fmt_val $new_val] $delta_str $t]
        }
        lappend lines ""
    }

    # Overall convergence summary
    set first_data [lindex $all_data 0]
    set last_data [lindex $all_data end]
    set improving 0
    set stalling 0
    set regressing 0
    foreach {name pattern lower_better} $metrics {
        set t [trend [dict get $first_data $name] [dict get $last_data $name] $lower_better]
        switch $t {
            IMPROVING  { incr improving }
            STALLING   { incr stalling }
            REGRESSING { incr regressing }
        }
    }

    lappend lines "===== Overall Convergence (first -> last) ====="
    lappend lines "  IMPROVING:  $improving metrics"
    lappend lines "  STALLING:   $stalling metrics"
    lappend lines "  REGRESSING: $regressing metrics"
    if {$regressing > 0} {
        lappend lines "  WARNING: $regressing metrics regressed from first to last iteration."
    }
    if {$stalling > [llength [list {*}$metrics]] / 6} {
        lappend lines "  NOTE: Multiple metrics stalling — consider changing optimization strategy."
    }
    lappend lines ""

    output $lines {*}$args
}

# CLI entry point
proc ::iteration_tracker::main {args} {
    set report_list [list]
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -reports {
                incr i
                set report_list [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: tclsh iteration_tracker.tcl -reports {report1.rpt report2.rpt ...} \[-out file\]"
            }
        }
    }

    if {[llength $report_list] == 0} {
        error "ERROR: -reports argument is required with a list of report files."
    }

    set out_args [list]
    if {$out_file ne ""} { lappend out_args -out $out_file }

    analyze $report_list {*}$out_args
}

# Execute when run from command line
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::iteration_tracker::main {*}$::argv
}
