#!/usr/bin/env tclsh
###############################################################################
# timing_debug.tcl — FC Timing Debug Utility
#
# Parses timing reports and provides analysis for debug.
# Works in two modes:
#   1. Inside FC (Fusion Compiler): uses get_timing_paths for live analysis
#   2. Report mode: parses a timing report file
#
# Usage (report mode — plain tclsh):
#   tclsh timing_debug.tcl -report report_timing.max.rpt -histogram
#   tclsh timing_debug.tcl -report report_timing.min.rpt -top 20
#   tclsh timing_debug.tcl -report report_timing.max.rpt -groups
#   tclsh timing_debug.tcl -report report_timing.max.rpt -endpoints
#   tclsh timing_debug.tcl -report report_timing.max.rpt -histogram -out results.txt
#
# Usage (inside FC):
#   source timing_debug.tcl
#   timing_debug -histogram
#   timing_debug -top 10
#   timing_debug -groups
#   timing_debug -endpoints
#   timing_debug -endpoints -out failing_eps.txt
#
# Features:
#   -histogram   Slack histogram — bucket endpoints into ranges
#   -top N       Show top N bottleneck cells (most frequent in failing paths)
#   -groups      Per path group WNS/TNS summary
#   -endpoints   List all failing endpoints sorted by slack
#   -out FILE    Write output to file instead of stdout
#
# No fallbacks. Errors if report not found or data missing.
###############################################################################

namespace eval ::timing_debug {
    variable version "1.0.0"
}

# Detect whether we are running inside FC
proc ::timing_debug::in_fc {} {
    return [expr {[info commands "get_timing_paths"] ne ""}]
}

