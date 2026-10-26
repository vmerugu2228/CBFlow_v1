###############################################################################
# HELPER SCRIPTS FOR BUMP PLACEMENT DEBUGGING AND VISUALIZATION
# Updated with Signal I/O Assignment Support
###############################################################################

# ============================================================================
# Script 1: Visualize Bump Placement in GUI
# ============================================================================

proc visualize_bumps {} {
    puts "Visualizing bump placement..."
    
    # Zoom to fit all bumps
    fit
    
    # Highlight analog pin bumps (RED)
    deselect_obj -all
    select_bump -pattern "*_BUMP"
    gui_highlight -color red
    puts "Analog pin bumps highlighted in RED"
    
    # Highlight ground ring bumps (BLUE)
    deselect_obj -all
    select_bump -pattern "*_GND_*"
    gui_highlight -color blue
    puts "Ground ring bumps (VSSA) highlighted in BLUE"
    
    # Highlight VDD core bumps (GREEN)
    deselect_obj -all
    select_bump -pattern "CORE_VDD_*"
    gui_highlight -color green
    puts "Core VDD bumps highlighted in GREEN"
    
    # Highlight VSS core bumps (YELLOW)
    deselect_obj -all
    select_bump -pattern "CORE_VSS_*"
    gui_highlight -color yellow
    puts "Core VSS bumps highlighted in YELLOW"
    
    # Highlight signal I/O bumps (MAGENTA)
    deselect_obj -all
    set signal_bumps [dbGet top.bumps.net.name "*" -p]
    set sig_bump_names {}
    foreach bump $signal_bumps {
        set name [dbGet $bump.name]
        set net [dbGet $bump.net.name]
        # Skip power/ground nets
        if {$net != "VDD" && $net != "VSS" && $net != "VDDA" && $net != "VSSA" && \
            ![string match "*_GND_*" $name] && ![string match "*_BUMP" $name] && \
            ![string match "CORE_*" $name]} {
            lappend sig_bump_names $name
        }
    }
    if {[llength $sig_bump_names] > 0} {
        selectInst $sig_bump_names
        gui_highlight -color magenta
        puts "Signal I/O bumps highlighted in MAGENTA"
    }
    
    # Show I/O cells
    deselect_obj -all
    selectInst "IO_*"
    gui_highlight -color cyan
    puts "I/O cells highlighted in CYAN"
    
    deselect_obj -all
    puts "\nVisualization complete!"
    puts "\nColor Legend:"
    puts "  RED     - Analog pin bumps"
    puts "  BLUE    - Ground ring (VSSA)"
    puts "  GREEN   - Core VDD"
    puts "  YELLOW  - Core VSS"
    puts "  MAGENTA - Signal I/O bumps"
    puts "  CYAN    - I/O cells"
}

# ============================================================================
# Script 2: Verify Analog Pin Coverage
# ============================================================================

proc verify_analog_pin_coverage {analog_master} {
    puts "\n=========================================="
    puts "VERIFYING ANALOG PIN COVERAGE"
    puts "=========================================="
    
    set instances [dbGet top.insts.cell.name $analog_master -p]
    set total_pins 0
    set covered_pins 0
    set missing_pins {}
    
    foreach inst $instances {
        set inst_name [dbGet $inst.name]
        set pins [dbGet $inst.instTerms]
        
        foreach pin $pins {
            incr total_pins
            set pin_name [dbGet $pin.name]
            set expected_bump "${inst_name}_${pin_name}_BUMP"
            
            set bump_exists [dbGet top.bumps.name $expected_bump -p]
            if {$bump_exists != "" && $bump_exists != "0x0"} {
                incr covered_pins
            } else {
                lappend missing_pins "$inst_name : $pin_name"
            }
        }
    }
    
    puts "\nTotal analog pins:    $total_pins"
    puts "Pins with bumps:      $covered_pins"
    puts "Coverage:             [format "%.1f%%" [expr {$covered_pins * 100.0 / $total_pins}]]"
    
    if {[llength $missing_pins] > 0} {
        puts "\nWARNING: Missing bumps for [llength $missing_pins] pins:"
        foreach pin $missing_pins {
            puts "  - $pin"
        }
    } else {
        puts "\nSUCCESS: All analog pins have bumps!"
    }
    
    return $covered_pins
}

# ============================================================================
# Script 3: Verify Signal I/O Assignment
# ============================================================================

