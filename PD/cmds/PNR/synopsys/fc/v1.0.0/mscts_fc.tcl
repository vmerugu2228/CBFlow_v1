#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — Multi-Source Clock Tree Synthesis (MSCTS) / Multipoint CTS (MPCTS)
# Tool: Synopsys Fusion Compiler (fc_shell)
# ═══════════════════════════════════════════════════════════════════════════════
#
# WHAT THIS IS
#   The FC-RM Y-2026.03 reference flow for "Regular MSCTS" — Synopsys'
#   official term for what some teams call "Multipoint CTS" (MPCTS).
#   It builds a global clock distribution as either:
#     - htree           : H-tree from clock root → tap drivers → subtrees
#     - subtree_only    : user-driven tap insertion onto an existing mesh net
#   then performs integrated tap-assignment so per-flop subtree CTS picks
#   up the nearest tap.
#
# SOURCE
#   Ported 1:1 (logic, command names, variable names) from FC-RM Y-2026.03
#   `examples/mscts.regular.tcl`. CBflow integration is OUTSIDE the script
#   body — this file owns nothing but the MSCTS recipe, so future FC-RM
#   version bumps stay a 1:1 diff against the new RM example.
#
# WHEN TO RUN
#   Sourced AFTER initial placement, BEFORE clock_opt_cts. In FC-RM the
#   integration point is `place_opt.tcl` gated by `CTS_STYLE == "MSCTS"`.
#   We keep this file standalone for now (per user direction) — the
#   regular `cts_fc.tcl` does NOT source it. To use it interactively:
#
#     cbflow run interactive --node place1
#     fc_shell> source <CBFLOW_RUN_DIR>/setup/mscts_inputs.tcl   ;# set the MSCTS_* vars
#     fc_shell> source <FLOW_DIR>/cmds/PNR/synopsys/fc/v1.0.0/mscts_fc.tcl
#
#   Or invoke from a custom hook after place_opt completes.
#
# INPUTS (must be set BEFORE sourcing this file; canonical names from FC-RM)
#   MSCTS_CLOCK                    Clock name (or list of names)
#   MSCTS_SOURCE                   Clock root pin/port (or list)
#   MSCTS_TOPOLOGY                 "htree" | "subtree_only"
#   MSCTS_PITCH                    Tap-driver grid pitch (numeric, design units)
#   MSCTS_TAP_DRIVER_LIB_CELLS     Lib-cell list for tap drivers
#
#   htree-mode inputs (required when MSCTS_TOPOLOGY == "htree"):
#     MSCTS_HTREE_LIB_CELLS              Lib-cell list for H-tree drivers
#     MSCTS_HTREE_NDR_RULE_NAME          NDR rule for H-tree routing
#     MSCTS_HTREE_MIN_ROUTING_LAYER      Min layer for H-tree
#     MSCTS_HTREE_MAX_ROUTING_LAYER      Max layer for H-tree
#
#   subtree_only-mode inputs:
#     MSCTS_MESH_NET                     Mesh net (clock distribution net)
#     MSCTS_MESH_NET_PORT                Port driving the mesh net
#     MSCTS_MESH_NET_PORT_TRANSITION     Annotated transition at the port
#     MSCTS_MESH_NET_PORT_DELAY          Annotated delay at the port
#     MSCTS_INPUT_TRANSITION             Tap-driver input transition
#     MSCTS_NET_DELAY                    Net delay from mesh-port to tap-input
#
#   Optional (both modes):
#     MSCTS_NET                          Net to insert taps on if ≠ clock root
#     MSCTS_TAP_DRIVER_MAX_DISPLACEMENT  Max legalization displacement
#     MSCTS_TAP_BOUNDARY                 "{ll_x ll_y} {ur_x ur_y}" for tap area
#     MSCTS_MACRO_KEEPOUT                "true"|"false" — auto-keepout macros
#     TCL_USER_MESH_ANNOTATION_SCRIPT    User-provided annotation override
#
# OUTPUTS
#   - H-tree (or tap drivers) inserted into the design
#   - Tap-assignment options registered via set_multisource_clock_tap_options
#   - The subsequent clock_opt cts step picks up the tap assignment
#     automatically (no extra knob needed)
#
# ═══════════════════════════════════════════════════════════════════════════════

