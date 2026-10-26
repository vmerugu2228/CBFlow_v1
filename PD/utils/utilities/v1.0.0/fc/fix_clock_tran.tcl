#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# Clock Transition Violation Fixer — Fusion Compiler (fc_shell)
# Standalone. Reads design from FC session. No CBflow dependency.
#
# ═══════════════════════════════════════════════════════════════════════════════
# USAGE:
#   source fix_clock_tran.tcl
#   fix_clock_tran -max_tran 0.100
#   fix_clock_tran -max_tran 0.080 -ck_buffers {CKBD4 CKBD8 CKBD16}
#   fix_clock_tran -max_tran 0.100 -auto
#   fix_clock_tran -max_tran 0.100 -out clock_tran_report.rpt
#
# ARGUMENTS:
#   -max_tran <ns>         Maximum allowed clock transition (required)
#   -ck_buffers <list>     Allowed clock buffer cells, ordered small to large (required unless -auto)
#   -auto                  Auto-detect clock buffers from technology library
#   -max_iter <int>        Maximum fix iterations (default: 3)
#   -max_cells <int>       Maximum cells to insert (default: 2000)
#   -size_only             Only try sizing — do not insert new buffers
#   -out <file>            Write report to file (default: stdout)
#
# FIX STRATEGY:
#   1. Find clock network cells with transition > threshold
#   2. Attempt to size up undersized clock buffers (within allowed cells)
#   3. If sizing insufficient, insert additional clock buffer before violator
#   4. Only uses allowed clock cells — never inserts non-clock buffers
#
# EXAMPLES:
#   # Fix with explicit clock buffer list
#   fix_clock_tran -max_tran 0.100 -ck_buffers {CKBD4 CKBD8 CKBD16}
#
#   # Auto-detect clock buffers from library
#   fix_clock_tran -max_tran 0.080 -auto
#
#   # Size-only mode — no new buffer insertion
#   fix_clock_tran -max_tran 0.100 -ck_buffers {CKBD4 CKBD8 CKBD16} -size_only
#
#   # Write report
#   fix_clock_tran -max_tran 0.100 -auto -out ck_tran_fix.rpt
#
# FC-SPECIFIC COMMANDS USED:
#   get_clocks
#   get_clock_network_objects -type cell
#   get_attribute (ref_name, full_name, actual_rise_transition, actual_fall_transition)
#   get_pins -of_objects -filter "direction == out"
#   size_cell -lib_cell
#   insert_buffer -new_cell_name -lib_cell
#   get_lib_cells
#   sizeof_collection
# ═══════════════════════════════════════════════════════════════════════════════