proc verify_signal_io_assignment {} {
    puts "\n=========================================="
    puts "VERIFYING SIGNAL I/O ASSIGNMENT"
    puts "=========================================="
    
    # Get all top-level signal ports (exclude power/ground)
    set all_signals [dbGet top.terms.name]
    set power_nets {VDD VSS VDDA VSSA}
    
    set total_signals 0
    set assigned_signals 0
    set unassigned_signals {}
    
    foreach signal $all_signals {
        # Skip power/ground
        if {[lsearch $power_nets $signal] >= 0} {continue}
        incr total_signals
        
        # Check if signal has a net and if that net has a bump
        set net_obj [dbGet top.nets.name $signal -p]
        if {$net_obj == "" || $net_obj == "0x0"} {
            lappend unassigned_signals "$signal (no net)"
            continue
        }
        
        # Check if any bump is connected to this net
        set bump_on_net [dbGet top.bumps.net.name $signal -p]
        if {$bump_on_net != "" && $bump_on_net != "0x0"} {
            incr assigned_signals
        } else {
            lappend unassigned_signals $signal
        }
    }
    
    puts "\nTotal signal ports:      $total_signals"
    puts "Ports with bumps:        $assigned_signals"
    puts "Coverage:                [format "%.1f%%" [expr {$assigned_signals * 100.0 / $total_signals}]]"
    
    if {[llength $unassigned_signals] > 0} {
        puts "\nWARNING: [llength $unassigned_signals] signals without bump assignment:"
        foreach sig [lrange $unassigned_signals 0 19] {
            puts "  - $sig"
        }
        if {[llength $unassigned_signals] > 20} {
            puts "  ... and [expr {[llength $unassigned_signals] - 20}] more"
        }
    } else {
        puts "\nSUCCESS: All signal ports have bump assignments!"
    }
    
    return $assigned_signals
}

# ============================================================================
# Script 4: Verify I/O Cell Placement
# ============================================================================

proc verify_io_cell_placement {} {
    puts "\n=========================================="
    puts "VERIFYING I/O CELL PLACEMENT"
    puts "=========================================="
    
    set io_cells [dbGet top.insts.name "IO_*" -p]
    
    if {[llength $io_cells] == 0} {
        puts "WARNING: No I/O cells found (pattern: IO_*)"
        return 0
    }
    
    puts "Total I/O cells: [llength $io_cells]"
    puts ""
    
    set cells_with_bumps 0
    set cells_without_bumps {}
    
    foreach io_cell $io_cells {
        set cell_name [dbGet $io_cell.name]
        
        # Extract signal name from cell name (IO_signalname)
        set signal [string range $cell_name 3 end]
        
        # Check if signal has a bump
        set bump [dbGet top.bumps.net.name $signal -p]
        if {$bump != "" && $bump != "0x0"} {
            incr cells_with_bumps
        } else {
            lappend cells_without_bumps $cell_name
        }
    }
    
    puts "I/O cells with assigned bumps: $cells_with_bumps"
    puts "I/O cells without bumps:       [llength $cells_without_bumps]"
    
    if {[llength $cells_without_bumps] > 0} {
        puts "\nI/O cells without bump assignment:"
        foreach cell [lrange $cells_without_bumps 0 9] {
            puts "  - $cell"
        }
        if {[llength $cells_without_bumps] > 10} {
            puts "  ... and [expr {[llength $cells_without_bumps] - 10}] more"
        }
    }
    
    return $cells_with_bumps
}

# ============================================================================
# Script 5: Export Bump Coordinates to CSV
# ============================================================================

proc export_bump_coordinates {filename} {
    puts "Exporting bump coordinates to $filename..."
    
    set fp [open $filename w]
    
    # Write header
    puts $fp "Bump_Name,Net,X_um,Y_um,Type,Instance"
    
    # Get all bumps
    foreach bump [dbGet top.bumps] {
        set name [dbGet $bump.name]
        set net [dbGet $bump.net.name]
        if {$net == "" || $net == "0x0"} {set net "UNASSIGNED"}
        lassign [dbGet $bump.pt] x y
        
        # Determine type
        if {[string match "*_GND_*" $name]} {
            set type "GROUND_RING"
            set inst [lindex [split $name "_GND_"] 0]
        } elseif {[string match "*_BUMP" $name]} {
            set type "ANALOG_PIN"
            set inst [lindex [split $name "_"] 0]
        } elseif {[string match "CORE_VDD_*" $name]} {
            set type "CORE_POWER"
            set inst "CORE"
        } elseif {[string match "CORE_VSS_*" $name]} {
            set type "CORE_GROUND"
            set inst "CORE"
        } else {
            set type "SIGNAL_IO"
            set inst "N/A"
        }
        
        puts $fp "$name,$net,$x,$y,$type,$inst"
    }
    
    close $fp
    puts "Export complete: $filename"
}