#### Variables related to Regular MSCTS — set these via user_config or an
#### inputs script BEFORE sourcing this file. The defaults match FC-RM's
#### example (empty == "must be set").
if {![info exists MSCTS_CLOCK]}                     { set MSCTS_CLOCK "" }
if {![info exists MSCTS_SOURCE]}                    { set MSCTS_SOURCE "" }
if {![info exists MSCTS_TOPOLOGY]}                  { set MSCTS_TOPOLOGY "htree" }
if {![info exists MSCTS_NET]}                       { set MSCTS_NET "" }
if {![info exists MSCTS_HTREE_NDR_RULE_NAME]}       { set MSCTS_HTREE_NDR_RULE_NAME "" }
if {![info exists MSCTS_HTREE_MIN_ROUTING_LAYER]}   { set MSCTS_HTREE_MIN_ROUTING_LAYER "" }
if {![info exists MSCTS_HTREE_MAX_ROUTING_LAYER]}   { set MSCTS_HTREE_MAX_ROUTING_LAYER "" }
if {![info exists MSCTS_HTREE_LIB_CELLS]}           { set MSCTS_HTREE_LIB_CELLS "" }
if {![info exists MSCTS_PITCH]}                     { set MSCTS_PITCH "100" }
if {![info exists MSCTS_TAP_DRIVER_LIB_CELLS]}      { set MSCTS_TAP_DRIVER_LIB_CELLS "" }
if {![info exists MSCTS_TAP_DRIVER_MAX_DISPLACEMENT]} { set MSCTS_TAP_DRIVER_MAX_DISPLACEMENT "" }
if {![info exists MSCTS_TAP_BOUNDARY]}              { set MSCTS_TAP_BOUNDARY "" }
if {![info exists MSCTS_MACRO_KEEPOUT]}             { set MSCTS_MACRO_KEEPOUT "false" }
if {![info exists MSCTS_MESH_NET]}                  { set MSCTS_MESH_NET "" }
if {![info exists MSCTS_MESH_NET_PORT]}             { set MSCTS_MESH_NET_PORT "" }
if {![info exists MSCTS_MESH_NET_PORT_TRANSITION]}  { set MSCTS_MESH_NET_PORT_TRANSITION "" }
if {![info exists MSCTS_MESH_NET_PORT_DELAY]}       { set MSCTS_MESH_NET_PORT_DELAY "" }
if {![info exists MSCTS_INPUT_TRANSITION]}          { set MSCTS_INPUT_TRANSITION "" }
if {![info exists MSCTS_NET_DELAY]}                 { set MSCTS_NET_DELAY "" }
if {![info exists TCL_USER_MESH_ANNOTATION_SCRIPT]} { set TCL_USER_MESH_ANNOTATION_SCRIPT "" }

# ── Input validation ────────────────────────────────────────────────────────
# Every required-input check from FC-RM. Aggregates all errors before
# bailing so the user sees the full list, not just the first miss.
if {$MSCTS_CLOCK eq ""} {
    puts "RM-error: MSCTS clock not defined."
    set rm_mscts_error 1
}
if {$MSCTS_SOURCE eq ""} {
    puts "RM-error: MSCTS clock source not defined."
    set rm_mscts_error 1
}
if {$MSCTS_PITCH eq ""} {
    puts "RM-error: MSCTS pitch not defined."
    set rm_mscts_error 1
}
if {$MSCTS_TAP_DRIVER_LIB_CELLS eq ""} {
    puts "RM-error: MSCTS tap drivers not defined."
    set rm_mscts_error 1
}
if {$MSCTS_TOPOLOGY eq "htree"} {
    if {$MSCTS_HTREE_LIB_CELLS eq ""} {
        puts "RM-error: MSCTS htree lib cells not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_HTREE_NDR_RULE_NAME eq ""} {
        puts "RM-error: MSCTS NDR rule not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_HTREE_MIN_ROUTING_LAYER eq ""} {
        puts "RM-error: MSCTS min routing layer not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_HTREE_MAX_ROUTING_LAYER eq ""} {
        puts "RM-error: MSCTS max routing layer not defined."
        set rm_mscts_error 1
    }
}
if {$MSCTS_TOPOLOGY eq "subtree_only"} {
    if {$MSCTS_INPUT_TRANSITION eq ""} {
        puts "RM-error: Input transition for tap driver not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_NET_DELAY eq ""} {
        puts "RM-error: Delay from clock source to tap driver not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_MESH_NET eq ""} {
        puts "RM-error: Mesh net not defined."
        set rm_mscts_error 1
    }
    if {$MSCTS_MESH_NET_PORT eq ""} {
        puts "RM-error: Mesh net port not defined."
        set rm_mscts_error 1
    }
}
if {[info exists rm_mscts_error]} {
    puts "RM-info: Errors encountered. There are requirements not met."
    puts "RM-info: Please check the RM-error messages in the log and correct the missing information and try it again."
    return -code error "MSCTS input validation failed"
}

