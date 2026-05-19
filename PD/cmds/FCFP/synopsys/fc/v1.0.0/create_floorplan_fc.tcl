#!/usr/bin/env tclsh
# CBFlow FCFP create_floorplan - Synopsys Fusion Compiler
# FC-RM: create_floorplan.tcl (hier) -- Floorplan initialization, macro placement,
#         boundary/tap cells, pin placement, design checks
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP create_floorplan..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FCFP/create_floorplan1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for create_floorplan..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(create_floorplan,from_label)] ? $fc(create_floorplan,from_label) : "init_compile"}]
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

    if {[info exists fc(floorplan,core_utilization)] && $fc(floorplan,core_utilization) ne ""} {
        set fp_cmd "initialize_floorplan -core_utilization $fc(floorplan,core_utilization)"
        if {[info exists fc(floorplan,core_offset)] && $fc(floorplan,core_offset) ne ""} {
            append fp_cmd " -core_offset $fc(floorplan,core_offset)"
        }
        if {[info exists fc(floorplan,core_aspect_ratio)] && $fc(floorplan,core_aspect_ratio) ne ""} {
            append fp_cmd " -core_aspect_ratio $fc(floorplan,core_aspect_ratio)"
        }
        handle_info "Running: $fp_cmd"
        eval $fp_cmd
    } elseif {[info exists fc(floorplan,die_area)] && $fc(floorplan,die_area) ne ""} {
        set fp_cmd "initialize_floorplan -die_area {$fc(floorplan,die_area)}"
        if {[info exists fc(floorplan,core_area)] && $fc(floorplan,core_area) ne ""} {
            append fp_cmd " -core_area {$fc(floorplan,core_area)}"
        }
        handle_info "Running: $fp_cmd"
        eval $fp_cmd
    } else {
        handle_info "No floorplan dimensions specified; using auto-computed floorplan"
        initialize_floorplan
    }

    # Source track creation file
    if {[info exists fc(floorplan,track_file)] && [file exists $fc(floorplan,track_file)]} {
        source -e $fc(floorplan,track_file)
    }

    # Check design pre-floorplan
    redirect -file $::REPORTS_DIR/check_design.dp_pre_floorplan {
        check_design -checks dp_pre_floorplan
    }

    # Source physical constraints (macro pre-placement, blockages, voltage areas)
    if {[info exists fc(floorplan,physical_constraints)] && [file exists $fc(floorplan,physical_constraints)]} {
        source -e $fc(floorplan,physical_constraints)
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

    if {[info exists fc(floorplan,macro_constraints)] && [file exists $fc(floorplan,macro_constraints)]} {
        source -e $fc(floorplan,macro_constraints)
    }

    set all_macros [get_cells -quiet -physical_context -filter "design_type == macro"]
    if {[sizeof_collection $all_macros] > 0} {
        report_macro_constraints -allowed_orientations -preferred_location \
            -alignment_grid -align_pins_to_tracks $all_macros \
            > $::REPORTS_DIR/report_macro_constraints.rpt

        set_app_option -name plan.macro.macro_place_only -value true
        set cmd_options "-floorplan"

        if {[info exists fc(floorplan,congestion_driven)] && $fc(floorplan,congestion_driven) ne ""} {
            set_app_option -name plan.place.congestion_driven_mode -value $fc(floorplan,congestion_driven)
            set cmd_options "$cmd_options -congestion"
        }
        if {[info exists fc(floorplan,timing_driven)] && $fc(floorplan,timing_driven) ne ""} {
            set_app_option -name plan.place.timing_driven_mode -value $fc(floorplan,timing_driven)
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

    if {[info exists fc(floorplan,boundary_cell_script)] && [file exists $fc(floorplan,boundary_cell_script)]} {
        source -e $fc(floorplan,boundary_cell_script)
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

    if {[info exists fc(floorplan,tap_cell_script)] && [file exists $fc(floorplan,tap_cell_script)]} {
        source -e $fc(floorplan,tap_cell_script)
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
    if {[info exists fc(floorplan,place_pins)] && $fc(floorplan,place_pins)} {
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

    if {[info exists fc(create_abstract,enable)] && $fc(create_abstract,enable)} {
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

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

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

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

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
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.create_floorplan.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