# ============================================================================
# Script 6: Export Signal-to-Bump-to-IOCell Mapping
# ============================================================================

proc export_signal_mapping {filename} {
    puts "Exporting signal-to-bump-to-IOcell mapping to $filename..."
    
    set fp [open $filename w]
    
    # Write header
    puts $fp "Signal_Name,Bump_Name,Bump_X,Bump_Y,IOCell_Name,IOCell_Master,IOCell_X,IOCell_Y,Direction"
    
    # Get all signal I/O cells
    set io_cells [dbGet top.insts.name "IO_*" -p]
    
    foreach io_cell $io_cells {
        set cell_name [dbGet $io_cell.name]
        set cell_master [dbGet $io_cell.cell.name]
        lassign [dbGet $io_cell.pt] cell_x cell_y
        
        # Extract signal name
        set signal [string range $cell_name 3 end]
        
        # Get direction
        set port [dbGet top.terms.name $signal -p]
        if {$port != "" && $port != "0x0"} {
            set direction [dbGet $port.direction]
        } else {
            set direction "UNKNOWN"
        }
        
        # Find bump for this signal
        set bump [dbGet top.bumps.net.name $signal -p]
        if {$bump != "" && $bump != "0x0"} {
            set bump_name [dbGet $bump.name]
            lassign [dbGet $bump.pt] bump_x bump_y
        } else {
            set bump_name "NO_BUMP"
            set bump_x "N/A"
            set bump_y "N/A"
        }
        
        puts $fp "$signal,$bump_name,$bump_x,$bump_y,$cell_name,$cell_master,$cell_x,$cell_y,$direction"
    }
    
    close $fp
    puts "Export complete: $filename"
}

# ============================================================================
# Script 7: Check for Bump Spacing Violations
# ============================================================================

proc check_bump_spacing {min_spacing} {
    puts "\n=========================================="
    puts "CHECKING BUMP SPACING VIOLATIONS"
    puts "Minimum spacing: $min_spacing μm"
    puts "=========================================="
    
    set bumps [dbGet top.bumps]
    set violations {}
    
    for {set i 0} {$i < [llength $bumps]} {incr i} {
        set bump1 [lindex $bumps $i]
        set name1 [dbGet $bump1.name]
        lassign [dbGet $bump1.pt] x1 y1
        
        for {set j [expr {$i + 1}]} {$j < [llength $bumps]} {incr j} {
            set bump2 [lindex $bumps $j]
            set name2 [dbGet $bump2.name]
            lassign [dbGet $bump2.pt] x2 y2
            
            set dx [expr {$x2 - $x1}]
            set dy [expr {$y2 - $y1}]
            set dist [expr {sqrt($dx*$dx + $dy*$dy)}]
            
            if {$dist < $min_spacing && $dist > 0.01} {
                lappend violations [list $name1 $name2 $dist]
            }
        }
    }
    
    if {[llength $violations] == 0} {
        puts "\nSUCCESS: No spacing violations found!"
        return 0
    } else {
        puts "\nERROR: Found [llength $violations] spacing violations:"
        foreach viol [lrange $violations 0 19] {
            lassign $viol b1 b2 d
            puts [format "  %-30s <-> %-30s : %.2f μm" $b1 $b2 $d]
        }
        if {[llength $violations] > 20} {
            puts "  ... and [expr {[llength $violations] - 20}] more violations"
        }
        return [llength $violations]
    }
}

# ============================================================================
# Script 8: Generate Bump-to-Pin Connection Report
# ============================================================================

