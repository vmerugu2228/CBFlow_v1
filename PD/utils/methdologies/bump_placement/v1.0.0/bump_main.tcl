###############################################################################
# FLIP-CHIP BUMP PLACEMENT SCRIPT WITH SIGNAL I/O ASSIGNMENT
# Design: Analog macro with 6 instances + Core digital logic + Signal I/Os
# Requirements:
#   - Bumps exactly on analog pins
#   - 1 row VSSA bumps around each analog macro
#   - Shared ground rows between adjacent analog macros
#   - Core area: Checkerboard VDD/VSS pattern
#   - Signal I/O assignment to user-specified regions
#   - Pitch: 150μm, Edge spacing: 50μm
###############################################################################

# ============================================================================
# CONFIGURATION PARAMETERS
# ============================================================================

set BUMP_CELL "Bump_130x"
set BUMP_PITCH 150.0
set EDGE_SPACING 50.0

# Analog configuration
set ANALOG_MASTER "u_analog_macro"
set ANALOG_POWER_NET "VDDA"
set ANALOG_GROUND_NET "VSSA"

# Digital configuration
set DIGITAL_POWER_NET "VDD"
set DIGITAL_GROUND_NET "VSS"

# Ground ring configuration
set GROUND_RING_OFFSET $BUMP_PITCH  ;# 1 row at 150μm

# I/O cell configuration (dummy cell names - update with actual cell names)
set IO_INPUT_CELL "IO_INPUT_CELL"
set IO_OUTPUT_CELL "IO_OUTPUT_CELL"
set IO_BIDIR_CELL "IO_BIDIR_CELL"
set IO_PLACEMENT_OFFSET 50.0  ;# Distance from bump to I/O cell (microns)

# Signal I/O assignment fi
set SIGNAL_ASSIGNMENT_FILE "bump_assignemnt_template.tcl"

# ============================================================================
# HELPER PROCEDURES
# ============================================================================

proc get_analog_instances {master_name} {
    # Get all instances of analog macro
    set instances [dbGet top.insts.cell.name $master_name -p]
    if {[llength $instances] == 0} {
        puts "ERROR: No instances found for master: $master_name"
        return {}
    }
    set inst_names [dbGet $instances.name]
    puts "Found [llength $inst_names] instances of $master_name:"
    foreach inst $inst_names {
        puts "  - $inst"
    }
    return $instances
}

proc get_instance_bbox {inst_obj} {
    # Get bounding box of instance {llx lly urx ury}
    set bbox [dbGet $inst_obj.box]
    return $bbox
}

proc expand_bbox {bbox offset} {
    # Expand bbox by offset in all directions
    lassign $bbox llx lly urx ury
    return [list \
        [expr {$llx - $offset}] \
        [expr {$lly - $offset}] \
        [expr {$urx + $offset}] \
        [expr {$ury + $offset}]]
}

proc create_bump_at_location {x y bump_name cell_name} {
    # Create a single bump at exact location
    create_bump \
        -cell $cell_name \
        -loc [list $x $y] \
        -loc_type cell_center \
        -name_format $bump_name \
        -orientation R0
    
    # Verify bump was created
    if {[dbGet top.bumps.name $bump_name -p] == ""} {
        puts "WARNING: Failed to create bump: $bump_name at ($x, $y)"
        return 0
    }
    return 1
}

proc bboxes_overlap {bbox1 bbox2} {
    # Check if two bounding boxes overlap
    lassign $bbox1 llx1 lly1 urx1 ury1
    lassign $bbox2 llx2 lly2 urx2 ury2
    
    if {$urx1 <= $llx2 || $urx2 <= $llx1} {return 0}
    if {$ury1 <= $lly2 || $ury2 <= $lly1} {return 0}
    return 1
}

proc point_in_bbox {x y bbox} {
    # Check if point (x,y) is inside bounding box
    lassign $bbox llx lly urx ury
    return [expr {$x >= $llx && $x <= $urx && $y >= $lly && $y <= $ury}]
}