# ── MV (multi-voltage) support — see FC-RM commentary ──────────────────────
# Punches ports on power-domain boundaries and merges/clones isolation /
# level-shifter cells during tap insertion. Safe to leave on for non-MV
# designs (no-op when no PG-aware constructs are present).
set_app_options -name cts.multisource.enable_full_mv_support -value true
# Required for physical-feedthrough nets and power-domain instances.
set_app_options -name opt.common.allow_physical_feedthrough -value true

# Clear dont_touch on the clock root(s) so insertion can modify the net.
foreach source $MSCTS_SOURCE {
    set_dont_touch_network -clear $source
}

mark_clock_trees -clear -dont_touch

# MSCTS needs a setup-mode scenario active. Pin the first one we find so
# the rest of the script has a known context.
set active_scenarios [get_object_name [get_scenarios -filter "setup&&active"]]
set first_active [lindex $active_scenarios 0]
current_scenario $first_active

# ── Helper procs (pitch → tap grid) ─────────────────────────────────────────
proc _mscts_width_from_bbox  {bbox} { return [expr [lindex $bbox 1 0] - [lindex $bbox 0 0]] }
proc _mscts_height_from_bbox {bbox} { return [expr [lindex $bbox 1 1] - [lindex $bbox 0 1]] }

# FC-RM rounds the column/row count to the next power of 2 so the H-tree
# stays balanced. Same table here, renamed only.
proc _mscts_next_pow2 {x} {
    puts "input number: $x"
    if {$x <=  2 && $x <   4} { puts "output number: 2";  return 2  }
    if {$x <=  4 && $x <   8} { puts "output number: 4";  return 4  }
    if {$x <=  8 && $x <  16} { puts "output number: 8";  return 8  }
    if {$x <= 16 && $x <  32} { puts "output number: 16"; return 16 }
    if {$x <= 32 && $x <  64} { puts "output number: 32"; return 32 }
    if {$x <= 64 && $x < 128} { puts "output number: 64"; return 64 }
    return 64
}

# Compute the (cols, rows) tap grid from pitch + boundary.
proc _mscts_compute_grid {pitch boundary} {
    if {$boundary ne ""} {
        set width  [_mscts_width_from_bbox  $boundary]
        set height [_mscts_height_from_bbox $boundary]
    } else {
        set bbox [get_attribute [current_design] boundary_bbox]
        set width  [lindex $bbox 1 0]
        set height [lindex $bbox 1 1]
    }
    set x [expr round($width  / ($pitch * 2.0))]
    set y [expr round($height / ($pitch * 2.0))]
    puts "DEBUG: x is $x and y is $y"
    if {$x < 1} { set x 1 }
    if {$y < 1} { set y 1 }
    puts "DEBUG: x is $x and y is $y"
    return [list $x $y]
}

