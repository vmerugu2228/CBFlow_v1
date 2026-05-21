#!/usr/bin/env tclsh
# CBFlow FCFP create_floorplan - Synopsys Fusion Compiler (FC-RM Y-2026.03)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "create_floorplan"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for create_floorplan..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(create_floorplan,from_label)] ? $fcfp(create_floorplan,from_label) : "init_compile"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/create_floorplan
    current_block ${design_name}/create_floorplan
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: initialize_floorplan
# FC-RM: initialize_floorplan with die/core area or utilization
# ==============================================================================
flow_proc initialize_floorplan {
    handle_info "Initializing floorplan..."
    global fcfp tech

    if {[info exists fcfp(floorplan,core_utilization)] && $fcfp(floorplan,core_utilization) ne ""} {
        set fp_cmd "initialize_floorplan -core_utilization $fcfp(floorplan,core_utilization)"
        if {[info exists fcfp(floorplan,core_offset)] && $fcfp(floorplan,core_offset) ne ""} {
            append fp_cmd " -core_offset $fcfp(floorplan,core_offset)"
        }
        if {[info exists fcfp(floorplan,core_aspect_ratio)] && $fcfp(floorplan,core_aspect_ratio) ne ""} {
            append fp_cmd " -core_aspect_ratio $fcfp(floorplan,core_aspect_ratio)"
        }
        handle_info "Running: $fp_cmd"
        eval $fp_cmd
    } elseif {[info exists fcfp(floorplan,die_area)] && $fcfp(floorplan,die_area) ne ""} {
        set fp_cmd "initialize_floorplan -die_area {$fcfp(floorplan,die_area)}"
        if {[info exists fcfp(floorplan,core_area)] && $fcfp(floorplan,core_area) ne ""} {
            append fp_cmd " -core_area {$fcfp(floorplan,core_area)}"
        }
        handle_info "Running: $fp_cmd"
        eval $fp_cmd
    } else {
        handle_info "No floorplan dimensions specified; using auto-computed floorplan"
        initialize_floorplan
    }

    # Source track creation file
    if {[info exists fcfp(floorplan,track_file)] && [file exists $fcfp(floorplan,track_file)]} {
        source -e $fcfp(floorplan,track_file)
    }

    # Check design pre-floorplan
    redirect -file $::REPORTS_DIR/check_design.dp_pre_floorplan {
        check_design -checks dp_pre_floorplan
    }

    # Source physical constraints (macro pre-placement, blockages, voltage areas)
    if {[info exists fcfp(floorplan,physical_constraints)] && [file exists $fcfp(floorplan,physical_constraints)]} {
        source -e $fcfp(floorplan,physical_constraints)
        handle_info "Physical constraints applied"
    }

    handle_info "Floorplan initialized"
}

# ==============================================================================
# flow_proc: place_macros
# FC-RM: Macro placement with congestion/timing-driven options
# ==============================================================================
flow_proc place_macros {
    handle_info "Placing macros..."
    global fcfp

    if {[info exists fcfp(floorplan,macro_constraints)] && [file exists $fcfp(floorplan,macro_constraints)]} {
        source -e $fcfp(floorplan,macro_constraints)
    }

    set all_macros [get_cells -quiet -physical_context -filter "design_type == macro"]
    if {[sizeof_collection $all_macros] > 0} {
        report_macro_constraints -allowed_orientations -preferred_location \
            -alignment_grid -align_pins_to_tracks $all_macros \
            > $::REPORTS_DIR/report_macro_constraints.rpt

        set_app_option -name plan.macro.macro_place_only -value true
        set cmd_options "-floorplan"

        if {[info exists fcfp(floorplan,congestion_driven)] && $fcfp(floorplan,congestion_driven) ne ""} {
            set_app_option -name plan.place.congestion_driven_mode -value $fcfp(floorplan,congestion_driven)
            set cmd_options "$cmd_options -congestion"
        }
        if {[info exists fcfp(floorplan,timing_driven)] && $fcfp(floorplan,timing_driven) ne ""} {
            set_app_option -name plan.place.timing_driven_mode -value $fcfp(floorplan,timing_driven)
            set cmd_options "$cmd_options -timing_driven"
        }

        handle_info "Running: create_placement $cmd_options"
        eval create_placement $cmd_options

        report_placement -physical_hierarchy_violations all \
            -wirelength all -hard_macro_overlap -verbose high \
            > $::REPORTS_DIR/report_macro_placement.rpt

        set_attribute $all_macros status "fixed"
        reset_placement
    } else {
        handle_info "No macros found to place"
    }

    handle_info "Macro placement completed"
}