proc find_nearest_bump {x y region_bbox available_bumps} {
    # Find nearest available bump to location (x,y) within region
    set min_dist 1e20
    set nearest_bump ""
    
    foreach bump $available_bumps {
        set bump_obj [dbGet top.bumps.name $bump -p]
        if {$bump_obj == "" || $bump_obj == "0x0"} {continue}
        
        lassign [dbGet $bump_obj.pt] bx by
        
        # Check if bump is in the specified region
        if {![point_in_bbox $bx $by $region_bbox]} {continue}
        
        # Calculate distance
        set dx [expr {$bx - $x}]
        set dy [expr {$by - $y}]
        set dist [expr {sqrt($dx*$dx + $dy*$dy)}]
        
        if {$dist < $min_dist} {
            set min_dist $dist
            set nearest_bump $bump
        }
    }
    
    return $nearest_bump
}

proc get_signal_direction {signal_name} {
    # Determine signal direction from top-level port
    set port [dbGet top.terms.name $signal_name -p]
    if {$port == "" || $port == "0x0"} {
        puts "    WARNING: Signal $signal_name not found at top level"
        return "unknown"
    }
    
    set direction [dbGet $port.direction]
    return [string tolower $direction]
}

proc get_io_cell_for_signal {direction io_input_cell io_output_cell io_bidir_cell} {
    # Select appropriate I/O cell based on signal direction
    switch -exact $direction {
        "input" {return $io_input_cell}
        "output" {return $io_output_cell}
        "inout" {return $io_bidir_cell}
        default {return $io_input_cell}
    }
}

proc place_io_cell_near_bump {signal_name bump_name io_cell offset} {
    # Place I/O cell near bump at legal location
    set bump_obj [dbGet top.bumps.name $bump_name -p]
    if {$bump_obj == "" || $bump_obj == "0x0"} {
        puts "    ERROR: Bump $bump_name not found"
        return 0
    }
    
    lassign [dbGet $bump_obj.pt] bx by
    
    # Calculate target location (offset below bump)
    set target_x $bx
    set target_y [expr {$by - $offset}]
    
    # Create instance name
    set io_inst_name "IO_${signal_name}"
    
    # Check if I/O cell exists in library
    set cell_obj [dbGet head.libCells.name $io_cell -p]
    if {$cell_obj == "" || $cell_obj == "0x0"} {
        puts "    WARNING: I/O cell $io_cell not found in library, skipping placement"
        return 0
    }
    
    # Create instance
    createInst $io_inst_name $io_cell
    
    # Place at target location
    placeInstance $io_inst_name $target_x $target_y -placed
    
    puts "    Placed I/O cell: $io_inst_name at ($target_x, $target_y)"
    return 1
}

proc create_signal_assignment_template {filename} {
    # Create template assignment file
    set fp [open $filename w]
    
    puts $fp "###############################################################################"
    puts $fp "# SIGNAL I/O TO BUMP ASSIGNMENT FILE"
    puts $fp "# Format: REGION_NAME, llx, lly, urx, ury, {signal_list}"
    puts $fp "#"
    puts $fp "# REGION_NAME: Descriptive name for the region (e.g., LEFT_SIDE, TOP_EDGE)"
    puts $fp "# llx, lly:    Lower-left corner coordinates (microns)"
    puts $fp "# urx, ury:    Upper-right corner coordinates (microns)"
    puts $fp "# signal_list: List of signal names in curly braces"
    puts $fp "#"
    puts $fp "# Example:"
    puts $fp "# LEFT_SIDE, 100, 1000, 500, 5000, {sig_a sig_b sig_c data\[0\] data\[1\]}"
    puts $fp "#"
    puts $fp "# Notes:"
    puts $fp "# - Lines starting with # are comments"
    puts $fp "# - Bus signals use brackets: data\[0\], addr\[7\]"
    puts $fp "# - Signals are assigned to nearest available bump in the region"
    puts $fp "# - Bumps must be available (not already assigned to power/ground)"
    puts $fp "###############################################################################"
    puts $fp ""
    puts $fp "# Example assignments (update with your actual signals and coordinates)"
    puts $fp "LEFT_SIDE, 100, 1000, 500, 5000, {clk_in reset_n enable data_in\[0\] data_in\[1\]}"
    puts $fp "RIGHT_SIDE, 9500, 1000, 10000, 5000, {data_out\[0\] data_out\[1\] valid_out ready_in}"
    puts $fp "TOP_EDGE, 2000, 9500, 8000, 10000, {addr\[0\] addr\[1\] addr\[2\] addr\[3\]}"
    puts $fp "BOTTOM_EDGE, 2000, 100, 8000, 500, {debug\[0\] debug\[1\] test_mode scan_en}"
    
    close $fp
    puts "Created signal assignment template: $filename"
}

