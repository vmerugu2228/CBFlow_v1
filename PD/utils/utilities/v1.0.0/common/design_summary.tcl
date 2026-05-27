#!/usr/bin/env tclsh
###############################################################################
# design_summary.tcl — Tool-Independent Single-Page Design Scorecard
#
# Scans a run directory for standard report files and produces a compact
# stage-by-stage metric table. Works with plain tclsh — just reads files.
#
# Scanned reports:
#   report_qor.rpt, report_timing.max.rpt, report_timing.min.rpt,
#   report_power.rpt, report_congestion.rpt, report_clock_qor.rpt,
#   check_routes.rpt, signoff_check_drc.rpt
#
# Usage:
#   tclsh design_summary.tcl -run-dir /path/to/P0_run_SYNTH_PNR_test1
#   tclsh design_summary.tcl -run-dir /path/to/run -out summary.txt
#
# Features:
#   -run-dir DIR    Run directory to scan (required)
#   -out FILE       Write output to file instead of stdout
#
# Output: one compact table with columns per stage, rows per metric.
# No fallbacks. Errors if run directory not found.
###############################################################################

namespace eval ::design_summary {
    variable version "1.0.0"

    # Ordered stage names to search for in work/<FLOW>/
    variable stage_order [list \
        init_design synthesis place cts route pro signoff \
        compile compile1 compile2 place_opt clock_opt \
        route_auto route_opt chip_finish \
    ]

    # Report files to look for in each stage directory
    variable report_files [list \
        report_qor.rpt \
        report_timing.max.rpt \
        report_timing.min.rpt \
        report_power.rpt \
        report_congestion.rpt \
        report_clock_qor.rpt \
        check_routes.rpt \
        signoff_check_drc.rpt \
    ]