proc report_bump_pin_connections {analog_master output_file} {
    puts "Generating bump-to-pin connection report..."
    
    set fp [open $output_file w]
    
    puts $fp "=========================================="
    puts $fp "BUMP-TO-PIN CONNECTION REPORT"
    puts $fp "=========================================="
    puts $fp ""
    
    set instances [dbGet top.insts.cell.name $analog_master -p]
    
    foreach inst $instances {
        set inst_name [dbGet $inst.name]
        puts $fp "\nInstance: $inst_name"
        puts $fp [string repeat "-" 80]
        puts $fp [format "%-25s %-20s %-25s %-10s" "Pin Name" "Net" "Bump Name" "Status"]
        puts $fp [string repeat "-" 80]
        
        set pins [dbGet $inst.instTerms]
        
        foreach pin $pins {
            set pin_name [dbGet $pin.name]
            set net_name [dbGet $pin.net.name]
            if {$net_name == "" || $net_name == "0x0"} {set net_name "FLOATING"}
            
            set bump_name "${inst_name}_${pin_name}_BUMP"
            set bump_obj [dbGet top.bumps.name $bump_name -p]
            
            if {$bump_obj != "" && $bump_obj != "0x0"} {
                set bump_net [dbGet $bump_obj.net.name]
                if {$bump_net == $net_name} {
                    set status "OK"
                } else {
                    set status "MISMATCH"
                }
            } else {
                set bump_name "NO_BUMP"
                set status "MISSING"
            }
            
            puts $fp [format "%-25s %-20s %-25s %-10s" $pin_name $net_name $bump_name $status]
        }
    }
    
    close $fp
    puts "Report written to: $output_file"
}

# ============================================================================
# Script 9: Fix Overlapping Bumps
# ============================================================================

proc fix_overlapping_bumps {tolerance} {
    puts "\n=========================================="
    puts "FIXING OVERLAPPING BUMPS"
    puts "Tolerance: $tolerance μm"
    puts "=========================================="
    
    set bumps [dbGet top.bumps]
    set deleted_count 0
    
    for {set i 0} {$i < [llength $bumps]} {incr i} {
        set bump1 [lindex $bumps $i]
        set name1 [dbGet $bump1.name]
        lassign [dbGet $bump1.pt] x1 y1
        
        for {set j [expr {$i + 1}]} {$j < [llength $bumps]} {incr j} {
            set bump2 [lindex $bumps $j]
            set name2 [dbGet $bump2.name]
            lassign [dbGet $bump2.pt] x2 y2
            
            set dx [expr {abs($x2 - $x1)}]
            set dy [expr {abs($y2 - $y1)}]
            
            if {$dx < $tolerance && $dy < $tolerance} {
                puts "WARNING: Overlapping bumps found:"
                puts "  $name1 at ($x1, $y1)"
                puts "  $name2 at ($x2, $y2)"
                
                # Keep analog pin bump, delete core bump
                if {[string match "*_BUMP" $name1] && [string match "CORE_*" $name2]} {
                    puts "  Deleting $name2 (core bump)"
                    deleteBumps $name2
                    incr deleted_count
                } elseif {[string match "CORE_*" $name1] && [string match "*_BUMP" $name2]} {
                    puts "  Deleting $name1 (core bump)"
                    deleteBumps $name1
                    incr deleted_count
                }
            }
        }
    }
    
    puts "\nDeleted $deleted_count overlapping bumps"
    return $deleted_count
}

# ============================================================================
# Script 10: Adjust Bump Location (Fine-tuning)
# ============================================================================

proc adjust_bump_location {bump_name new_x new_y} {
    puts "Adjusting bump location: $bump_name"
    
    # Check if bump exists
    set bump_obj [dbGet top.bumps.name $bump_name -p]
    if {$bump_obj == "" || $bump_obj == "0x0"} {
        puts "ERROR: Bump not found: $bump_name"
        return 0
    }
    
    # Get current location and net
    lassign [dbGet $bump_obj.pt] old_x old_y
    set net [dbGet $bump_obj.net.name]
    
    puts "  Old location: ($old_x, $old_y)"
    puts "  New location: ($new_x, $new_y)"
    puts "  Net: $net"
    
    # Delete old bump
    deleteBumps $bump_name
    
    # Create new bump at adjusted location
    set bump_cell [dbGet head.libCells.name "*Bump*" -p]
    if {$bump_cell == "" || $bump_cell == "0x0"} {
        set bump_cell [dbGet head.libCells.name "*BUMP*" -p]
    }
    
    create_bump \
        -cell [dbGet $bump_cell.name] \
        -loc [list $new_x $new_y] \
        -loc_type cell_center \
        -name_format $bump_name
    
    # Re-assign to net
    if {$net != "" && $net != "0x0"} {
        assignBump -net $net -bump $bump_name
    }
    
    puts "Bump adjusted successfully"
    return 1
}

# ============================================================================
# Script 11: List Available Signals for Assignment
# ============================================================================

