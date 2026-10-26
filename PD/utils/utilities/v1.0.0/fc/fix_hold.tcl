#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Batch Hold Buffer Insertion — Fusion Compiler (fc_shell)
# Standalone. Reads timing from FC session. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source fix_hold.tcl
#   fix_hold -slack_threshold 0 -buffer BUFFD1
#   fix_hold -slack_threshold -0.020 -buffer BUFFD2 -max_iter 5
#   fix_hold -auto -slack_threshold 0
#   fix_hold -slack_threshold 0 -buffer BUFFD1 -out fix_hold_report.rpt
#
# ARGUMENTS:
#   -slack_threshold <ns>  Fix endpoints with hold slack below this value (required)
#   -buffer <name>         Hold buffer cell name for insertion (required unless -auto)
#   -auto                  Auto-select smallest hold buffer from technology library
#   -max_iter <int>        Maximum fix iterations (default: 3)
#   -max_buffers <int>     Maximum total buffers to insert (default: 10000)
#   -skip_ports            Skip paths ending at output ports
#   -out <file>            Write report to file (default: stdout)
#
# EXAMPLES:
#   # Fix all hold violations with specific buffer
#   fix_hold -slack_threshold 0 -buffer BUFFD1
#
#   # Fix only severe violations, auto-select buffer
#   fix_hold -slack_threshold -0.050 -auto
#
#   # Conservative: limit iterations and buffer count
#   fix_hold -slack_threshold 0 -buffer BUFFD1 -max_iter 2 -max_buffers 500
#
#   # Write report without executing (dry run via -out)
#   fix_hold -slack_threshold 0 -buffer BUFFD1 -out hold_fix.rpt
#
# FC-SPECIFIC COMMANDS USED:
#   get_timing_paths -delay min -slack_lesser_than -max_paths
#   get_attribute [timing_path] slack endpoint startpoint
#   insert_buffer -new_cell_name
#   size_cell
#   report_timing -delay min
#   get_lib_cells
#   sizeof_collection
# ═══════════════════════════════════════════════════════════════════════════════

