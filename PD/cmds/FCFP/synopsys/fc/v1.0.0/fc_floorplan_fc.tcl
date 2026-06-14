#!/usr/bin/env tclsh
# CBFlow FCFP fc_floorplan - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "fc_floorplan"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
# flow_proc: initialize_floorplan
# FC-RM: Initialize floorplan with die/core area (from create_floorplan.tcl)
# ---------------------------------------------------------------------------
flow_proc initialize_floorplan {
    handle_info "Initializing floorplan..."
    global fcfp tech
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/fcfp"
    file mkdir "$::REPORTS_DIR"

    # FC-RM: Initialize floorplan using core_utilization, die_area, or core_area
    if {[info exists fcfp(floorplan,core_utilization)] && $fcfp(floorplan,core_utilization) ne ""} {
        # Utilization-based floorplan initialization
        set fp_cmd "initialize_floorplan -core_utilization $fcfp(floorplan,core_utilization)"

        if {[info exists fcfp(floorplan,core_offset)] && $fcfp(floorplan,core_offset) ne ""} {
            append fp_cmd " -core_offset $fcfp(floorplan,core_offset)"
        }
        if {[info exists fcfp(floorplan,core_aspect_ratio)] && $fcfp(floorplan,core_aspect_ratio) ne ""} {
            append fp_cmd " -core_aspect_ratio $fcfp(floorplan,core_aspect_ratio)"
        }

        puts "CBflow-info: Running $fp_cmd"
        eval $fp_cmd

    } elseif {[info exists fcfp(floorplan,die_area)] && $fcfp(floorplan,die_area) ne ""} {
        # Explicit die_area and core_area specification
        set fp_cmd "initialize_floorplan -die_area {$fcfp(floorplan,die_area)}"
        if {[info exists fcfp(floorplan,core_area)] && $fcfp(floorplan,core_area) ne ""} {
            append fp_cmd " -core_area {$fcfp(floorplan,core_area)}"
        }

        puts "CBflow-info: Running $fp_cmd"
        eval $fp_cmd

    } else {
        # Auto-compute floorplan
        handle_info "No floorplan dimensions specified; using auto-computed floorplan"
        initialize_floorplan
    }

    # FC-RM: Source track creation file if provided
    if {[info exists fcfp(floorplan,track_file)] && $fcfp(floorplan,track_file) ne ""} {
        source $fcfp(floorplan,track_file)
        handle_info "Track creation file sourced"
    }

    # FC-RM: Set technology node if configured
    if {[info exists tech(node)] && $tech(node) ne ""} {
        set_technology -node $tech(node)
        handle_info "Technology node set: $tech(node)"
    }

    # FC-RM: Check design pre-floorplan (from create_floorplan.tcl)
    redirect -file $::REPORTS_DIR/check_design.pre_floorplan \
        {check_design -checks dp_pre_floorplan}

    # FC-RM: Check floorplan rules after initialization
    redirect -file $::REPORTS_DIR/check_floorplan_rules.init \
        {check_floorplan_rules}

    # FC-RM: Source physical constraints (macro pre-placement, blockages, voltage areas)
    if {[info exists fcfp(floorplan,physical_constraints)] && $fcfp(floorplan,physical_constraints) ne ""} {
        source $fcfp(floorplan,physical_constraints)
        handle_info "Physical constraints applied"
    }

    handle_info "Floorplan initialized"
}