proc parse_signal_assignment_file {filename} {
    # Parse signal assignment file and return list of regions
    if {![file exists $filename]} {
        puts "ERROR: Signal assignment file not found: $filename"
        return {}
    }
    
    set fp [open $filename r]
    set regions {}
    set line_num 0
    
    while {[gets $fp line] >= 0} {
        incr line_num
        set line [string trim $line]
        
        # Skip comments and empty lines
        if {$line == "" || [string index $line 0] == "#"} {continue}
        
        # Parse line: REGION_NAME, llx, lly, urx, ury, {signal_list}
        set parts [split $line ","]
        
        if {[llength $parts] < 6} {
            puts "WARNING: Line $line_num has incorrect format, skipping"
            continue
        }
        
        set region_name [string trim [lindex $parts 0]]
        set llx [string trim [lindex $parts 1]]
        set lly [string trim [lindex $parts 2]]
        set urx [string trim [lindex $parts 3]]
        set ury [string trim [lindex $parts 4]]
        
        # Extract signal list (everything after 5th comma)
        set signal_part [join [lrange $parts 5 end] ","]
        set signal_part [string trim $signal_part]
        
        # Parse signal list (should be in curly braces)
        if {[regexp {\{([^}]*)\}} $signal_part match signals]} {
            set signal_list [split $signals]
        } else {
            puts "WARNING: Line $line_num has invalid signal list format, skipping"
            continue
        }
        
        # Validate coordinates
        if {![string is double $llx] || ![string is double $lly] || 
            ![string is double $urx] || ![string is double $ury]} {
            puts "WARNING: Line $line_num has invalid coordinates, skipping"
            continue
        }
        
        # Add region to list
        lappend regions [list $region_name $llx $lly $urx $ury $signal_list]
        puts "Parsed region: $region_name with [llength $signal_list] signals"
    }
    
    close $fp
    return $regions
}

# ============================================================================
# PHASE 1: FIND ALL ANALOG INSTANCES AND THEIR BOUNDING BOXES
# ============================================================================

puts "\n=========================================="
puts "PHASE 1: Analyzing Analog Macro Instances"
puts "=========================================="

set analog_instances [get_analog_instances $ANALOG_MASTER]
if {[llength $analog_instances] == 0} {
    puts "ERROR: Cannot proceed without analog instances"
    exit 1
}

# Store instance info
set analog_info_list {}
set exclusion_zones {}

foreach inst $analog_instances {
    set inst_name [dbGet $inst.name]
    set bbox [get_instance_bbox $inst]
    lassign $bbox llx lly urx ury
    
    puts "\nInstance: $inst_name"
    puts "  Bounding box: ($llx, $lly) to ($urx, $ury)"
    puts "  Size: [expr {$urx - $llx}] x [expr {$ury - $lly}] μm"
    
    # Store info
    lappend analog_info_list [list $inst_name $inst $bbox]
    
    # Add to exclusion zones (expanded by 1 pitch for ground ring)
    set expanded_bbox [expand_bbox $bbox $GROUND_RING_OFFSET]
    lappend exclusion_zones $expanded_bbox
}