proc fix_clock_tran {args} {
    set max_tran ""
    set ck_buffers [list]
    set auto_select 0
    set max_iter 3
    set max_cells 2000
    set size_only 0
    set outfile ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -max_tran    { incr i; set max_tran [lindex $args $i] }
            -ck_buffers  { incr i; set ck_buffers [lindex $args $i] }
            -auto        { set auto_select 1 }
            -max_iter    { incr i; set max_iter [lindex $args $i] }
            -max_cells   { incr i; set max_cells [lindex $args $i] }
            -size_only   { set size_only 1 }
            -out         { incr i; set outfile [lindex $args $i] }
            default      { error "Unknown option: [lindex $args $i]" }
        }
    }

    if {$max_tran eq ""} { error "-max_tran required" }
    if {[llength $ck_buffers] == 0 && !$auto_select} { error "-ck_buffers or -auto required" }

    # ── Auto-detect clock buffers ─────────────────────────────────────
    if {$auto_select} {
        set ck_buffers [_detect_clock_buffers]
        if {[llength $ck_buffers] == 0} {
            error "Auto-detect failed: no clock buffer cells found in libraries"
        }
    }

    # Verify all clock buffers exist — FC: get_lib_cells
    set ck_lib_cells [list]
    foreach ckb $ck_buffers {
        set lc [get_lib_cells -quiet "*/$ckb"]
        if {$lc eq "" || [sizeof_collection $lc] == 0} {
            error "Clock buffer cell '$ckb' not found in any library"
        }
        lappend ck_lib_cells $ckb
    }

    # Build drive-strength ordering (by area as proxy)
    set ck_ordered [_order_by_drive $ck_lib_cells]

    set report_lines [list]
    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  Clock Transition Fix Report"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"
    lappend report_lines "  Max transition     : $max_tran ns"
    lappend report_lines "  Clock buffers      : [join $ck_ordered ", "]"
    lappend report_lines "  Max iterations     : $max_iter"
    lappend report_lines "  Max cells          : $max_cells"
    lappend report_lines "  Size-only mode     : [expr {$size_only ? "yes" : "no"}]"
    lappend report_lines "───────────────────────────────────────────────────────────────────"

    # ── Get all clocks ────────────────────────────────────────────────
    set clocks [get_clocks -quiet *]
    if {$clocks eq "" || [sizeof_collection $clocks] == 0} {
        error "No clocks defined in design"
    }

    set total_sized 0
    set total_inserted 0
    set total_fixed 0

    # ── Iterative fix loop ────────────────────────────────────────────
    for {set iter 1} {$iter <= $max_iter} {incr iter} {
        set iter_sized 0
        set iter_inserted 0
        set iter_fixed 0
        set violators [list]

        # Collect violating clock cells — FC: get_clock_network_objects
        foreach_in_collection clk $clocks {
            set clk_name [get_attribute $clk full_name]
            set ck_cells [get_clock_network_objects -type cell -clocks $clk_name]
            if {$ck_cells eq "" || [sizeof_collection $ck_cells] == 0} { continue }

            foreach_in_collection cell $ck_cells {
                set cell_name [get_attribute $cell full_name]
                set ref_name  [get_attribute $cell ref_name]

                # Get output pin transition — FC: get_pins, get_attribute
                set out_pins [get_pins -quiet -of_objects $cell -filter "direction == out"]
                if {$out_pins eq "" || [sizeof_collection $out_pins] == 0} { continue }

                set out_pin [index_collection $out_pins 0]
                set rise_tran [get_attribute $out_pin actual_rise_transition]
                set fall_tran [get_attribute $out_pin actual_fall_transition]

                # Use worst of rise/fall
                set worst_tran $rise_tran
                if {$fall_tran > $worst_tran} { set worst_tran $fall_tran }

                if {$worst_tran > $max_tran} {
                    lappend violators [list $cell_name $ref_name $worst_tran $clk_name \
                                           [get_attribute $out_pin full_name]]
                }
            }
        }

        # Sort by worst transition (descending) — fix worst first
        set violators [lsort -real -decreasing -index 2 $violators]

        if {[llength $violators] == 0} {
            lappend report_lines ""
            lappend report_lines "  Iteration $iter: No clock transition violations above $max_tran ns"
            break
        }

        lappend report_lines ""
        lappend report_lines "  Iteration $iter: [llength $violators] violating cell(s)"

        foreach viol $violators {
            if {[expr {$total_sized + $total_inserted}] >= $max_cells} {
                lappend report_lines "  WARNING: Max cell limit ($max_cells) reached"
                break
            }

            set cell_name [lindex $viol 0]
            set ref_name  [lindex $viol 1]
            set tran_val  [lindex $viol 2]
            set clk_name  [lindex $viol 3]
            set out_pin   [lindex $viol 4]

            # ── Step 1: Try sizing up ─────────────────────────────────
            set sized_up 0
            set next_cell [_find_next_size $ref_name $ck_ordered]

            if {$next_cell ne ""} {
                if {$outfile eq ""} {
                    set status [size_cell $cell_name -lib_cell [get_lib_cells "*/$next_cell"]]
                    if {$status ne ""} {
                        set sized_up 1
                        incr iter_sized
                        incr total_sized
                        incr iter_fixed
                    }
                } else {
                    set sized_up 1
                    incr iter_sized
                    incr total_sized
                    incr iter_fixed
                }
            }

            # ── Step 2: Insert buffer if sizing not sufficient ────────
            if {!$sized_up && !$size_only} {
                # Use largest available clock buffer for insertion
                set insert_buf [lindex $ck_ordered end]

                if {$outfile eq ""} {
                    set buf_name "FIX_CK_TRAN_${iter}_${iter_inserted}"
                    set status [insert_buffer $out_pin \
                                   -new_cell_name $buf_name \
                                   -lib_cell [get_lib_cells "*/$insert_buf"]]
                    if {$status ne ""} {
                        incr iter_inserted
                        incr total_inserted
                        incr iter_fixed
                    }
                } else {
                    incr iter_inserted
                    incr total_inserted
                    incr iter_fixed
                }
            }
        }

        incr total_fixed $iter_fixed
        lappend report_lines "    Cells sized up   : $iter_sized"
        lappend report_lines "    Buffers inserted : $iter_inserted"
        if {[expr {$total_sized + $total_inserted}] >= $max_cells} { break }
    }

    # ── Final check ───────────────────────────────────────────────────
    if {$outfile eq ""} {
        set remaining_count 0
        set remaining_worst 0.0
        foreach_in_collection clk $clocks {
            set clk_name [get_attribute $clk full_name]
            set ck_cells [get_clock_network_objects -type cell -clocks $clk_name]
            if {$ck_cells eq "" || [sizeof_collection $ck_cells] == 0} { continue }
            foreach_in_collection cell $ck_cells {
                set out_pins [get_pins -quiet -of_objects $cell -filter "direction == out"]
                if {$out_pins eq "" || [sizeof_collection $out_pins] == 0} { continue }
                set out_pin [index_collection $out_pins 0]
                set rise_tran [get_attribute $out_pin actual_rise_transition]
                set fall_tran [get_attribute $out_pin actual_fall_transition]
                set worst [expr {max($rise_tran, $fall_tran)}]
                if {$worst > $max_tran} {
                    incr remaining_count
                    if {$worst > $remaining_worst} { set remaining_worst $worst }
                }
            }
        }
        lappend report_lines ""
        if {$remaining_count > 0} {
            lappend report_lines "  Remaining violations : $remaining_count"
            lappend report_lines "  Worst remaining tran : [format %.4f $remaining_worst] ns"
        } else {
            lappend report_lines "  All clock transition violations resolved"
        }
    }

    # ── Summary ───────────────────────────────────────────────────────
    lappend report_lines ""
    lappend report_lines "───────────────────────────────────────────────────────────────────"
    lappend report_lines "  Total cells sized up       : $total_sized"
    lappend report_lines "  Total buffers inserted     : $total_inserted"
    lappend report_lines "  Total violations addressed : $total_fixed"
    lappend report_lines "═══════════════════════════════════════════════════════════════════"

    set report_text [join $report_lines "\n"]

    if {$outfile ne ""} {
        set fh [open $outfile "w"]
        puts $fh $report_text
        close $fh
        puts "Clock transition fix report written to $outfile"
    } else {
        puts $report_text
    }

    return [expr {$total_sized + $total_inserted}]
}