# ---------------------------------------------------------------------------
# flow_proc: place_macros
# FC-RM: Macro placement (from create_floorplan.tcl MACRO_PLACEMENT section)
# ---------------------------------------------------------------------------
flow_proc place_macros {
    handle_info "Placing macros..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Source auto-placement constraints
    if {[info exists fcfp(floorplan,macro_constraints)] && $fcfp(floorplan,macro_constraints) ne ""} {
        source $fcfp(floorplan,macro_constraints)
        handle_info "Macro placement constraints loaded"
    }

    set all_macros [get_cells -quiet -physical_context -filter "design_type == macro"]

    if {[sizeof_collection $all_macros] > 0} {
        # FC-RM: Report macro constraints before placement
        report_macro_constraints -allowed_orientations -preferred_location \
            -alignment_grid -align_pins_to_tracks $all_macros \
            > $::REPORTS_DIR/report_macro_constraints.rpt

        # FC-RM: Macro-only placement mode
        set_app_option -name plan.macro.macro_place_only -value true

        # FC-RM: Build placement command with optional congestion/timing
        set cmd_options "-floorplan"

        if {[info exists fcfp(floorplan,congestion_driven)] && $fcfp(floorplan,congestion_driven) ne ""} {
            set_app_option -name plan.place.congestion_driven_mode -value $fcfp(floorplan,congestion_driven)
            set cmd_options "$cmd_options -congestion"
        }
        if {[info exists fcfp(floorplan,timing_driven)] && $fcfp(floorplan,timing_driven) ne ""} {
            set_app_option -name plan.place.timing_driven_mode -value $fcfp(floorplan,timing_driven)
            set cmd_options "$cmd_options -timing_driven"
        }

        # FC-RM: Run macro placement
        puts "CBflow-info: Running create_placement $cmd_options"
        eval create_placement $cmd_options

        # FC-RM: Report placement results
        report_placement \
            -physical_hierarchy_violations all \
            -wirelength all -hard_macro_overlap \
            -verbose high > $::REPORTS_DIR/report_macro_placement.rpt

        # FC-RM: Derive preferred locations for incremental runs
        file delete -force $run_dir/results/fcfp/preferred_macro_locations.tcl
        derive_preferred_macro_locations $all_macros \
            -file $run_dir/results/fcfp/preferred_macro_locations.tcl

        # FC-RM: Fix all macros and check floorplan rules
        set_attribute $all_macros status "fixed"

        redirect -file $::REPORTS_DIR/check_floorplan_rules.macro \
            {check_floorplan_rules}

        # FC-RM: Reset stdcell placement to avoid conflicts with PG/boundary/tap insertion
        reset_placement

    } else {
        handle_info "No macros found to place"
    }

    handle_info "Macro placement completed"
}

# ---------------------------------------------------------------------------
# flow_proc: insert_tap_cells
# FC-RM: Tap cell insertion (from create_floorplan.tcl TAP_CELL section)
# ---------------------------------------------------------------------------
flow_proc insert_tap_cells {
    handle_info "Inserting tap cells..."
    global fcfp tech
    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Tap cell insertion via node-specific sidefile or config
    if {[info exists fcfp(floorplan,tap_cell_script)] && $fcfp(floorplan,tap_cell_script) ne ""} {
        # Source user-provided tap cell script
        source $fcfp(floorplan,tap_cell_script)
        handle_info "Tap cells inserted from script"
    } elseif {[info exists tech(cells,well_tap)] && $tech(cells,well_tap) ne ""} {
        # FC-RM: Insert well tap cells from technology config
        set tap_cell $tech(cells,well_tap)
        set tap_distance "30"
        if {[info exists tech(cells,well_tap_distance)]} {
            set tap_distance $tech(cells,well_tap_distance)
        }

        puts "CBflow-info: Inserting tap cell $tap_cell with max distance $tap_distance"
        create_tap_cells -lib_cell $tap_cell -distance $tap_distance

        handle_info "Tap cells inserted: $tap_cell (distance=$tap_distance)"
    } else {
        handle_info "No tap cell configuration found; skipping"
    }

    # FC-RM: Check floorplan rules after tap cell insertion
    redirect -file $::REPORTS_DIR/check_floorplan_rules.tap_cell \
        {check_floorplan_rules}

    handle_info "Tap cell insertion completed"
}