# ============================================================================
# PHASE 2: PLACE BUMPS ON ANALOG PINS
# ============================================================================

puts "\n=========================================="
puts "PHASE 2: Placing Bumps on Analog Pins"
puts "=========================================="

set analog_bump_count 0

foreach info $analog_info_list {
    lassign $info inst_name inst_obj bbox
    puts "\nProcessing pins for instance: $inst_name"
    
    # Get all pins (terms) of this instance
    set pins [dbGet $inst_obj.instTerms]
    
    if {[llength $pins] == 0} {
        puts "  WARNING: No pins found for $inst_name"
        continue
    }
    
    puts "  Found [llength $pins] pins"
    
    foreach pin $pins {
        set pin_name [dbGet $pin.name]
        set net_name [dbGet $pin.net.name]
        
        # Get pin center location
        set pin_shapes [dbGet $pin.pin.shapes]
        if {$pin_shapes == "" || $pin_shapes == "0x0"} {
            puts "    WARNING: No shapes for pin $pin_name, skipping"
            continue
        }
        
        # Calculate pin center from all shapes
        set all_x {}
        set all_y {}
        
        foreach shape $pin_shapes {
            set shape_pts [dbGet $shape.points]
            if {$shape_pts != "" && $shape_pts != "0x0"} {
                foreach pt $shape_pts {
                    lassign $pt x y
                    lappend all_x $x
                    lappend all_y $y
                }
            }
        }
        
        if {[llength $all_x] == 0} {
            puts "    WARNING: No valid coordinates for pin $pin_name, skipping"
            continue
        }
        
        # Calculate center point
        set min_x [lindex [lsort -real $all_x] 0]
        set max_x [lindex [lsort -real $all_x] end]
        set min_y [lindex [lsort -real $all_y] 0]
        set max_y [lindex [lsort -real $all_y] end]
        
        set center_x [expr {($min_x + $max_x) / 2.0}]
        set center_y [expr {($min_y + $max_y) / 2.0}]
        
        # Create bump name
        set bump_name "${inst_name}_${pin_name}_BUMP"
        
        # Create bump at pin location
        if {[create_bump_at_location $center_x $center_y $bump_name $BUMP_CELL]} {
            puts "    Created bump: $bump_name at ($center_x, $center_y) for pin $pin_name"
            
            # Assign bump to net
            if {$net_name != "" && $net_name != "0x0"} {
                assignBump -net $net_name -bump $bump_name
                puts "      Assigned to net: $net_name"
            } else {
                puts "      WARNING: Pin $pin_name not connected to any net"
            }
            
            incr analog_bump_count
        }
    }
}

puts "\nPhase 2 Summary: Created $analog_bump_count bumps on analog pins"

# Fix all analog bumps to prevent movement
select_bump -pattern "*_BUMP"
setBumpFixed -selected
deselect_bump -all

# ============================================================================
# PHASE 3: CREATE GROUND RING AROUND EACH ANALOG MACRO
# ============================================================================

puts "\n=========================================="
puts "PHASE 3: Creating Ground Rings Around Analog Macros"
puts "=========================================="

set ground_ring_bumps {}