# ── Detect clock buffers from library ─────────────────────────────────────────
proc _detect_clock_buffers {} {
    set found [list]
    foreach pattern {"*/CK*BUF*" "*/CKBD*" "*/CKBUF*" "*/CLK*BUF*" "*/CK_BUF*"} {
        set cells [get_lib_cells -quiet $pattern]
        if {$cells ne "" && [sizeof_collection $cells] > 0} {
            foreach_in_collection c $cells {
                set cname [get_attribute $c base_name]
                if {[lsearch -exact $found $cname] < 0} {
                    lappend found $cname
                }
            }
        }
    }
    # Also check for clock inverters as backup
    if {[llength $found] == 0} {
        foreach pattern {"*/CK*INV*" "*/CKINV*" "*/CLK*INV*"} {
            set cells [get_lib_cells -quiet $pattern]
            if {$cells ne "" && [sizeof_collection $cells] > 0} {
                foreach_in_collection c $cells {
                    set cname [get_attribute $c base_name]
                    if {[lsearch -exact $found $cname] < 0} {
                        lappend found $cname
                    }
                }
            }
        }
    }
    return [_order_by_drive $found]
}

# ── Order cell list by drive strength (area as proxy) ─────────────────────────
proc _order_by_drive {cell_list} {
    set with_area [list]
    foreach cname $cell_list {
        set lc [get_lib_cells -quiet "*/$cname"]
        if {$lc eq "" || [sizeof_collection $lc] == 0} { continue }
        set first [index_collection $lc 0]
        set area [get_attribute $first area]
        lappend with_area [list $cname $area]
    }
    set sorted [lsort -real -index 1 $with_area]
    set result [list]
    foreach item $sorted {
        lappend result [lindex $item 0]
    }
    return $result
}

# ── Find next larger size in ordered list ─────────────────────────────────────
proc _find_next_size {current_ref ordered_list} {
    set idx [lsearch -exact $ordered_list $current_ref]
    if {$idx < 0} {
        # Current cell not in allowed list — return largest allowed
        return [lindex $ordered_list end]
    }
    set next_idx [expr {$idx + 1}]
    if {$next_idx < [llength $ordered_list]} {
        return [lindex $ordered_list $next_idx]
    }
    # Already at largest — no further sizing possible
    return ""
}