# ---------------------------------------------------------------------------
# flow_proc: insert_boundary_cells
# FC-RM: Boundary cell insertion (from create_floorplan.tcl BOUNDARY_CELL section)
# ---------------------------------------------------------------------------
flow_proc insert_boundary_cells {
    handle_info "Inserting boundary cells..."
    global fcfp tech
    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Boundary cell insertion via node-specific sidefile or config
    if {[info exists fcfp(floorplan,boundary_cell_script)] && $fcfp(floorplan,boundary_cell_script) ne ""} {
        source $fcfp(floorplan,boundary_cell_script)
        handle_info "Boundary cells inserted from script"
    } elseif {[info exists tech(cells,boundary)] && $tech(cells,boundary) ne ""} {
        puts "CBflow-info: Inserting boundary cells: $tech(cells,boundary)"
        create_boundary_cells -left_boundary_cell $tech(cells,boundary) \
            -right_boundary_cell $tech(cells,boundary)
        handle_info "Boundary cells inserted"
    } else {
        handle_info "No boundary cell configuration found; skipping"
    }

    # FC-RM: Check floorplan rules after boundary cell insertion
    redirect -file $::REPORTS_DIR/check_floorplan_rules.boundary_cell \
        {check_floorplan_rules}

    handle_info "Boundary cell insertion completed"
}

# ---------------------------------------------------------------------------
# flow_proc: save_design_block
# FC-RM: Save design block (from create_floorplan.tcl)
# ---------------------------------------------------------------------------
flow_proc save_design_block {
    handle_info "Saving design block..."
    global fcfp project

    if {[info exists fcfp(output,block_labeling)] && $fcfp(output,block_labeling) ne "" && [string is true -strict $fcfp(output,block_labeling)]} {
        if {[info exists project(top_module)] && $project(top_module) ne ""} {
            set design_name $project(top_module)
        } else {
            set design_name [get_object_name [current_design]]
        }
        puts "CBflow-info: Saving block as ${design_name}/create_floorplan"
        save_block -as ${design_name}/create_floorplan
    } else {
        save_block
    }

    handle_info "Design block saved"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_reports
# FC-RM: Floorplan summary reports
# ---------------------------------------------------------------------------
flow_proc generate_reports {
    handle_info "Generating floorplan reports..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"

    # FC-RM: Utilization report
    redirect -file $::REPORTS_DIR/utilization.rpt { report_utilization }

    # FC-RM: Overall design report
    redirect -file $::REPORTS_DIR/fc_floorplan_final.rpt { report_design }
    redirect -file $::REPORTS_DIR/fc_floorplan_physical.rpt { report_design -physical }

    # FC-RM: Check design with floorplan rules
    redirect -file $::REPORTS_DIR/check_design.dp_floorplan_rules \
        {check_design -checks dp_floorplan_rules}

    # Floorplan summary
    set fp [open "$res_dir/fc_floorplan_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "FCFP Fullchip Floorplan Summary - Fusion Compiler"
    puts $fp "Ported from FC-RM Y-2026.03 create_floorplan.tcl"
    puts $fp "Date: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Floorplan stages:"
    puts $fp "  1. Initialize floorplan (die/core area)"
    puts $fp "  2. Macro placement"
    puts $fp "  3. Tap cell insertion"
    puts $fp "  4. Boundary cell insertion"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Floorplan reports generated"
}

# ---------------------------------------------------------------------------
# flow_proc: fc_floorplan_flow
# Execute all fc_floorplan flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc fc_floorplan_flow {
    handle_info "Executing FCFP fc_floorplan flow..."
    flow_exec initialize_floorplan
    flow_exec place_macros
    flow_exec insert_tap_cells
    flow_exec insert_boundary_cells
    flow_exec save_design_block
    flow_exec generate_reports
    handle_info "FCFP fc_floorplan completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_floorplan_flow } else { puts " FCFP fc_floorplan procedures loaded" }

# Exit tool after stage completion
exit