foreach info $analog_info_list {
    lassign $info inst_name inst_obj bbox
    lassign $bbox llx lly urx ury
    
    puts "\nCreating ground ring for: $inst_name"
    puts "  Macro bbox: ($llx, $lly) to ($urx, $ury)"
    
    # Calculate ground ring boundary (1 row = 1 pitch offset)
    set ring_llx [expr {$llx - $GROUND_RING_OFFSET}]
    set ring_lly [expr {$lly - $GROUND_RING_OFFSET}]
    set ring_urx [expr {$urx + $GROUND_RING_OFFSET}]
    set ring_ury [expr {$ury + $GROUND_RING_OFFSET}]
    
    puts "  Ground ring bbox: ($ring_llx, $ring_lly) to ($ring_urx, $ring_ury)"
    
    set bump_idx 0
    
    # Bottom row (left to right)
    for {set x $ring_llx} {$x <= $ring_urx} {set x [expr {$x + $BUMP_PITCH}]} {
        set bump_name "${inst_name}_GND_B_${bump_idx}"
        if {[create_bump_at_location $x $ring_lly $bump_name $BUMP_CELL]} {
            lappend ground_ring_bumps [list $bump_name $x $ring_lly $inst_name]
            incr bump_idx
        }
    }
    
    # Top row (left to right)
    for {set x $ring_llx} {$x <= $ring_urx} {set x [expr {$x + $BUMP_PITCH}]} {
        set bump_name "${inst_name}_GND_T_${bump_idx}"
        if {[create_bump_at_location $x $ring_ury $bump_name $BUMP_CELL]} {
            lappend ground_ring_bumps [list $bump_name $x $ring_ury $inst_name]
            incr bump_idx
        }
    }
    
    # Left column (bottom to top, excluding corners)
    for {set y [expr {$ring_lly + $BUMP_PITCH}]} {$y < $ring_ury} {set y [expr {$y + $BUMP_PITCH}]} {
        set bump_name "${inst_name}_GND_L_${bump_idx}"
        if {[create_bump_at_location $ring_llx $y $bump_name $BUMP_CELL]} {
            lappend ground_ring_bumps [list $bump_name $ring_llx $y $inst_name]
            incr bump_idx
        }
    }
    
    # Right column (bottom to top, excluding corners)
    for {set y [expr {$ring_lly + $BUMP_PITCH}]} {$y < $ring_ury} {set y [expr {$y + $BUMP_PITCH}]} {
        set bump_name "${inst_name}_GND_R_${bump_idx}"
        if {[create_bump_at_location $ring_urx $y $bump_name $BUMP_CELL]} {
            lappend ground_ring_bumps [list $bump_name $ring_urx $y $inst_name]
            incr bump_idx
        }
    }
    
    puts "  Created $bump_idx ground ring bumps"
}

# Assign all ground ring bumps to VSSA
puts "\nAssigning ground ring bumps to $ANALOG_GROUND_NET..."
set ground_bump_names {}
foreach bump_info $ground_ring_bumps {
    lappend ground_bump_names [lindex $bump_info 0]
}

if {[llength $ground_bump_names] > 0} {
    assignBump -net $ANALOG_GROUND_NET -bump $ground_bump_names
    puts "Assigned [llength $ground_bump_names] bumps to $ANALOG_GROUND_NET"
}

# Fix ground ring bumps
select_bump -pattern "*_GND_*"
setBumpFixed -selected
deselect_bump -all

# ============================================================================
# PHASE 4: CREATE CORE AREA BUMPS (CHECKERBOARD VDD/VSS)
# ============================================================================

puts "\n=========================================="
puts "PHASE 4: Creating Core Area Bumps"
puts "=========================================="

# Get die boundaries
set die_bbox [dbGet top.fPlan.box]
lassign $die_bbox die_llx die_lly die_urx die_ury

puts "Die boundaries: ($die_llx, $die_lly) to ($die_urx, $die_ury)"
puts "Edge spacing: $EDGE_SPACING μm"
puts "Bump pitch: $BUMP_PITCH μm"

# Calculate core bump grid boundaries
set core_llx [expr {$die_llx + $EDGE_SPACING}]
set core_lly [expr {$die_lly + $EDGE_SPACING}]
set core_urx [expr {$die_urx - $EDGE_SPACING}]
set core_ury [expr {$die_ury - $EDGE_SPACING}]

