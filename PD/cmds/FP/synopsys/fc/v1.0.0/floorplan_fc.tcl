#!/usr/bin/env tclsh
# CBFlow FP floorplan - Synopsys Fusion Compiler
# FC-RM: create_floorplan.tcl -- Initialize floorplan, place macros, insert
#         boundary/tap cells, place pins, check floorplan
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "floorplan"
set NODE_NAME "floorplan1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, current_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for floorplan..."
    global fp flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

    # Open library and set current block
    handle_info "Opening library: $lib_name"
    open_lib $lib_name

    # Copy from import_design stage
    handle_info "Creating working copy: ${design_name}/floorplan"
    copy_block -from ${design_name}/import_design_done -to ${design_name}/floorplan
    current_block ${design_name}/floorplan
    link_block

    set cell_count [sizeof_collection [get_cells -hierarchical]]
    handle_info "Design loaded for floorplan: $cell_count cells"
}

# ==============================================================================
# flow_proc: initialize_floorplan
# FC-RM: initialize_floorplan with die/core area or utilization
# ==============================================================================
flow_proc initialize_floorplan {
    handle_info "Initializing floorplan..."
    global fp tech

    # Initialize floorplan with die area and core area
    if {[info exists fp(common,die_area)] && $fp(common,die_area) ne "" && [info exists fp(common,core_area)] && $fp(common,core_area) ne ""} {
        handle_info "Initializing floorplan with die: $fp(common,die_area), core: $fp(common,core_area)"
        initialize_floorplan \
            -die_area $fp(common,die_area) \
            -core_area $fp(common,core_area)
    } elseif {[info exists fp(common,core_utilization)] && $fp(common,core_utilization) ne ""} {
        set core_offset {5 5 5 5}
        if {[info exists fp(common,core_offset)] && $fp(common,core_offset) ne ""} {
            set core_offset $fp(common,core_offset)
        }
        handle_info "Initializing floorplan with utilization: $fp(common,core_utilization)"
        initialize_floorplan \
            -core_utilization $fp(common,core_utilization) \
            -core_offset $core_offset
    } else {
        handle_info "Initializing floorplan with default utilization 0.7"
        initialize_floorplan -core_utilization 0.7
    }

    # Read floorplan DEF if an existing floorplan is provided
    if {[info exists fp(common,input_def)] && $fp(common,input_def) ne ""} {
        if {[file exists $fp(common,input_def)]} {
            handle_info "Reading floorplan DEF: $fp(common,input_def)"
            read_def $fp(common,input_def)
        } else {
            handle_warning "DEF file not found: $fp(common,input_def)"
        }
    }

    # Source floorplan TCL if provided
    if {[info exists fp(common,fp_tcl)] && $fp(common,fp_tcl) ne "" && [file exists $fp(common,fp_tcl)]} {
        handle_info "Sourcing floorplan TCL: $fp(common,fp_tcl)"
        source -e $fp(common,fp_tcl)
    }

    handle_info "Floorplan initialization completed"
}

# ==============================================================================
# flow_proc: place_macros
# FC-RM: create_placement -floorplan -congestion -timing_driven
# ==============================================================================
flow_proc place_macros {
    handle_info "Placing macros..."
    global fp

    # Apply macro placement constraints if defined
    if {[info exists fp(common,macro_constraints_file)] && $fp(common,macro_constraints_file) ne ""} {
        if {[file exists $fp(common,macro_constraints_file)]} {
            handle_info "Sourcing macro constraints: $fp(common,macro_constraints_file)"
            source -e $fp(common,macro_constraints_file)
        }
    }

    # Check for hard macros
    set macros [get_cells -hierarchical -filter "is_hard_macro == true"]
    if {[sizeof_collection $macros] > 0} {
        handle_info "Found [sizeof_collection $macros] macros to place"

        # Set keepout margins around macros
        if {[info exists fp(common,macro_keepout)] && $fp(common,macro_keepout) ne ""} {
            set_macro_constraints -keepout $fp(common,macro_keepout) $macros
        } else {
            set_macro_constraints -keepout {5 5 5 5} $macros
        }

        # Set macro orientation preferences
        if {[info exists fp(common,macro_orientations)] && $fp(common,macro_orientations) ne ""} {
            foreach {macro_pat orient} $fp(common,macro_orientations) {
                set_macro_constraints -orientation $orient [get_cells $macro_pat]
            }
        }

        # Run automatic macro placement with congestion and timing awareness
        handle_info "Running create_placement -floorplan -congestion -timing_driven..."
        create_placement -floorplan -congestion -timing_driven

        # Report macro placement
        redirect -file $::REPORTS_DIR/macro_placement.rpt {
            report_placement -type macro
        }
    } else {
        handle_info "No hard macros found in design -- skipping macro placement"
    }

    handle_info "Macro placement completed"
}