# Output helper — write to file or stdout
proc ::timing_debug::output {lines args} {
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

# Parse a timing report file. Returns list of path dicts.
# Each dict: endpoint slack startpoint group cells
proc ::timing_debug::parse_report {rpt_file} {
    if {![file exists $rpt_file]} {
        error "ERROR: Timing report not found: $rpt_file"
    }
    set fh [open $rpt_file r]
    set content [read $fh]
    close $fh

    set paths [list]
    set current_endpoint ""
    set current_startpoint ""
    set current_slack ""
    set current_group ""
    set current_cells [list]
    set in_path 0

    foreach line [split $content "\n"] {
        set trimmed [string trim $line]

        # Detect path group
        if {[regexp {^Path Group:\s+(\S+)} $trimmed -> grp]} {
            set current_group $grp
            continue
        }

        # Detect startpoint
        if {[regexp {^Startpoint:\s+(\S+)} $trimmed -> sp]} {
            set current_startpoint $sp
            set in_path 1
            set current_cells [list]
            continue
        }

        # Detect endpoint
        if {[regexp {^Endpoint:\s+(\S+)} $trimmed -> ep]} {
            set current_endpoint $ep
            continue
        }

        # Detect slack line (various formats)
        if {[regexp {^\s*slack\s*\(?(\w*)\)?\s+([-\d.]+)} $trimmed -> _type slk]} {
            set current_slack $slk
            # Path complete — save it
            if {$current_endpoint ne ""} {
                lappend paths [list \
                    endpoint $current_endpoint \
                    startpoint $current_startpoint \
                    slack $current_slack \
                    group $current_group \
                    cells $current_cells]
            }
            set current_endpoint ""
            set current_startpoint ""
            set current_slack ""
            set current_cells [list]
            set in_path 0
            continue
        }

        # Collect cell instances from data path lines
        # Typical format: U123/A (cell_name) or instance/pin
        if {$in_path && [regexp {^\s*(\S+/\S+)\s+} $trimmed -> pin]} {
            set cell [lindex [split $pin "/"] 0]
            if {$cell ne "" && $cell ne "clock" && $cell ne "data"} {
                lappend current_cells $cell
            }
        }
    }

    if {[llength $paths] == 0} {
        error "ERROR: No timing paths found in $rpt_file. Verify report format."
    }
    return $paths
}

# Get paths from FC live session
proc ::timing_debug::get_fc_paths {} {
    if {![::timing_debug::in_fc]} {
        error "ERROR: Not running inside FC. Use -report flag for report mode."
    }
    set paths [list]
    set tp_collection [get_timing_paths -max_paths 5000 -slack_lesser_than 0.0]
    foreach_in_collection tp $tp_collection {
        set ep [get_attribute $tp endpoint]
        set sp [get_attribute $tp startpoint]
        set slk [get_attribute $tp slack]
        set grp [get_attribute $tp path_group]
        set cell_list [list]
        set point_collection [get_attribute $tp timing_points]
        foreach_in_collection pt $point_collection {
            set obj [get_attribute $pt object]
            if {[get_attribute $obj object_class] eq "cell"} {
                lappend cell_list [get_attribute $obj full_name]
            }
        }
        lappend paths [list \
            endpoint $ep startpoint $sp slack $slk group $grp cells $cell_list]
    }
    if {[llength $paths] == 0} {
        error "ERROR: No failing timing paths found in current design."
    }
    return $paths
}

# Helper to access path dict fields
proc ::timing_debug::pget {path key} {
    foreach {k v} $path {
        if {$k eq $key} { return $v }
    }
    return ""
}

# -histogram: Slack distribution in buckets
proc ::timing_debug::histogram {paths args} {
    set buckets [dict create]
    set ranges [list "<-2.0" "-2.0:-1.0" "-1.0:-0.5" "-0.5:-0.2" "-0.2:-0.1" "-0.1:-0.05" "-0.05:0.0" "0.0:0.05" "0.05:0.1" ">0.1"]
    foreach r $ranges { dict set buckets $r 0 }

    foreach p $paths {
        set slk [pget $p slack]
        if {$slk < -2.0} {
            dict incr buckets "<-2.0"
        } elseif {$slk < -1.0} {
            dict incr buckets "-2.0:-1.0"
        } elseif {$slk < -0.5} {
            dict incr buckets "-1.0:-0.5"
        } elseif {$slk < -0.2} {
            dict incr buckets "-0.5:-0.2"
        } elseif {$slk < -0.1} {
            dict incr buckets "-0.2:-0.1"
        } elseif {$slk < -0.05} {
            dict incr buckets "-0.1:-0.05"
        } elseif {$slk < 0.0} {
            dict incr buckets "-0.05:0.0"
        } elseif {$slk < 0.05} {
            dict incr buckets "0.0:0.05"
        } elseif {$slk < 0.1} {
            dict incr buckets "0.05:0.1"
        } else {
            dict incr buckets ">0.1"
        }
    }

    set lines [list]
    lappend lines "===== Slack Histogram ====="
    lappend lines [format "%-16s %8s  %s" "Range (ns)" "Count" "Bar"]
    lappend lines [string repeat "-" 60]
    foreach r $ranges {
        set cnt [dict get $buckets $r]
        set bar [string repeat "#" [expr {min($cnt, 60)}]]
        lappend lines [format "%-16s %8d  %s" $r $cnt $bar]
    }
    lappend lines ""
    lappend lines "Total paths: [llength $paths]"
    output $lines {*}$args
}

# -top N: Most frequent cells in failing paths
proc ::timing_debug::top_cells {paths n args} {
    set cell_count [dict create]
    foreach p $paths {
        set slk [pget $p slack]
        if {$slk >= 0.0} continue
        foreach c [pget $p cells] {
            if {[dict exists $cell_count $c]} {
                dict incr cell_count $c
            } else {
                dict set cell_count $c 1
            }
        }
    }

    # Sort by count descending
    set sorted [list]
    dict for {cell cnt} $cell_count {
        lappend sorted [list $cell $cnt]
    }
    set sorted [lsort -integer -decreasing -index 1 $sorted]

    set lines [list]
    lappend lines "===== Top $n Bottleneck Cells ====="
    lappend lines [format "%-6s  %-50s  %s" "Rank" "Cell Instance" "Failing Paths"]
    lappend lines [string repeat "-" 72]
    set rank 0
    foreach entry $sorted {
        incr rank
        if {$rank > $n} break
        lassign $entry cell cnt
        lappend lines [format "%-6d  %-50s  %d" $rank $cell $cnt]
    }
    lappend lines ""
    lappend lines "Total unique cells in failing paths: [dict size $cell_count]"
    output $lines {*}$args
}

# -groups: Per path group WNS/TNS summary
proc ::timing_debug::groups {paths args} {
    set group_data [dict create]
    foreach p $paths {
        set grp [pget $p group]
        set slk [pget $p slack]
        if {$grp eq ""} { set grp "default" }
        if {![dict exists $group_data $grp]} {
            dict set group_data $grp wns 0.0
            dict set group_data $grp tns 0.0
            dict set group_data $grp nvp 0
            dict set group_data $grp total 0
        }
        dict with group_data $grp {
            incr total
            if {$slk < $wns} { set wns $slk }
            if {$slk < 0.0} {
                set tns [expr {$tns + $slk}]
                incr nvp
            }
        }
    }

    set lines [list]
    lappend lines "===== Path Group Summary ====="
    lappend lines [format "%-25s %10s %12s %8s %8s" "Path Group" "WNS (ns)" "TNS (ns)" "NVP" "Total"]
    lappend lines [string repeat "-" 68]
    dict for {grp data} $group_data {
        set wns [dict get $data wns]
        set tns [dict get $data tns]
        set nvp [dict get $data nvp]
        set total [dict get $data total]
        lappend lines [format "%-25s %10.4f %12.4f %8d %8d" $grp $wns $tns $nvp $total]
    }
    output $lines {*}$args
}

# -endpoints: All failing endpoints sorted by slack
proc ::timing_debug::endpoints {paths args} {
    set failing [list]
    foreach p $paths {
        set slk [pget $p slack]
        if {$slk < 0.0} {
            lappend failing [list [pget $p endpoint] $slk [pget $p startpoint] [pget $p group]]
        }
    }
    set failing [lsort -real -index 1 $failing]

    set lines [list]
    lappend lines "===== Failing Endpoints (sorted by slack) ====="
    lappend lines [format "%-50s %10s  %-40s  %s" "Endpoint" "Slack" "Startpoint" "Group"]
    lappend lines [string repeat "-" 120]
    foreach entry $failing {
        lassign $entry ep slk sp grp
        lappend lines [format "%-50s %10.4f  %-40s  %s" $ep $slk $sp $grp]
    }
    lappend lines ""
    lappend lines "Total failing endpoints: [llength $failing]"
    output $lines {*}$args
}

# Main dispatcher — called as proc inside FC or from CLI
proc ::timing_debug::run {args} {
    set report_file ""
    set do_histogram 0
    set do_top 0
    set top_n 10
    set do_groups 0
    set do_endpoints 0
    set out_file ""

    # Parse arguments
    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -report {
                incr i
                set report_file [lindex $args $i]
            }
            -histogram { set do_histogram 1 }
            -top {
                set do_top 1
                incr i
                set top_n [lindex $args $i]
                if {![string is integer -strict $top_n] || $top_n <= 0} {
                    error "ERROR: -top requires a positive integer argument."
                }
            }
            -groups { set do_groups 1 }
            -endpoints { set do_endpoints 1 }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: timing_debug \[-report file\] \[-histogram\] \[-top N\] \[-groups\] \[-endpoints\] \[-out file\]"
            }
        }
    }

    if {!$do_histogram && !$do_top && !$do_groups && !$do_endpoints} {
        error "ERROR: Specify at least one analysis: -histogram, -top N, -groups, or -endpoints"
    }

    # Build output args
    set out_args [list]
    if {$out_file ne ""} { lappend out_args -out $out_file }

    # Get paths
    if {$report_file ne ""} {
        set paths [::timing_debug::parse_report $report_file]
    } else {
        set paths [::timing_debug::get_fc_paths]
    }

    if {$do_histogram} { ::timing_debug::histogram $paths {*}$out_args }
    if {$do_top}       { ::timing_debug::top_cells $paths $top_n {*}$out_args }
    if {$do_groups}    { ::timing_debug::groups $paths {*}$out_args }
    if {$do_endpoints} { ::timing_debug::endpoints $paths {*}$out_args }
}

# FC convenience wrapper
proc timing_debug {args} {
    ::timing_debug::run {*}$args
}

# CLI entry point — execute when run with tclsh
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::timing_debug::run {*}$::argv
}