proc fix_hold {args} {
    set slack_threshold ""
    set buffer_name ""
    set auto_select 0
    set max_iter 3
    set max_buffers 10000
    set skip_ports 0
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -slack_threshold { incr i; set slack_threshold [lindex $args $i] }
            -buffer          { incr i; set buffer_name [lindex $args $i] }
            -auto            { set auto_select 1 }
            -max_iter        { incr i; set max_iter [lindex $args $i] }
            -max_buffers     { incr i; set max_buffers [lindex $args $i] }
            -skip_ports      { set skip_ports 1 }
            -out             { incr i; set outfile [lindex $args $i] }
            default          { error "Unknown option: [lindex $args $i]" }
        }
    }

    if {$slack_threshold eq ""} { error "-slack_threshold required" }
    if {$buffer_name eq "" && !$auto_select} { error "-buffer or -auto required" }

    # ── Auto-select hold buffer ───────────────────────────────────────
    if {$auto_select} {
        set buffer_name [_select_hold_buffer]
        if {$buffer_name eq ""} {
            error "Auto-select failed: no suitable buffer cell found in libraries"
        }
    }

    # Verify buffer exists — FC: get_lib_cells
    set lib_cell [get_lib_cells -quiet "*/$buffer_name"]
    if {$lib_cell eq "" || [sizeof_collection $lib_cell] == 0} {
        error "Buffer cell '$buffer_name' not found in any library"
    }

    set total_inserted 0
    set total_endpoints_fixed 0
    set report_lines [list]

    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  Hold Fix Report"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  Buffer cell        : $buffer_name"
    lappend report_lines "  Slack threshold    : $slack_threshold ns"
    lappend report_lines "  Max iterations     : $max_iter"
    lappend report_lines "  Max buffers        : $max_buffers"
    lappend report_lines "───────────────────────────────────────────────────────────────────"

    # ── Iterative fix loop ────────────────────────────────────────────
    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        # FC: get_timing_paths -delay min -slack_lesser_than
        set paths [get_timing_paths -delay min \
                       -slack_lesser_than $slack_threshold \
                       -max_paths 5000 \
                       -nworst 1]

        if {$paths eq "" || [sizeof_collection $paths] == 0} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No hold violations below $slack_threshold ns"
            break
        }

        set path_count [sizeof_collection $paths]
        set iter_inserted 0
        set iter_fixed 0
        set worst_slack 0.0

        lappend report_lines ""
        lappend report_lines "  Iteration $iter: $path_count failing path(s)"

        foreach_in_collection path $paths {
            if {$total_inserted >= $max_buffers} {
                lappend report_lines "  WARNING: Max buffer limit ($max_buffers) reached"
                break
            }

            set slack    [get_attribute $path slack]
            set endpoint [get_attribute $path endpoint]
            set startpt  [get_attribute $path startpoint]
            set ep_name  [get_attribute $endpoint full_name]
            set sp_name  [get_attribute $startpt full_name]

            # Track worst slack
            if {$slack < $worst_slack} { set worst_slack $slack }

            # Skip output port endpoints if requested
            if {$skip_ports} {
                set ep_obj_class [get_attribute $endpoint object_class]
                if {$ep_obj_class eq "port"} { continue }
            }

            # Insert buffer — FC: insert_buffer
            set buf_inst_name "HOLD_BUF_${iter}_${iter_inserted}"
            set insert_pin [get_attribute $endpoint full_name]

            if {$outfile eq ""} {
                # Execute directly
                set status [insert_buffer $insert_pin \
                               -new_cell_name $buf_inst_name \
                               -lib_cell [get_lib_cells "*/$buffer_name"]]
                if {$status ne ""} {
                    incr iter_inserted
                    incr total_inserted
                    incr iter_fixed
                }
            } else {
                # Dry run — just count
                incr iter_inserted
                incr total_inserted
                incr iter_fixed
            }
        }

        incr total_endpoints_fixed $iter_fixed
        lappend report_lines "    Buffers inserted : $iter_inserted"
        lappend report_lines "    Worst slack      : [format %.4f $worst_slack] ns"

        if {$total_inserted >= $max_buffers} { break }
    }

    # ── Final check ───────────────────────────────────────────────────
    if {$outfile eq ""} {
        set remaining [get_timing_paths -delay min \
                           -slack_lesser_than $slack_threshold \
                           -max_paths 1 -nworst 1]
        if {$remaining ne "" && [sizeof_collection $remaining] > 0} {
            set final_worst [get_attribute [index_collection $remaining 0] slack]
            lappend report_lines ""
            lappend report_lines "  Remaining worst hold slack: [format %.4f $final_worst] ns"
        } else {
            lappend report_lines ""
            lappend report_lines "  All hold violations resolved"
        }
    }

    # ── Summary ───────────────────────────────────────────────────────
    lappend report_lines ""
    lappend report_lines "───────────────────────────────────────────────────────────────────"
    lappend report_lines "  Total buffers inserted     : $total_inserted"
    lappend report_lines "  Total endpoints addressed  : $total_endpoints_fixed"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"

    set report_text [join $report_lines "\n"]

    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh $report_text
        close $fh
        puts "Hold fix report written to $outfile"
    } else {
        puts $report_text
    }

    return $total_inserted
}

# ── Auto-select smallest hold buffer from libraries ───────────────────────────
proc _select_hold_buffer {} {
    # Look for common buffer naming patterns — FC: get_lib_cells
    set candidates [list]
    foreach pattern {"*/BUFFD0*" "*/BUFFD1*" "*/BUFHD1*" "*/BUFH_*" "*/BUF_X1*" "*/BUFX1*"} {
        set cells [get_lib_cells -quiet $pattern]
        if {$cells ne "" && [sizeof_collection $cells] > 0} {
            foreach_in_collection c $cells {
                set cname [get_attribute $c base_name]
                set area  [get_attribute $c area]
                lappend candidates [list $cname $area]
            }
        }
    }

    if {[llength $candidates] == 0} { return "" }

    # Sort by area, pick smallest
    set sorted [lsort -real -index 1 $candidates]
    return [lindex [lindex $sorted 0] 0]
}