# ==============================================================================
# flow_proc: insert_boundary_cells
# FC-RM: create_boundary_cells for endcap and corner cells
# ==============================================================================
flow_proc insert_boundary_cells {
    handle_info "Inserting boundary cells..."
    global fp tech

    # Insert boundary (endcap) cells
    if {[info exists fp(common,boundary_cell)] && $fp(common,boundary_cell) ne ""} {
        handle_info "Inserting boundary cells: $fp(common,boundary_cell)"
        create_boundary_cells -prefix BNDRY -left_boundary_cell $fp(common,boundary_cell) -right_boundary_cell $fp(common,boundary_cell)
    } elseif {[info exists tech(endcap_cell)] && $tech(endcap_cell) ne ""} {
        handle_info "Inserting boundary cells from tech: $tech(endcap_cell)"
        create_boundary_cells -prefix BNDRY -left_boundary_cell $tech(endcap_cell) -right_boundary_cell $tech(endcap_cell)
    } else {
        handle_info "No boundary cell specified -- skipping"
    }

    # Insert corner cells if specified
    if {[info exists fp(common,corner_cell)] && $fp(common,corner_cell) ne ""} {
        handle_info "Inserting corner cells: $fp(common,corner_cell)"
        create_boundary_cells -prefix CORNER -corner_boundary_cell $fp(common,corner_cell)
    }

    handle_info "Boundary cells inserted"
}

# ==============================================================================
# flow_proc: insert_tap_cells
# FC-RM: create_tap_cells for well tie connections
# ==============================================================================
flow_proc insert_tap_cells {
    handle_info "Inserting tap cells..."
    global fp tech

    # Determine tap cell and distance
    set tap_cell ""
    set tap_distance 30

    if {[info exists fp(common,tap_cell)] && $fp(common,tap_cell) ne ""} {
        set tap_cell $fp(common,tap_cell)
    } elseif {[info exists tech(tap_cell)] && $tech(tap_cell) ne ""} {
        set tap_cell $tech(tap_cell)
    }

    if {[info exists fp(common,tap_distance)] && $fp(common,tap_distance) ne ""} {
        set tap_distance $fp(common,tap_distance)
    }

    if {$tap_cell ne ""} {
        handle_info "Inserting tap cells: $tap_cell (distance: $tap_distance)"
        create_tap_cells -lib_cell $tap_cell -distance $tap_distance -prefix TAP
    } else {
        handle_info "No tap cell specified -- skipping"
    }

    handle_info "Tap cell insertion completed"
}

# ==============================================================================
# flow_proc: place_pins_initial
# FC-RM: place_pins -self for initial pin placement
# ==============================================================================
flow_proc place_pins_initial {
    handle_info "Running initial pin placement..."
    global fp

    # Apply pin placement constraints from file if specified
    if {[info exists fp(common,pin_placement_file)] && $fp(common,pin_placement_file) ne ""} {
        if {[file exists $fp(common,pin_placement_file)]} {
            handle_info "Sourcing pin placement: $fp(common,pin_placement_file)"
            source -e $fp(common,pin_placement_file)
        }
    }

    # Set pin layer constraints
    if {[info exists fp(common,pin_metal_layer)] && $fp(common,pin_metal_layer) ne ""} {
        set_pin_constraints -layers $fp(common,pin_metal_layer) [get_ports *]
    }

    # Run automatic pin placement
    handle_info "Running place_pins -self..."
    place_pins -self

    # Report pin placement
    redirect -file $::REPORTS_DIR/pin_placement_initial.rpt {
        report_port_placement
    }

    handle_info "Initial pin placement completed"
}

# ==============================================================================
# flow_proc: check_floorplan
# FC-RM: check_design -checks dp_pre_floorplan, check_pin_placement
# ==============================================================================
flow_proc check_floorplan {
    handle_info "Running floorplan checks..."
    global fp

    # Run DP pre-floorplan checks
    handle_info "Running check_design -checks dp_pre_floorplan..."
    redirect -file $::REPORTS_DIR/check_design_dp_pre_floorplan.rpt {
        check_design -checks dp_pre_floorplan
    }

    # Check pin placement
    handle_info "Running check_pin_placement..."
    redirect -file $::REPORTS_DIR/check_pin_placement.rpt {
        check_pin_placement
    }

    # Check legality
    redirect -file $::REPORTS_DIR/check_legality.rpt {
        check_legality
    }

    # Report utilization
    redirect -file $::REPORTS_DIR/utilization.rpt {
        report_utilization
    }

    # Report design summary
    redirect -file $::REPORTS_DIR/design_summary.rpt {
        report_design -summary
    }

    handle_info "Floorplan checks completed"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_lib, save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving floorplan block..."
    global fp flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

    save_lib -all
    save_block
    save_block -as ${lib_name}:${design_name}/floorplan_done

    handle_info "Floorplan block saved: ${design_name}/floorplan_done"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, report_timing, report_congestion
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating floorplan reports..."
    global fp

    file mkdir "$::REPORTS_DIR"

    set max_paths [expr {[info exists fp(analysis,max_paths)] ? $fp(analysis,max_paths) : 50}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_congestion.rpt {
        report_congestion -routing_stage global
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Floorplan reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.floorplan.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