proc list_available_signals {} {
    puts "\n=========================================="
    puts "AVAILABLE SIGNALS FOR BUMP ASSIGNMENT"
    puts "=========================================="
    
    set all_signals [dbGet top.terms.name]
    set power_nets {VDD VSS VDDA VSSA}
    
    set available {}
    set already_assigned {}
    
    foreach signal $all_signals {
        # Skip power/ground
        if {[lsearch $power_nets $signal] >= 0} {continue}
        
        # Check if signal already has a bump
        set bump [dbGet top.bumps.net.name $signal -p]
        if {$bump != "" && $bump != "0x0"} {
            lappend already_assigned $signal
        } else {
            lappend available $signal
        }
    }
    
    puts "\nSignals already assigned to bumps: [llength $already_assigned]"
    puts "Signals available for assignment:  [llength $available]"
    puts ""
    
    if {[llength $available] > 0} {
        puts "Available signals (first 50):"
        foreach sig [lrange $available 0 49] {
            # Get direction
            set port [dbGet top.terms.name $sig -p]
            set dir [dbGet $port.direction]
            puts [format "  %-40s [%s]" $sig $dir]
        }
        if {[llength $available] > 50} {
            puts "  ... and [expr {[llength $available] - 50}] more"
        }
    }
    
    return $available
}

# ============================================================================
# Script 12: Generate Assignment File from Existing Layout
# ============================================================================

proc generate_assignment_from_layout {output_file} {
    puts "Generating assignment file from current layout..."
    
    set fp [open $output_file w]
    
    puts $fp "###############################################################################"
    puts $fp "# AUTO-GENERATED SIGNAL ASSIGNMENT FILE"
    puts $fp "# Generated from current bump placement"
    puts $fp "# Edit as needed and re-run bump placement script"
    puts $fp "###############################################################################"
    puts $fp ""
    
    # Get all signal bumps (not power/ground)
    set signal_bumps {}
    foreach bump [dbGet top.bumps] {
        set net [dbGet $bump.net.name]
        if {$net != "" && $net != "0x0" && \
            $net != "VDD" && $net != "VSS" && $net != "VDDA" && $net != "VSSA"} {
            set name [dbGet $bump.name]
            if {![string match "*_GND_*" $name] && ![string match "*_BUMP" $name] && \
                ![string match "CORE_*" $name]} {
                lappend signal_bumps [list $name $net [dbGet $bump.pt]]
            }
        }
    }
    
    if {[llength $signal_bumps] == 0} {
        puts $fp "# No signal bumps found in current layout"
        close $fp
        puts "WARNING: No signal bumps found"
        return
    }
    
    # Group by approximate regions
    puts $fp "# Detected [llength $signal_bumps] signal bump assignments"
    puts $fp ""
    puts $fp "CURRENT_LAYOUT, 0, 0, 99999, 99999, {"
    foreach bump_info $signal_bumps {
        lassign $bump_info name net loc
        puts $fp "  $net"
    }
    puts $fp "}"
    
    close $fp
    puts "Generated assignment file: $output_file"
}

# ============================================================================
# Script 13: Complete Verification Suite
# ============================================================================

proc run_complete_verification {} {
    puts "\n=========================================="
    puts "RUNNING COMPLETE BUMP VERIFICATION SUITE"
    puts "=========================================="
    
    # Run all verification checks
    verify_analog_pin_coverage "u_analog_macro"
    verify_signal_io_assignment
    verify_io_cell_placement
    check_bump_spacing 150.0
    
    puts "\n=========================================="
    puts "VERIFICATION COMPLETE"
    puts "=========================================="
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================

puts "\n=========================================="
puts "BUMP HELPER SCRIPTS LOADED"
puts "=========================================="
puts "Available commands:"
puts ""
puts "Visualization:"
puts "  visualize_bumps"
puts ""
puts "Verification:"
puts "  verify_analog_pin_coverage u_analog_macro"
puts "  verify_signal_io_assignment"
puts "  verify_io_cell_placement"
puts "  check_bump_spacing 150.0"
puts "  run_complete_verification"
puts ""
puts "Reporting:"
puts "  export_bump_coordinates bumps.csv"
puts "  export_signal_mapping signal_map.csv"
puts "  report_bump_pin_connections u_analog_macro connections.rpt"
puts ""
puts "Utilities:"
puts "  fix_overlapping_bumps 10.0"
puts "  adjust_bump_location BUMP_NAME new_x new_y"
puts "  list_available_signals"
puts "  generate_assignment_from_layout assignment_backup.txt"
puts "=========================================="