puts "Core bump area: ($core_llx, $core_lly) to ($core_urx, $core_ury)"

# Create core bumps with manual loop to implement checkerboard and exclusions
set core_bump_count 0
set core_bump_list {}
set row_num 0

for {set y $core_lly} {$y <= $core_ury} {set y [expr {$y + $BUMP_PITCH}]} {
    set col_num 0
    
    for {set x $core_llx} {$x <= $core_urx} {set x [expr {$x + $BUMP_PITCH}]} {
        
        # Check if location conflicts with analog exclusion zones
        set skip_location 0
        foreach excl_bbox $exclusion_zones {
            lassign $excl_bbox ex_llx ex_lly ex_urx ex_ury
            if {$x >= $ex_llx && $x <= $ex_urx && $y >= $ex_lly && $y <= $ex_ury} {
                set skip_location 1
                break
            }
        }
        
        if {$skip_location} {
            incr col_num
            continue
        }
        
        # Check if bump already exists at this location (from analog pins or ground ring)
        set existing_bumps [dbGet top.bumps.pt "$x $y" -p]
        if {$existing_bumps != "" && $existing_bumps != "0x0"} {
            incr col_num
            continue
        }
        
        # Determine power net based on checkerboard pattern
        set sum [expr {$row_num + $col_num}]
        if {[expr {$sum % 2}] == 0} {
            set net_name $DIGITAL_POWER_NET
            set net_type "VDD"
        } else {
            set net_name $DIGITAL_GROUND_NET
            set net_type "VSS"
        }
        
        set bump_name "CORE_${net_type}_${row_num}_${col_num}"
        
        if {[create_bump_at_location $x $y $bump_name $BUMP_CELL]} {
            assignBump -net $net_name -bump $bump_name
            lappend core_bump_list [list $bump_name $x $y]
            incr core_bump_count
        }
        
        incr col_num
    }
    
    incr row_num
}

puts "\nPhase 4 Summary: Created $core_bump_count core area bumps"

# ============================================================================
# PHASE 5: SIGNAL I/O ASSIGNMENT TO BUMPS
# ============================================================================

puts "\n=========================================="
puts "PHASE 5: Signal I/O Assignment to Bumps"
puts "=========================================="