    # Metrics to extract: {display_name source_file regex}
    variable metrics [list \
        {WNS (ns)}       report_qor.rpt       {(?:WNS|Worst Negative Slack)\s*[:(]\s*([-\d.]+)} \
        {TNS (ns)}       report_qor.rpt       {(?:TNS|Total Negative Slack)\s*[:(]\s*([-\d.]+)} \
        {NVP}            report_qor.rpt       {(?:NVP|Number of Violating Paths|No\. of Violating Paths)\s*[:(]\s*(\d+)} \
        {Power (mW)}     report_power.rpt     {(?:Total\s+Power|Total Dynamic.*Power)\s*[:(=]\s*([-\d.eE+]+)} \
        {Area}           report_qor.rpt       {(?:Design\s+Area|Cell\s+Area|Total\s+Area)\s*[:(]\s*([-\d.eE+]+)} \
        {DRC}            signoff_check_drc.rpt {(?:DRC|Total DRC|Total)\s*(?:Violations?|Count|Errors?)?\s*[:(]\s*(\d+)} \
        {Clock Skew}     report_clock_qor.rpt  {(?:Global\s+)?Skew\s*[:(]\s*([-\d.]+)} \
        {Congestion}     report_congestion.rpt {(?:Overflow|Total Overflow|Max Overflow)\s*[:(]\s*([-\d.]+)} \
    ]
}

# Output helper
proc ::design_summary::output {lines args} {
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

# Find all stage directories in a run directory
# Searches work/<FLOW>/<stage>N/ for report directories
proc ::design_summary::discover_stages {run_dir} {
    variable stage_order

    set work_dir [file join $run_dir "work"]
    if {![file isdirectory $work_dir]} {
        error "ERROR: work/ directory not found in $run_dir"
    }

    # Find flow subdirectory
    set flow_dirs [glob -nocomplain -directory $work_dir -type d *]
    if {[llength $flow_dirs] == 0} {
        error "ERROR: No flow directories found in $work_dir"
    }

    set found_stages [dict create]

    foreach flow_dir $flow_dirs {
        set flow_name [file tail $flow_dir]
        set node_dirs [glob -nocomplain -directory $flow_dir -type d *]

        foreach node_dir $node_dirs {
            set node_name [file tail $node_dir]
            # Strip trailing digits to get base stage name
            set base_name [regsub {\d+$} $node_name ""]

            # Check if this stage has a reports directory
            set rpt_dir [file join $node_dir "reports"]
            set run_rpt_dir [file join $node_dir "run"]

            set actual_dir ""
            if {[file isdirectory $rpt_dir]} {
                set actual_dir $rpt_dir
            } elseif {[file isdirectory $run_rpt_dir]} {
                set actual_dir $run_rpt_dir
            } else {
                # Reports may be directly in the node directory
                set actual_dir $node_dir
            }

            # Determine display order
            set order_idx [lsearch -exact $stage_order $base_name]
            if {$order_idx == -1} {
                # Try the full node name
                set order_idx [lsearch -exact $stage_order $node_name]
            }
            if {$order_idx == -1} {
                set order_idx 99
            }

            dict set found_stages $node_name [list dir $actual_dir order $order_idx flow $flow_name]
        }
    }

    if {[dict size $found_stages] == 0} {
        error "ERROR: No stage directories found in $work_dir"
    }

    # Sort by order
    set sorted [list]
    dict for {name info} $found_stages {
        lappend sorted [list $name [dict get $info dir] [dict get $info order]]
    }
    set sorted [lsort -integer -index 2 $sorted]

    return $sorted
}

# Extract a metric from a report file
proc ::design_summary::extract_metric {rpt_dir source_file pattern} {
    set rpt_path [file join $rpt_dir $source_file]
    if {![file exists $rpt_path]} {
        return "---"
    }
    set fh [open $rpt_path r]
    set content [read $fh]
    close $fh

    if {[regexp -nocase $pattern $content -> val]} {
        return $val
    }
    return "---"
}

# Format a metric value for compact display
proc ::design_summary::fmt_val {val} {
    if {$val eq "---" || $val eq "N/A"} { return $val }
    if {[string is integer -strict $val]} { return $val }
    if {[catch {set f [format "%.3f" $val]}]} { return $val }
    return $f
}

# Main analysis
proc ::design_summary::generate {run_dir args} {
    variable metrics

    if {![file isdirectory $run_dir]} {
        error "ERROR: Run directory not found: $run_dir"
    }

    # Discover stages
    set stages [discover_stages $run_dir]
    set num_stages [llength $stages]

    # Collect stage names and directories
    set stage_names [list]
    set stage_dirs [list]
    foreach entry $stages {
        lassign $entry name dir order
        lappend stage_names $name
        lappend stage_dirs $dir
    }

    # Limit to 8 stages for readability — take first and last stages
    if {$num_stages > 8} {
        set keep_names [list]
        set keep_dirs [list]
        for {set i 0} {$i < 4} {incr i} {
            lappend keep_names [lindex $stage_names $i]
            lappend keep_dirs [lindex $stage_dirs $i]
        }
        for {set i [expr {$num_stages - 4}]} {$i < $num_stages} {incr i} {
            lappend keep_names [lindex $stage_names $i]
            lappend keep_dirs [lindex $stage_dirs $i]
        }
        set stage_names $keep_names
        set stage_dirs $keep_dirs
        set num_stages [llength $stage_names]
    }

    # Extract all metrics for all stages
    set data [dict create]
    foreach {name source pattern} $metrics {
        set row [list]
        for {set i 0} {$i < $num_stages} {incr i} {
            set val [extract_metric [lindex $stage_dirs $i] $source $pattern]
            lappend row $val
        }
        dict set data $name $row
    }

    # Build output table
    set lines [list]
    lappend lines "===== Design Scorecard ====="
    lappend lines "Run: $run_dir"
    lappend lines ""

    # Column widths
    set metric_w 14
    set col_w 12

    # Header
    set hdr [format "%-${metric_w}s" "Metric"]
    foreach sn $stage_names {
        set label $sn
        if {[string length $label] > [expr {$col_w - 1}]} {
            set label [string range $label 0 [expr {$col_w - 2}]]
        }
        append hdr [format " %${col_w}s" $label]
    }
    lappend lines $hdr
    set total_w [expr {$metric_w + ($num_stages * ($col_w + 1))}]
    lappend lines [string repeat "-" $total_w]

    # Data rows
    foreach {name source pattern} $metrics {
        set row_data [dict get $data $name]
        set row [format "%-${metric_w}s" $name]
        foreach val $row_data {
            append row [format " %${col_w}s" [fmt_val $val]]
        }
        lappend lines $row
    }

    lappend lines [string repeat "-" $total_w]
    lappend lines ""

    # Stage-over-stage delta summary (WNS progression)
    lappend lines "===== WNS Progression ====="
    set wns_row [dict get $data "WNS (ns)"]
    set prev_wns ""
    set wns_lines [list]
    for {set i 0} {$i < $num_stages} {incr i} {
        set sn [lindex $stage_names $i]
        set wns [lindex $wns_row $i]
        set delta_str "---"
        if {$prev_wns ne "" && $wns ne "---" && $prev_wns ne "---"} {
            set delta [expr {double($wns) - double($prev_wns)}]
            if {$delta > 0} {
                set delta_str [format "+%.3f (IMPROVED)" $delta]
            } elseif {$delta < 0} {
                set delta_str [format "%.3f (REGRESSED)" $delta]
            } else {
                set delta_str "0.000 (SAME)"
            }
        }
        lappend wns_lines [format "  %-15s  WNS: %8s  Delta: %s" $sn [fmt_val $wns] $delta_str]
        if {$wns ne "---"} { set prev_wns $wns }
    }
    foreach l $wns_lines { lappend lines $l }
    lappend lines ""

    # Report file inventory
    lappend lines "===== Report File Inventory ====="
    variable report_files
    for {set i 0} {$i < $num_stages} {incr i} {
        set sn [lindex $stage_names $i]
        set sdir [lindex $stage_dirs $i]
        set found_count 0
        set missing [list]
        foreach rf $report_files {
            if {[file exists [file join $sdir $rf]]} {
                incr found_count
            } else {
                lappend missing $rf
            }
        }
        set total [llength $report_files]
        set status "OK"
        if {$found_count == 0} {
            set status "NO REPORTS"
        } elseif {$found_count < $total} {
            set status "PARTIAL ($found_count/$total)"
        }
        lappend lines [format "  %-15s  %s" $sn $status]
    }
    lappend lines ""

    output $lines {*}$args
}

# CLI entry point
proc ::design_summary::main {args} {
    set run_dir ""
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -run-dir {
                incr i
                set run_dir [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: tclsh design_summary.tcl -run-dir /path/to/run \[-out file\]"
            }
        }
    }

    if {$run_dir eq ""} {
        error "ERROR: -run-dir argument is required."
    }

    set out_args [list]
    if {$out_file ne ""} { lappend out_args -out $out_file }

    generate $run_dir {*}$out_args
}

# Execute when run from command line
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::design_summary::main {*}$::argv
}