# ==============================================================================
# flow_proc: insert_boundary_cells
# FC-RM: Boundary cell insertion
# ==============================================================================
flow_proc insert_boundary_cells {
    handle_info "Inserting boundary cells..."
    global fcfp tech

    if {[info exists fcfp(floorplan,boundary_cell_script)] && [file exists $fcfp(floorplan,boundary_cell_script)]} {
        source -e $fcfp(floorplan,boundary_cell_script)
    } elseif {[info exists tech(cells,boundary)] && $tech(cells,boundary) ne ""} {
        create_boundary_cells -left_boundary_cell $tech(cells,boundary) \
            -right_boundary_cell $tech(cells,boundary)
        handle_info "Boundary cells inserted: $tech(cells,boundary)"
    } else {
        handle_info "No boundary cell configuration; skipping"
    }

    redirect -file $::REPORTS_DIR/check_floorplan_rules.boundary {
        check_floorplan_rules
    }

    handle_info "Boundary cell insertion completed"
}

# ==============================================================================
# flow_proc: insert_tap_cells
# FC-RM: Tap cell insertion
# ==============================================================================
flow_proc insert_tap_cells {
    handle_info "Inserting tap cells..."
    global fcfp tech

    if {[info exists fcfp(floorplan,tap_cell_script)] && [file exists $fcfp(floorplan,tap_cell_script)]} {
        source -e $fcfp(floorplan,tap_cell_script)
    } elseif {[info exists tech(cells,well_tap)] && $tech(cells,well_tap) ne ""} {
        set tap_distance "30"
        if {[info exists tech(cells,well_tap_distance)]} {
            set tap_distance $tech(cells,well_tap_distance)
        }
        create_tap_cells -lib_cell $tech(cells,well_tap) -distance $tap_distance
        handle_info "Tap cells inserted: $tech(cells,well_tap) (distance=$tap_distance)"
    } else {
        handle_info "No tap cell configuration; skipping"
    }

    redirect -file $::REPORTS_DIR/check_floorplan_rules.tap {
        check_floorplan_rules
    }

    handle_info "Tap cell insertion completed"
}

# ==============================================================================
# flow_proc: check_floorplan
# FC-RM: check_design -checks dp_floorplan_rules, place_pins -self
# ==============================================================================
flow_proc check_floorplan {
    handle_info "Checking floorplan..."
    global fcfp

    redirect -file $::REPORTS_DIR/check_design.dp_floorplan_rules {
        check_design -checks dp_floorplan_rules
    }
    redirect -file $::REPORTS_DIR/check_floorplan_rules.final {
        check_floorplan_rules
    }

    # Initial pin placement for downstream stages
    if {[info exists fcfp(floorplan,place_pins)] && $fcfp(floorplan,place_pins)} {
        place_pins -self
        handle_info "Initial pin placement done"
    }

    handle_info "Floorplan checks completed"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract for sub-blocks
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts..."
    global fcfp

    if {[info exists fcfp(create_abstract,enable)] && $fcfp(create_abstract,enable)} {
        create_abstract -read_only
        handle_info "Abstracts created"
    } else {
        create_abstract
        handle_info "Abstracts created (default)"
    }
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving create_floorplan block..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/create_floorplan
    handle_info "Block saved: ${design_name}/create_floorplan"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating create_floorplan reports..."
    global fcfp

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Create_floorplan reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
