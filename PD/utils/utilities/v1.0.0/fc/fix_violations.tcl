#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Batch Max Transition / Max Capacitance / Max Fanout Fixer — Fusion Compiler
# Standalone. Reads design from FC session. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source fix_violations.tcl
#   fix_violations -type max_tran -buffer BUFFD2
#   fix_violations -type max_cap -auto
#   fix_violations -type max_fanout -buffer BUFFD4 -max_fanout_limit 32
#   fix_violations -type max_tran -buffer BUFFD2 -out violations_report.rpt
#
# ARGUMENTS:
#   -type <type>           Violation type: max_tran | max_cap | max_fanout (required)
#   -buffer <name>         Buffer cell for insertion (required unless -auto)
#   -auto                  Auto-select buffer from technology library
#   -max_iter <int>        Maximum fix iterations (default: 3)
#   -max_cells <int>       Maximum cells to insert (default: 5000)
#   -max_fanout_limit <n>  Target max fanout after fix (default: 32, for -type max_fanout)
#   -out <file>            Write report to file (default: stdout)
#
# VIOLATION TYPES:
#   max_tran   — Find nets with transition violations, insert buffers to split
#   max_cap    — Find nets with capacitance violations, insert repeaters
#   max_fanout — Find high-fanout nets, clone drivers or add buffer trees
#
# EXAMPLES:
#   # Fix transition violations
#   fix_violations -type max_tran -buffer BUFFD2
#
#   # Fix cap violations with auto buffer selection
#   fix_violations -type max_cap -auto
#
#   # Fix fanout with explicit limit
#   fix_violations -type max_fanout -buffer BUFFD4 -max_fanout_limit 24
#
#   # Dry-run report
#   fix_violations -type max_tran -buffer BUFFD2 -out drc_fix.rpt
#
# FC-SPECIFIC COMMANDS USED:
#   get_nets -filter
#   get_pins -of_objects -filter
#   get_attribute (max_transition, max_capacitance, actual_transition, total_capacitance)
#   insert_buffer -new_cell_name -lib_cell
#   size_cell
#   sizeof_collection
#   get_lib_cells
# ═══════════════════════════════════════════════════════════════════════════════

proc fix_violations {args} {
    set viol_type ""
    set buffer_name ""
    set auto_select 0
    set max_iter 3
    set max_cells 5000
    set max_fanout_limit 32
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -type             { incr i; set viol_type [lindex $args $i] }
            -buffer           { incr i; set buffer_name [lindex $args $i] }
            -auto             { set auto_select 1 }
            -max_iter         { incr i; set max_iter [lindex $args $i] }
            -max_cells        { incr i; set max_cells [lindex $args $i] }
            -max_fanout_limit { incr i; set max_fanout_limit [lindex $args $i] }
            -out              { incr i; set outfile [lindex $args $i] }
            default           { error "Unknown option: [lindex $args $i]" }
        }
    }

    if {$viol_type eq ""} { error "-type required (max_tran | max_cap | max_fanout)" }
    if {$viol_type ni {max_tran max_cap max_fanout}} {
        error "Invalid -type '$viol_type' — must be: max_tran | max_cap | max_fanout"
    }
    if {$buffer_name eq "" && !$auto_select} { error "-buffer or -auto required" }

    # ── Auto-select buffer ────────────────────────────────────────────
    if {$auto_select} {
        set buffer_name [_select_driver_buffer $viol_type]
        if {$buffer_name eq ""} {
            error "Auto-select failed: no suitable buffer cell found"
        }
    }

    # Verify buffer exists — FC: get_lib_cells
    set lib_cell [get_lib_cells -quiet "*/$buffer_name"]
    if {$lib_cell eq "" || [sizeof_collection $lib_cell] == 0} {
        error "Buffer cell '$buffer_name' not found in any library"
    }

    set report_lines [list]
    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  DRC Violation Fix Report"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  Violation type     : $viol_type"
    lappend report_lines "  Buffer cell        : $buffer_name"
    lappend report_lines "  Max iterations     : $max_iter"
    lappend report_lines "  Max cells          : $max_cells"
    if {$viol_type eq "max_fanout"} {
        lappend report_lines "  Target max fanout  : $max_fanout_limit"
    }
    lappend report_lines "───────────────────────────────────────────────────────────────────"

    set total_fixed 0
    set total_cells_added 0

    # ── Dispatch to violation-specific handler ────────────────────────
    switch -- $viol_type {
        "max_tran" {
            set result [_fix_max_tran $buffer_name $max_iter $max_cells $outfile report_lines]
        }
        "max_cap" {
            set result [_fix_max_cap $buffer_name $max_iter $max_cells $outfile report_lines]
        }
        "max_fanout" {
            set result [_fix_max_fanout $buffer_name $max_iter $max_cells $max_fanout_limit $outfile report_lines]
        }
    }

    set total_fixed [lindex $result 0]
    set total_cells_added [lindex $result 1]

    # ── Summary ───────────────────────────────────────────────────────
    lappend report_lines ""
    lappend report_lines "───────────────────────────────────────────────────────────────────"
    lappend report_lines "  Total violations fixed  : $total_fixed"
    lappend report_lines "  Total cells added       : $total_cells_added"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"

    set report_text [join $report_lines "\n"]

    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh $report_text
        close $fh
        puts "DRC fix report written to $outfile"
    } else {
        puts $report_text
    }

    return $total_cells_added
}

