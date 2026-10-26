#!/usr/bin/env tclsh
###############################################################################
# eco_helper.tcl — FC ECO Impact Estimator & Tracker
#
# Estimates timing/power delta for cell swaps, tracks ECO iterations,
# shows history, and suggests fixes for failing endpoints.
# Requires a live FC session for all operations.
#
# Usage (inside FC):
#   source eco_helper.tcl
#   eco_helper -estimate {U_core/U_alu/U_add inst_ADDF_X1 ADDF_X2}
#   eco_helper -track
#   eco_helper -history
#   eco_helper -suggest -endpoint reg_out_0/D
#   eco_helper -estimate {U1 BUF_X2 BUF_X4} -out eco_result.txt
#
# Features:
#   -estimate {cell old_ref new_ref}   Estimate timing/power delta for a swap
#   -track                             Snapshot current ECO state to eco_history.log
#   -history                           Display ECO pass history from log
#   -suggest -endpoint <name>          Suggest cell sizing/VT swap fixes
#   -out FILE                          Write output to file instead of stdout
#
# Writes eco_history.log in current directory for -track/-history.
# No fallbacks. Errors if not in FC or required data missing.
###############################################################################

namespace eval ::eco_helper {
    variable version "1.0.0"
    variable history_file "eco_history.log"
}

# Detect FC session
proc ::eco_helper::in_fc {} {
    return [expr {[info commands "get_cells"] ne ""}]
}

# Require FC — error immediately if not in tool
proc ::eco_helper::require_fc {} {
    if {![::eco_helper::in_fc]} {
        error "ERROR: eco_helper requires a live FC session. Cannot run in plain tclsh."
    }
}