# ═══════════════════════════════════════════════════════════════════════════
# Topology: htree
# Global clock tree (H-tree) + integrated tap assignment.
# ═══════════════════════════════════════════════════════════════════════════
if {$MSCTS_TOPOLOGY eq "htree"} {
    # Mark H-tree and tap-driver cells as CTS-purposed; clear dont_touch
    # so the tool may merge/split them during tap assignment.
    set_lib_cell_purpose -include cts [get_lib_cell $MSCTS_HTREE_LIB_CELLS]
    set_lib_cell_purpose -include cts [get_lib_cell $MSCTS_TAP_DRIVER_LIB_CELLS]
    set_dont_touch [get_lib_cell $MSCTS_HTREE_LIB_CELLS]      false
    set_dont_touch [get_lib_cell $MSCTS_TAP_DRIVER_LIB_CELLS] false

    # Either an explicit MSCTS_NET or the clock-source-driven net.
    if {$MSCTS_NET ne ""} {
        set load_cells [get_cells -of_objects \
                          [get_flat_pins -of_objects [get_nets $MSCTS_NET] \
                                          -filter "direction==in"]]
        set_dont_touch $load_cells false
        set_dont_touch [get_lib_cells -of_objects $load_cells] false
        set_size_only  $load_cells false
        set_placement_status placed $load_cells
        set net_driver [get_flat_cell -of_objects \
                          [get_flat_pins -filter "direction==out" \
                                          -of_objects $MSCTS_NET]]
        set net_driver_status [get_attribute [get_cells $net_driver] physical_status]
        if {$net_driver_status eq "placed"} {
            legalize_placement -cells $net_driver
        }
    } else {
        set load_cells [get_cells -of_objects \
                          [get_flat_pins -of_objects [get_nets -of_objects $MSCTS_SOURCE] \
                                          -filter "direction==in"]]
        set_dont_touch $load_cells false
        set_dont_touch [get_lib_cells -of_objects $load_cells] false
        set_size_only  $load_cells false
        set_placement_status placed $load_cells
    }

    # H-tree routing layers must be reachable from the inserted cells.
    set_app_options -name cts.multisource.enable_pin_accessibility_for_global_clock_trees -value true

    # ── STEP 1: Auto tap synthesis + global H-tree synthesis ─────────────
    lassign [_mscts_compute_grid $MSCTS_PITCH $MSCTS_TAP_BOUNDARY] _x _y
    set x_binary_row_count    [_mscts_next_pow2 $_x]
    set y_binary_column_count [_mscts_next_pow2 $_y]

    foreach clock $MSCTS_CLOCK {
        # The 2x2x2 combinatorial of optional flags FC-RM expressed as
        # nested elseifs. Same effective `set_regular_multisource_clock_tree_options`
        # call in every branch — we just append the optional args that
        # the user actually set.
        set _cmd [list set_regular_multisource_clock_tree_options -clock $clock \
                       -topology htree_only \
                       -prefix htree \
                       -tap_boxes [list $x_binary_row_count $y_binary_column_count] \
                       -htree_layers [list $MSCTS_HTREE_MIN_ROUTING_LAYER $MSCTS_HTREE_MAX_ROUTING_LAYER] \
                       -htree_routing_rule $MSCTS_HTREE_NDR_RULE_NAME \
                       -tap_lib_cells [get_lib_cells $MSCTS_TAP_DRIVER_LIB_CELLS] \
                       -htree_lib_cells [get_lib_cells $MSCTS_HTREE_LIB_CELLS]]
        if {$MSCTS_NET ne ""}                     { lappend _cmd -net $MSCTS_NET }
        if {$MSCTS_TAP_DRIVER_MAX_DISPLACEMENT ne ""} { lappend _cmd -max_displacement $MSCTS_TAP_DRIVER_MAX_DISPLACEMENT }
        eval $_cmd
    }

    # Additional pass: tap_boundary / net refinement
    foreach clock $MSCTS_CLOCK {
        if {$MSCTS_TAP_BOUNDARY ne "" && $MSCTS_NET ne ""} {
            set_regular_multisource_clock_tree_options -clock $clock \
                -topology htree_only \
                -tap_boxes [list $x_binary_row_count $y_binary_column_count] \
                -tap_boundary $MSCTS_TAP_BOUNDARY \
                -net $MSCTS_NET
        } elseif {$MSCTS_TAP_BOUNDARY ne ""} {
            set_regular_multisource_clock_tree_options -clock $clock \
                -topology htree_only \
                -tap_boxes [list $x_binary_row_count $y_binary_column_count] \
                -tap_boundary $MSCTS_TAP_BOUNDARY
        }
    }

    # Macro keepouts (only if any macros exist in the design)
    foreach clock $MSCTS_CLOCK {
        if {[sizeof_collection [get_cells -physical_context -filter design_type==macro]] > 0} {
            set gm [resize_polygons -objects [create_geo_mask -objects \
                       [get_cells -physical_context -filter design_type==macro]] -size {10}]
            set keepouts [get_attribute [get_attribute $gm poly_rects] point_list]
            if {$MSCTS_MACRO_KEEPOUT eq "true" && $MSCTS_NET ne ""} {
                set_regular_multisource_clock_tree_options -clock $clock \
                    -topology htree_only \
                    -tap_boxes [list $x_binary_row_count $y_binary_column_count] \
                    -keepouts $keepouts \
                    -net $MSCTS_NET
            } elseif {$MSCTS_MACRO_KEEPOUT eq "true"} {
                set_regular_multisource_clock_tree_options -clock $clock \
                    -topology htree_only \
                    -tap_boxes [list $x_binary_row_count $y_binary_column_count] \
                    -keepouts $keepouts
            }
        }
    }

    report_regular_multisource_clock_tree_options
    synthesize_regular_multisource_clock_trees

    # ── STEP 2: Tap-assignment settings for integrated tap assignment ────
    set active_scenarios [get_object_name [get_scenarios -filter "setup&&active"]]
    set first_active [lindex $active_scenarios 0]
    current_scenario $first_active

    update_timing
    foreach clock $MSCTS_CLOCK {
        set tap_drivers [get_pins -of_objects \
                           [get_cells -physical_context *htree_r*c*] \
                           -filter "direction==out && related_clock==$clock"]
        set_multisource_clock_tap_options -clock $clock \
            -num_taps [sizeof_collection $tap_drivers] \
            -driver_objects $tap_drivers
    }

# ═══════════════════════════════════════════════════════════════════════════
# Topology: subtree_only
# User-provided mesh net + auto tap-driver insertion. No H-tree built —
# the user owns the mesh net and its annotation.
# ═══════════════════════════════════════════════════════════════════════════
} elseif {$MSCTS_TOPOLOGY eq "subtree_only"} {
    set_dont_touch [get_lib_cell $MSCTS_TAP_DRIVER_LIB_CELLS] false
    set tap_lib_cells [get_lib_cell $MSCTS_TAP_DRIVER_LIB_CELLS]
    # Save dont_use state so we can restore it at the end of the script.
    foreach lc [get_object_name $tap_lib_cells] {
        set save_dont_use($lc) [get_attribute $lc dont_use]
    }
    set_lib_cell_purpose -include cts $tap_lib_cells
    set_attribute $tap_lib_cells dont_use false

    set load_cells [get_cells -of_objects \
                      [get_flat_pins -of_objects [get_nets $MSCTS_MESH_NET] \
                                      -filter "direction==in"]]
    set_dont_touch $load_cells false
    set_dont_touch [get_lib_cells -of_objects $load_cells] false
    set_size_only  $load_cells false
    set_placement_status placed $load_cells

    # ── STEP 1: Tap-driver insertion (no H-tree) ─────────────────────────
    lassign [_mscts_compute_grid $MSCTS_PITCH $MSCTS_TAP_BOUNDARY] x y

    # Same combinatorial as htree-mode but the command is different
    # (`create_clock_drivers` instead of `set_regular_multisource_clock_tree_options`).
    set _cmd [list create_clock_drivers \
                   -loads [get_nets $MSCTS_MESH_NET] \
                   -boxes [list $x $y] \
                   -prefix mstap \
                   -lib_cells $tap_lib_cells]
    if {$MSCTS_TAP_DRIVER_MAX_DISPLACEMENT ne ""} {
        lappend _cmd -max_displacement $MSCTS_TAP_DRIVER_MAX_DISPLACEMENT
    }
    if {$MSCTS_MACRO_KEEPOUT eq "true" && \
        [sizeof_collection [get_cells -physical_context -filter design_type==macro]] > 0} {
        set gm [resize_polygons -objects [create_geo_mask -objects \
                   [get_cells -physical_context -filter design_type==macro]] -size {10}]
        set keepouts [get_attribute [get_attribute $gm poly_rects] point_list]
        lappend _cmd -keepouts $keepouts
    }
    if {$MSCTS_TAP_BOUNDARY ne ""} { lappend _cmd -boundary $MSCTS_TAP_BOUNDARY }
    eval $_cmd

    # ── Mesh-net annotation ──────────────────────────────────────────────
    # If the user provided their own annotation script, source it. Else
    # apply the FC-RM default annotation.
    if {![rm_source -file $TCL_USER_MESH_ANNOTATION_SCRIPT -optional \
                    -print "TCL_USER_MESH_ANNOTATION_SCRIPT"]} {
        puts "RM-info: TCL_USER_MESH_ANNOTATION_SCRIPT($TCL_USER_MESH_ANNOTATION_SCRIPT) is not defined. Applying default annotation"
        set anchor [get_port $MSCTS_MESH_NET_PORT]
        # Mesh-port transition (rise/fall, max/min)
        foreach _edge {rise fall} {
            foreach _mm {max min} {
                set_annotated_transition -$_edge -$_mm $MSCTS_MESH_NET_PORT_TRANSITION $anchor
                set_annotated_delay -cell -$_edge -$_mm -from $anchor -to $anchor $MSCTS_MESH_NET_PORT_DELAY
            }
        }
        # Per-tap annotation across every scenario.
        foreach_in_collection scn [get_scenarios] {
            current_scenario $scn
            foreach_in_collection itm [get_pins -physical_context \
                                         -of_objects [get_flat_cells mstap_*] \
                                         -filter "direction==in && port_type==signal"] {
                foreach _edge {rise fall} {
                    foreach _mm {max min} {
                        set_annotated_transition -$_edge -$_mm $MSCTS_INPUT_TRANSITION $itm
                        set_annotated_delay -net -$_edge -$_mm \
                            -from $anchor -to $itm $MSCTS_NET_DELAY
                    }
                }
            }
        }
    }

    # Lock the mesh net so downstream routing/buffering leaves it alone.
    define_user_attribute -classes net -type string -one_of {true false} -name is_mesh_net
    set_attribute [get_nets $MSCTS_MESH_NET] is_mesh_net true
    set_attribute [get_nets $MSCTS_MESH_NET] physical_status locked
    set_dont_touch [get_nets $MSCTS_MESH_NET] true

    # ── STEP 2: Tap-assignment settings ──────────────────────────────────
    set active_scenarios [get_object_name [get_scenarios -filter "setup&&active"]]
    set first_active [lindex $active_scenarios 0]
    current_scenario $first_active

    update_timing
    set tap_drivers [get_pins -of_objects \
                       [get_cells -physical_context *mstap_r*c*] \
                       -filter "direction==out && related_clock==$MSCTS_CLOCK"]
    set_multisource_clock_tap_options -clock $MSCTS_CLOCK \
        -driver_objects $tap_drivers \
        -num_taps [sizeof_collection $tap_drivers]

    # Restore lib-cell state.
    set_lib_cell_purpose -exclude cts $tap_lib_cells
    set_attribute $tap_lib_cells dont_use true
    foreach lc [array names save_dont_use] {
        set_attribute [get_lib_cell $lc] dont_use $save_dont_use($lc)
    }

} else {
    puts "RM-error: Specified MSCTS_TOPOLOGY($MSCTS_TOPOLOGY) is not supported"
    return -code error "Unsupported MSCTS_TOPOLOGY: $MSCTS_TOPOLOGY"
}

puts "RM-info: MSCTS construction completed (topology=$MSCTS_TOPOLOGY)"