# ── Max transition fixer ──────────────────────────────────────────────────────
proc _fix_max_tran {buffer_name max_iter max_cells outfile report_var} {
    upvar 1 $report_var report_lines
    set total_fixed 0
    set total_added 0

    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        # FC: get_nets — find nets where actual transition > max_transition
        set violating_pins [get_pins -quiet -filter "actual_rise_transition > max_rise_transition || actual_fall_transition > max_fall_transition"]

        if {$violating_pins eq "" || [sizeof_collection $violating_pins] == 0} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No max_tran violations remaining"
            break
        }

        # Collect unique driving nets
        set processed_nets [list]
        set iter_fixed 0
        set iter_added 0

        foreach_in_collection pin $violating_pins {
            if {$total_added >= $max_cells} {
                lappend report_lines "  WARNING: Max cell limit ($max_cells) reached"
                break
            }

            set net_name [get_attribute [get_nets -quiet -of_objects $pin] full_name]
            if {$net_name eq ""} { continue }
            if {[lsearch -exact $processed_nets $net_name] >= 0} { continue }
            lappend processed_nets $net_name

            set pin_name [get_attribute $pin full_name]
            set actual_tran [get_attribute $pin actual_rise_transition]
            set max_tran [get_attribute $pin max_rise_transition]

            if {$outfile eq ""} {
                set buf_name "FIX_TRAN_BUF_${iter}_${iter_added}"
                set status [insert_buffer $pin_name \
                               -new_cell_name $buf_name \
                               -lib_cell [get_lib_cells "*/$buffer_name"]]
                if {$status ne ""} {
                    incr iter_added
                    incr total_added
                    incr iter_fixed
                }
            } else {
                incr iter_added
                incr total_added
                incr iter_fixed
            }
        }

        incr total_fixed $iter_fixed
        lappend report_lines ""
        lappend report_lines "  Iteration $iter: Fixed $iter_fixed nets, inserted $iter_added buffers"
        if {$total_added >= $max_cells} { break }
    }

    return [list $total_fixed $total_added]
}

# ── Max capacitance fixer ─────────────────────────────────────────────────────
proc _fix_max_cap {buffer_name max_iter max_cells outfile report_var} {
    upvar 1 $report_var report_lines
    set total_fixed 0
    set total_added 0

    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        # FC: find pins with capacitance violations
        set violating_pins [get_pins -quiet -filter "max_capacitance > 0 && total_capacitance > max_capacitance"]

        if {$violating_pins eq "" || [sizeof_collection $violating_pins] == 0} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No max_cap violations remaining"
            break
        }

        set processed_nets [list]
        set iter_fixed 0
        set iter_added 0

        foreach_in_collection pin $violating_pins {
            if {$total_added >= $max_cells} {
                lappend report_lines "  WARNING: Max cell limit ($max_cells) reached"
                break
            }

            set net [get_nets -quiet -of_objects $pin]
            if {$net eq "" || [sizeof_collection $net] == 0} { continue }
            set net_name [get_attribute $net full_name]
            if {[lsearch -exact $processed_nets $net_name] >= 0} { continue }
            lappend processed_nets $net_name

            set total_cap [get_attribute $pin total_capacitance]
            set max_cap   [get_attribute $pin max_capacitance]
            set pin_name  [get_attribute $pin full_name]

            # Estimate how many repeaters needed
            set num_bufs [expr {int(ceil($total_cap / $max_cap))}]
            if {$num_bufs < 1} { set num_bufs 1 }

            # Get load pins on the net for splitting
            set load_pins [get_pins -quiet -of_objects $net -filter "direction == in"]
            if {$load_pins eq "" || [sizeof_collection $load_pins] == 0} { continue }

            set load_count [sizeof_collection $load_pins]
            set loads_per_buf [expr {int(ceil(double($load_count) / ($num_bufs + 1)))}]
            if {$loads_per_buf < 1} { set loads_per_buf 1 }

            # Insert buffer at driving pin to split cap
            if {$outfile eq ""} {
                set buf_name "FIX_CAP_BUF_${iter}_${iter_added}"
                set status [insert_buffer $pin_name \
                               -new_cell_name $buf_name \
                               -lib_cell [get_lib_cells "*/$buffer_name"]]
                if {$status ne ""} {
                    incr iter_added
                    incr total_added
                    incr iter_fixed
                }
            } else {
                incr iter_added
                incr total_added
                incr iter_fixed
            }
        }

        incr total_fixed $iter_fixed
        lappend report_lines ""
        lappend report_lines "  Iteration $iter: Fixed $iter_fixed nets, inserted $iter_added repeaters"
        if {$total_added >= $max_cells} { break }
    }

    return [list $total_fixed $total_added]
}