# Check if assignment file exists, if not create template
if {![file exists $SIGNAL_ASSIGNMENT_FILE]} {
    puts "Signal assignment file not found. Creating template..."
    create_signal_assignment_template $SIGNAL_ASSIGNMENT_FILE
    puts "\nPlease edit $SIGNAL_ASSIGNMENT_FILE with your signal assignments"
    puts "Then re-run the script or source the I/O assignment section"
} else {
    puts "Reading signal assignment file: $SIGNAL_ASSIGNMENT_FILE"
    
    # Parse assignment file
    set regions [parse_signal_assignment_file $SIGNAL_ASSIGNMENT_FILE]
    
    if {[llength $regions] == 0} {
        puts "WARNING: No valid regions found in assignment file"
    } else {
        puts "Found [llength $regions] regions with signal assignments"
        
        # Get list of available (unassigned) core bumps
        set available_bumps {}
        foreach bump_info $core_bump_list {
            set bump_name [lindex $bump_info 0]
            set bump_obj [dbGet top.bumps.name $bump_name -p]
            if {$bump_obj == "" || $bump_obj == "0x0"} {continue}
            
            set net [dbGet $bump_obj.net.name]
            # Only consider power/ground bumps as "taken", others are available
            if {$net == $DIGITAL_POWER_NET || $net == $DIGITAL_GROUND_NET} {
                continue
            }
            lappend available_bumps $bump_name
        }
        
        puts "Available bumps for signal assignment: [llength $available_bumps]"
        
        # Process each region
        set total_assigned 0
        
        foreach region $regions {
            lassign $region region_name llx lly urx ury signal_list
            
            puts "\nProcessing region: $region_name"
            puts "  Coordinates: ($llx, $lly) to ($urx, $ury)"
            puts "  Signals: [llength $signal_list]"
            
            set region_bbox [list $llx $lly $urx $ury]
            set assigned_in_region 0
            
            foreach signal $signal_list {
                # Get signal direction
                set direction [get_signal_direction $signal]
                
                # Get appropriate I/O cell
                set io_cell [get_io_cell_for_signal $direction \
                    $IO_INPUT_CELL $IO_OUTPUT_CELL $IO_BIDIR_CELL]
                
                # Find center of region as starting point
                set center_x [expr {($llx + $urx) / 2.0}]
                set center_y [expr {($lly + $ury) / 2.0}]
                
                # Find nearest available bump in region
                set assigned_bump [find_nearest_bump $center_x $center_y \
                    $region_bbox $available_bumps]
                
                if {$assigned_bump == ""} {
                    puts "    WARNING: No available bump found for signal $signal"
                    continue
                }
                
                # Remove from available list
                set idx [lsearch $available_bumps $assigned_bump]
                if {$idx >= 0} {
                    set available_bumps [lreplace $available_bumps $idx $idx]
                }
                
                # Assign bump to signal
                assignBump -net $signal -bump $assigned_bump
                puts "    Assigned signal $signal to bump $assigned_bump"
                
                # Place I/O cell near bump
                if {[place_io_cell_near_bump $signal $assigned_bump \
                    $io_cell $IO_PLACEMENT_OFFSET]} {
                    incr assigned_in_region
                    incr total_assigned
                }
            }
            
            puts "  Region summary: Assigned $assigned_in_region signals"
        }
        
        puts "\nPhase 5 Summary: Assigned $total_assigned signal I/Os to bumps"
    }
}

# ============================================================================
# PHASE 6: VERIFICATION AND REPORTING
# ============================================================================

puts "\n=========================================="
puts "PHASE 6: Verification and Reporting"
puts "=========================================="

# Check bump pitch
puts "\nChecking bump pitch..."
checkBump -bumpPitch $BUMP_PITCH

# Count bumps by type
set total_bumps [llength [dbGet top.bumps.name]]
set vdd_bumps [llength [dbGet top.bumps.net.name $DIGITAL_POWER_NET -p]]
set vss_bumps [llength [dbGet top.bumps.net.name $DIGITAL_GROUND_NET -p]]
set vdda_bumps [llength [dbGet top.bumps.net.name $ANALOG_POWER_NET -p]]
set vssa_bumps [llength [dbGet top.bumps.net.name $ANALOG_GROUND_NET -p]]

# Count signal bumps (not power/ground)
set signal_bumps 0
foreach bump [dbGet top.bumps] {
    set net [dbGet $bump.net.name]
    if {$net != "" && $net != "0x0" && \
        $net != $DIGITAL_POWER_NET && $net != $DIGITAL_GROUND_NET && \
        $net != $ANALOG_POWER_NET && $net != $ANALOG_GROUND_NET} {
        incr signal_bumps
    }
}

set unassigned [llength [dbGet top.bumps.net.name "" -p]]

# Count I/O cells
set io_cells [llength [dbGet top.insts.name "IO_*" -p]]

puts "\n=========================================="
puts "BUMP PLACEMENT SUMMARY"
puts "=========================================="
puts "Total bumps created:        $total_bumps"
puts ""
puts "Analog bumps (on pins):     $analog_bump_count"
puts "Ground ring bumps (VSSA):   [llength $ground_bump_names]"
puts "Core area bumps:            $core_bump_count"
puts "Signal I/O bumps:           $signal_bumps"
puts ""
puts "By power net:"
puts "  VDD bumps:                $vdd_bumps"
puts "  VSS bumps:                $vss_bumps"
puts "  VDDA bumps:               $vdda_bumps"
puts "  VSSA bumps:               $vssa_bumps"
puts "  Unassigned:               $unassigned"
puts ""
puts "I/O Cells:"
puts "  Total I/O cells placed:   $io_cells"
puts ""
puts "Configuration used:"
puts "  Bump cell:                $BUMP_CELL"
puts "  Pitch:                    $BUMP_PITCH μm"
puts "  Edge spacing:             $EDGE_SPACING μm"
puts "  I/O placement offset:     $IO_PLACEMENT_OFFSET μm"
puts "=========================================="