# Output helper
proc ::eco_helper::output {lines args} {
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

# -estimate: Estimate timing/power delta for a cell swap
proc ::eco_helper::estimate {cell_name old_ref new_ref args} {
    require_fc

    set cell_obj [get_cells -quiet $cell_name]
    if {[sizeof_collection $cell_obj] == 0} {
        error "ERROR: Cell not found: $cell_name"
    }

    set current_ref [get_attribute $cell_obj ref_name]
    if {$current_ref ne $old_ref} {
        error "ERROR: Cell $cell_name has ref $current_ref, expected $old_ref"
    }

    # Capture pre-swap metrics
    set pre_area [get_attribute $cell_obj area]
    set pre_leak [get_attribute $cell_obj leakage_power]

    # Get timing through this cell before swap
    set pre_paths [get_timing_paths -through $cell_obj -max_paths 10 -slack_lesser_than 999]
    set pre_wns 999.0
    set pre_tns 0.0
    set pre_count 0
    foreach_in_collection tp $pre_paths {
        set slk [get_attribute $tp slack]
        if {$slk < $pre_wns} { set pre_wns $slk }
        if {$slk < 0.0} { set pre_tns [expr {$pre_tns + $slk}] }
        incr pre_count
    }

    # Perform swap
    size_cell $cell_name $new_ref

    # Capture post-swap metrics
    set post_area [get_attribute $cell_obj area]
    set post_leak [get_attribute $cell_obj leakage_power]
    set post_paths [get_timing_paths -through $cell_obj -max_paths 10 -slack_lesser_than 999]
    set post_wns 999.0
    set post_tns 0.0
    foreach_in_collection tp $post_paths {
        set slk [get_attribute $tp slack]
        if {$slk < $post_wns} { set post_wns $slk }
        if {$slk < 0.0} { set post_tns [expr {$post_tns + $slk}] }
    }

    # Revert swap — restore original
    size_cell $cell_name $old_ref

    # Compute deltas
    set delta_wns [format "%.4f" [expr {$post_wns - $pre_wns}]]
    set delta_tns [format "%.4f" [expr {$post_tns - $pre_tns}]]
    set delta_area [format "%.2f" [expr {$post_area - $pre_area}]]
    set delta_leak [format "%.6f" [expr {$post_leak - $pre_leak}]]

    set lines [list]
    lappend lines "===== ECO Estimate: $cell_name ($old_ref -> $new_ref) ====="
    lappend lines ""
    lappend lines [format "%-24s %14s %14s %14s" "Metric" "Before" "After" "Delta"]
    lappend lines [string repeat "-" 70]
    lappend lines [format "%-24s %14.4f %14.4f %14s" "WNS (ns)" $pre_wns $post_wns $delta_wns]
    lappend lines [format "%-24s %14.4f %14.4f %14s" "TNS (ns)" $pre_tns $post_tns $delta_tns]
    lappend lines [format "%-24s %14.2f %14.2f %14s" "Area" $pre_area $post_area $delta_area]
    lappend lines [format "%-24s %14.6f %14.6f %14s" "Leakage Power" $pre_leak $post_leak $delta_leak]
    lappend lines ""
    lappend lines "Paths analyzed through cell: $pre_count"
    lappend lines "Note: Swap was reverted. Use size_cell to apply permanently."
    output $lines {*}$args
}

# -track: Snapshot current WNS/TNS and cell counts to eco_history.log
proc ::eco_helper::track {args} {
    require_fc
    variable history_file

    # Get current QoR
    set all_paths [get_timing_paths -max_paths 50000 -slack_lesser_than 0.0]
    set wns 0.0
    set tns 0.0
    set nvp 0
    set cells_touched [list]
    foreach_in_collection tp $all_paths {
        set slk [get_attribute $tp slack]
        if {$slk < $wns} { set wns $slk }
        set tns [expr {$tns + $slk}]
        incr nvp
    }

    # Count all ECO-modified cells (changed_cells attribute if available)
    set eco_cells 0
    set modified [get_cells -quiet -filter "is_eco_cell == true"]
    if {[sizeof_collection $modified] > 0} {
        set eco_cells [sizeof_collection $modified]
    }

    # Determine pass number from existing log
    set pass 1
    if {[file exists $history_file]} {
        set fh [open $history_file r]
        set existing [read $fh]
        close $fh
        set pass_count 0
        foreach l [split $existing "\n"] {
            if {[regexp {^PASS\s+(\d+)} $l -> p]} {
                if {$p >= $pass_count} { set pass_count $p }
            }
        }
        set pass [expr {$pass_count + 1}]
    }

    # Append to log
    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set fh [open $history_file a]
    puts $fh "PASS $pass | $timestamp | WNS: [format %.4f $wns] | TNS: [format %.4f $tns] | NVP: $nvp | ECO_CELLS: $eco_cells"
    close $fh

    set lines [list]
    lappend lines "INFO: ECO pass $pass recorded to $history_file"
    lappend lines "  WNS: [format %.4f $wns] ns | TNS: [format %.4f $tns] ns | NVP: $nvp | ECO cells: $eco_cells"
    output $lines {*}$args
}

# -history: Display ECO pass history from log
proc ::eco_helper::history {args} {
    variable history_file

    if {![file exists $history_file]} {
        error "ERROR: No ECO history found. Run 'eco_helper -track' first to create $history_file."
    }

    set fh [open $history_file r]
    set content [read $fh]
    close $fh

    set entries [list]
    foreach line [split $content "\n"] {
        set trimmed [string trim $line]
        if {$trimmed eq ""} continue
        if {[regexp {^PASS\s+(\d+)\s*\|\s*(\S+ \S+)\s*\|\s*WNS:\s*([-\d.]+)\s*\|\s*TNS:\s*([-\d.]+)\s*\|\s*NVP:\s*(\d+)\s*\|\s*ECO_CELLS:\s*(\d+)} \
                $trimmed -> pass ts wns tns nvp eco]} {
            lappend entries [list $pass $ts $wns $tns $nvp $eco]
        }
    }

    if {[llength $entries] == 0} {
        error "ERROR: No valid ECO passes found in $history_file."
    }

    set lines [list]
    lappend lines "===== ECO Pass History ====="
    lappend lines [format "%-6s  %-20s  %10s  %12s  %6s  %10s  %s" \
        "Pass" "Timestamp" "WNS (ns)" "TNS (ns)" "NVP" "ECO Cells" "WNS Delta"]
    lappend lines [string repeat "-" 90]

    set prev_wns ""
    foreach entry $entries {
        lassign $entry pass ts wns tns nvp eco
        set delta_str "---"
        if {$prev_wns ne ""} {
            set delta [expr {$wns - $prev_wns}]
            if {$delta > 0} {
                set delta_str [format "+%.4f (IMPROVED)" $delta]
            } elseif {$delta < 0} {
                set delta_str [format "%.4f (REGRESSED)" $delta]
            } else {
                set delta_str "0.0000 (SAME)"
            }
        }
        lappend lines [format "%-6s  %-20s  %10s  %12s  %6s  %10s  %s" \
            $pass $ts $wns $tns $nvp $eco $delta_str]
        set prev_wns $wns
    }
    lappend lines ""
    output $lines {*}$args
}

# -suggest: Suggest cell sizing/VT swap fixes for a failing endpoint
proc ::eco_helper::suggest {endpoint_name args} {
    require_fc

    set paths [get_timing_paths -to $endpoint_name -max_paths 1 -slack_lesser_than 0.0]
    if {[sizeof_collection $paths] == 0} {
        error "ERROR: No failing paths found to endpoint: $endpoint_name"
    }

    set tp [index_collection $paths 0]
    set slack [get_attribute $tp slack]
    set needed [expr {abs($slack)}]

    # Collect cells on the critical path
    set point_collection [get_attribute $tp timing_points]
    set path_cells [list]
    foreach_in_collection pt $point_collection {
        set obj [get_attribute $pt object]
        if {[get_attribute $obj object_class] eq "cell"} {
            set cell_name [get_attribute $obj full_name]
            set ref [get_attribute $obj ref_name]
            set cell_delay [get_attribute $pt delay]
            set is_clock [get_attribute $obj is_clock_network_cell]
            if {!$is_clock} {
                lappend path_cells [list $cell_name $ref $cell_delay]
            }
        }
    }

    if {[llength $path_cells] == 0} {
        error "ERROR: No data-path cells found on path to $endpoint_name."
    }

    # Sort by delay descending — biggest contributors first
    set path_cells [lsort -decreasing -real -index 2 $path_cells]

    set lines [list]
    lappend lines "===== ECO Suggestions for: $endpoint_name ====="
    lappend lines "Slack: [format %.4f $slack] ns | Gap to close: [format %.4f $needed] ns"
    lappend lines ""
    lappend lines "--- Cells on critical path (sorted by delay) ---"
    lappend lines [format "%-6s  %-40s  %-20s  %10s  %s" "Rank" "Cell" "Ref" "Delay (ns)" "Suggestion"]
    lappend lines [string repeat "-" 100]

    set rank 0
    foreach entry $path_cells {
        incr rank
        if {$rank > 15} break
        lassign $entry cname cref cdelay

        # Generate suggestion based on ref name patterns
        set suggestion ""
        if {[regexp {_X(\d+)$} $cref -> sz]} {
            set next_sz [expr {$sz * 2}]
            set upsized [regsub {_X\d+$} $cref "_X${next_sz}"]
            set suggestion "Upsize -> $upsized"
        }
        if {[regexp {(?:SVT|RVT|HVT)} $cref]} {
            if {[regexp {HVT} $cref]} {
                set vt_swap [regsub {HVT} $cref "SVT"]
                set suggestion "$suggestion | VT swap -> $vt_swap"
            } elseif {[regexp {SVT} $cref]} {
                set vt_swap [regsub {SVT} $cref "LVT"]
                set suggestion "$suggestion | VT swap -> $vt_swap"
            } elseif {[regexp {RVT} $cref]} {
                set vt_swap [regsub {RVT} $cref "LVT"]
                set suggestion "$suggestion | VT swap -> $vt_swap"
            }
        }
        if {$suggestion eq ""} {
            set suggestion "Manual review (no standard naming pattern)"
        }
        set suggestion [string trim $suggestion " |"]

        lappend lines [format "%-6d  %-40s  %-20s  %10.4f  %s" \
            $rank $cname $cref $cdelay $suggestion]
    }

    lappend lines ""
    lappend lines "Total data-path cells: [llength $path_cells]"
    lappend lines "Note: Suggestions are heuristic. Validate with -estimate before applying."
    output $lines {*}$args
}

# Main dispatcher
proc ::eco_helper::run {args} {
    set do_estimate 0
    set estimate_spec [list]
    set do_track 0
    set do_history 0
    set do_suggest 0
    set suggest_ep ""
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -estimate {
                set do_estimate 1
                incr i
                set estimate_spec [lindex $args $i]
                if {[llength $estimate_spec] != 3} {
                    error "ERROR: -estimate requires {cell_name old_ref new_ref}"
                }
            }
            -track {
                set do_track 1
            }
            -history {
                set do_history 1
            }
            -suggest {
                set do_suggest 1
            }
            -endpoint {
                incr i
                set suggest_ep [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: eco_helper \[-estimate {cell old new}\] \[-track\] \[-history\] \[-suggest -endpoint name\] \[-out file\]"
            }
        }
    }

    if {!$do_estimate && !$do_track && !$do_history && !$do_suggest} {
        error "ERROR: Specify at least one action: -estimate, -track, -history, or -suggest"
    }

    if {$do_suggest && $suggest_ep eq ""} {
        error "ERROR: -suggest requires -endpoint <name>"
    }

    set out_args [list]
    if {$out_file ne ""} { lappend out_args -out $out_file }

    if {$do_estimate} {
        lassign $estimate_spec cell_name old_ref new_ref
        ::eco_helper::estimate $cell_name $old_ref $new_ref {*}$out_args
    }
    if {$do_track}   { ::eco_helper::track {*}$out_args }
    if {$do_history} { ::eco_helper::history {*}$out_args }
    if {$do_suggest} { ::eco_helper::suggest $suggest_ep {*}$out_args }
}

# FC convenience wrapper
proc eco_helper {args} {
    ::eco_helper::run {*}$args
}

# CLI entry point (limited — only -history works without FC)
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::eco_helper::run {*}$::argv
}