# ── Max fanout fixer ──────────────────────────────────────────────────────────
proc _fix_max_fanout {buffer_name max_iter max_cells max_fanout_limit outfile report_var} {
    upvar 1 $report_var report_lines
    set total_fixed 0
    set total_added 0

    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        # FC: find output pins where fanout exceeds limit
        set driving_pins [get_pins -quiet -filter "direction == out && max_fanout > 0"]

        if {$driving_pins eq "" || [sizeof_collection $driving_pins] == 0} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No driving pins found"
            break
        }

        set iter_fixed 0
        set iter_added 0
        set found_violations 0

        foreach_in_collection dpin $driving_pins {
            if {$total_added >= $max_cells} {
                lappend report_lines "  WARNING: Max cell limit ($max_cells) reached"
                break
            }

            set net [get_nets -quiet -of_objects $dpin]
            if {$net eq "" || [sizeof_collection $net] == 0} { continue }

            set load_pins [get_pins -quiet -of_objects $net -filter "direction == in"]
            if {$load_pins eq ""} { continue }
            set fanout [sizeof_collection $load_pins]

            if {$fanout <= $max_fanout_limit} { continue }
            set found_violations 1

            set pin_name [get_attribute $dpin full_name]
            set net_name [get_attribute $net full_name]

            # Calculate buffers needed to bring fanout under limit
            set num_bufs [expr {int(ceil(double($fanout) / $max_fanout_limit)) - 1}]
            if {$num_bufs < 1} { set num_bufs 1 }

            if {$outfile eq ""} {
                # Insert buffers to create a buffer tree
                for {set b 0} {$b < $num_bufs} {incr b} {
                    if {$total_added >= $max_cells} { break }
                    set buf_name "FIX_FO_BUF_${iter}_${total_added}"
                    set status [insert_buffer $pin_name \
                                   -new_cell_name $buf_name \
                                   -lib_cell [get_lib_cells "*/$buffer_name"]]
                    if {$status ne ""} {
                        incr iter_added
                        incr total_added
                    }
                }
                incr iter_fixed
            } else {
                incr iter_added $num_bufs
                incr total_added $num_bufs
                incr iter_fixed
            }
        }

        if {!$found_violations} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No fanout violations above $max_fanout_limit"
            break
        }

        incr total_fixed $iter_fixed
        lappend report_lines ""
        lappend report_lines "  Iteration $iter: Fixed $iter_fixed high-fanout nets, inserted $iter_added buffers"
        if {$total_added >= $max_cells} { break }
    }

    return [list $total_fixed $total_added]
}

# ── Auto-select buffer based on violation type ────────────────────────────────
proc _select_driver_buffer {viol_type} {
    # For max_tran/max_cap: prefer medium-drive buffer
    # For max_fanout: prefer high-drive buffer
    switch -- $viol_type {
        "max_tran"   { set patterns {"*/BUFFD2*" "*/BUFFD1*" "*/BUF_X2*" "*/BUFX2*"} }
        "max_cap"    { set patterns {"*/BUFFD4*" "*/BUFFD2*" "*/BUF_X4*" "*/BUFX4*"} }
        "max_fanout" { set patterns {"*/BUFFD4*" "*/BUFFD8*" "*/BUF_X8*" "*/BUFX8*"} }
    }

    foreach pattern $patterns {
        set cells [get_lib_cells -quiet $pattern]
        if {$cells ne "" && [sizeof_collection $cells] > 0} {
            set first [index_collection $cells 0]
            return [get_attribute $first base_name]
        }
    }
    return ""
}