# Check for unassigned bumps
if {$unassigned > 0} {
    puts "\nWARNING: Found $unassigned unassigned bumps"
    puts "Unassigned bump names:"
    foreach bump [dbGet top.bumps.net.name "" -p] {
        puts "  - [dbGet $bump.name]"
    }
}

# Generate detailed report file
set report_file "bump_placement_report.rpt"
set fp [open $report_file w]

puts $fp "=========================================="
puts $fp "BUMP PLACEMENT DETAILED REPORT"
puts $fp "=========================================="
puts $fp "Date: [clock format [clock seconds]]"
puts $fp ""
puts $fp "Design: [dbGet top.name]"
puts $fp "Bump cell: $BUMP_CELL"
puts $fp "Pitch: $BUMP_PITCH μm"
puts $fp "Edge spacing: $EDGE_SPACING μm"
puts $fp ""
puts $fp "Total bumps: $total_bumps"
puts $fp "Total I/O cells: $io_cells"
puts $fp ""
puts $fp "=========================================="
puts $fp "BUMP LISTING"
puts $fp "=========================================="
puts $fp [format "%-40s %-20s %-15s %-15s %-10s" \
    "Bump Name" "Net" "X (μm)" "Y (μm)" "Type"]
puts $fp [string repeat "=" 100]

foreach bump [dbGet top.bumps] {
    set name [dbGet $bump.name]
    set net [dbGet $bump.net.name]
    if {$net == "" || $net == "0x0"} {set net "UNASSIGNED"}
    lassign [dbGet $bump.pt] x y
    
    # Determine type
    if {[string match "*_GND_*" $name]} {
        set type "GND_RING"
    } elseif {[string match "*_BUMP" $name]} {
        set type "ANALOG"
    } elseif {[string match "CORE_VDD_*" $name]} {
        set type "PWR_CORE"
    } elseif {[string match "CORE_VSS_*" $name]} {
        set type "GND_CORE"
    } else {
        set type "SIGNAL"
    }
    
    puts $fp [format "%-40s %-20s %-15.2f %-15.2f %-10s" \
        $name $net $x $y $type]
}

puts $fp ""
puts $fp "=========================================="
puts $fp "I/O CELL LISTING"
puts $fp "=========================================="
puts $fp [format "%-30s %-20s %-15s %-15s" \
    "Cell Name" "Master" "X (μm)" "Y (μm)"]
puts $fp [string repeat "=" 80]

foreach io_inst [dbGet top.insts.name "IO_*" -p] {
    set name [dbGet $io_inst.name]
    set master [dbGet $io_inst.cell.name]
    lassign [dbGet $io_inst.pt] x y
    puts $fp [format "%-30s %-20s %-15.2f %-15.2f" $name $master $x $y]
}

close $fp
puts "\nDetailed report written to: $report_file"

# Save design state
puts "\nSaving design state..."
saveDesign bump_placement_complete.enc

puts "\n=========================================="
puts "BUMP PLACEMENT COMPLETED SUCCESSFULLY"
puts "=========================================="
puts ""
puts "Next steps:"
puts "1. Review bump placement in GUI"
puts "2. Verify I/O cell placement"
puts "3. Run: fcroute -type power (route power bumps first)"
puts "4. Run: fcroute -type signal (route signal bumps)"
puts "5. Run: verifyConnectivity -type all"
puts "=========================================="
