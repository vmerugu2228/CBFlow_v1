#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FCFP Floorplan Command File (Innovus)
# Description: Initialize floorplan, place partitions and macros, assign IOs,
#              and generate floorplan reports
# Tool: Cadence Innovus
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set FLOW_TYPE "FCFP"
set STAGE_NAME "fc_floorplan"
set NODE_NAME [cbflow_node_name]

# Generated per-node config (project + tech + flow + node + user cascade).
set config_file "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
if {![file exists $config_file]} { puts stderr "ERROR: node config not found: $config_file (run the $NODE_NAME setup subnode)"; exit 1 }
source $config_file
global fcfp project tech flow
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set WORK_DIR [cbflow_node_dir $NODE_NAME]
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting FCFP fc_floorplan stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     INITIALIZE FLOORPLAN                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc initialize_floorplan {
    global fcfp project tech flow
    handle_info "Initializing fullchip floorplan..."

    file mkdir "results/fcfp"
    file mkdir "$::REPORTS_DIR"

    # Site: fcfp(floorplan,site_name) override, else the tech site of the
    # project's track variant — tech(<project(track_variant)>,site).
    if {[info exists fcfp(floorplan,site_name)] && $fcfp(floorplan,site_name) ne ""} {
        set site_name $fcfp(floorplan,site_name)
    } else {
        set site_name [cbflow_require tech "[cbflow_require project track_variant],site"]
    }

    # Core margins (left bottom right top) — FCFP_innovus_config
    set margins [list [cbflow_require fcfp floorplan,core_margin_left] \
                      [cbflow_require fcfp floorplan,core_margin_bottom] \
                      [cbflow_require fcfp floorplan,core_margin_right] \
                      [cbflow_require fcfp floorplan,core_margin_top]]

    # Initialize floorplan using site
    if {[info exists fcfp(floorplan,die_width)] && $fcfp(floorplan,die_width) ne "" && \
        [info exists fcfp(floorplan,die_height)] && $fcfp(floorplan,die_height) ne ""} {
        # Fixed die size mode
        puts "Floorplan mode: fixed die size"
        puts "Die size: $fcfp(floorplan,die_width) x $fcfp(floorplan,die_height)"

        floorPlan -site $site_name \
            -d $fcfp(floorplan,die_width) $fcfp(floorplan,die_height) \
            {*}$margins
    } else {
        # Utilization-based mode (fcfp(floorplan,utilization/aspect_ratio))
        set util   [cbflow_require fcfp floorplan,utilization]
        set aspect [cbflow_require fcfp floorplan,aspect_ratio]
        puts "Floorplan mode: utilization-based"
        puts "Target utilization: $util"

        floorPlan -site $site_name \
            -r $aspect $util \
            {*}$margins
    }

    puts " Floorplan initialized"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     PLACE PARTITIONS                                       │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc place_partitions {
    global fcfp project tech flow
    handle_info "Placing hierarchical partitions..."

    # Place partitions/blocks from hierarchical design
    if {[info exists fcfp(floorplan,partition_list)]} {
        foreach partition $fcfp(floorplan,partition_list) {
            puts "   Placing partition: $partition"
        }
    }

    # Apply partition constraints from config (set but missing → error)
    if {[info exists fcfp(floorplan,partition_constraints_file)] && $fcfp(floorplan,partition_constraints_file) ne ""} {
        set constraint_file $fcfp(floorplan,partition_constraints_file)
        if {![file exists $constraint_file]} {
            handle_error "fcfp(floorplan,partition_constraints_file) not found: $constraint_file"
            return
        }
        puts "   Sourcing partition constraints: $constraint_file"
        source $constraint_file
    }

    # Set partition pin assignment mode
    if {[info exists fcfp(floorplan,partition_pin_mode)] && $fcfp(floorplan,partition_pin_mode) ne ""} {
        set_partition_pin_mode -mode $fcfp(floorplan,partition_pin_mode)
        puts "   Partition pin mode: $fcfp(floorplan,partition_pin_mode)"
    }

    puts " Partitions placed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     PLACE MACROS                                           │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc place_macros {
    global fcfp project tech flow
    handle_info "Placing hard macros..."

    # Apply macro placement constraints
    if {[info exists fcfp(floorplan,macro_placement_file)] && $fcfp(floorplan,macro_placement_file) ne ""} {
        set macro_file $fcfp(floorplan,macro_placement_file)
        if {![file exists $macro_file]} {
            handle_error "fcfp(floorplan,macro_placement_file) not found: $macro_file"
            return
        }
        puts "   Loading macro placement: $macro_file"
        source $macro_file
    } else {
        # Auto-place macros using Innovus macro placer
        puts "   Running automatic macro placement..."
        set halo_x [cbflow_require fcfp floorplan,macro_halo_x]
        set halo_y [cbflow_require fcfp floorplan,macro_halo_y]

        # Add halos around macros
        addHaloToBlock $halo_x $halo_y $halo_x $halo_y -allBlock
        puts "   Macro halo: ${halo_x}um x ${halo_y}um"

        # Place macros
        planDesign
    }

    # Create blockages around macros
    if {[info exists fcfp(floorplan,create_macro_blockage)] && $fcfp(floorplan,create_macro_blockage) eq "true"} {
        puts "   Creating placement blockages around macros..."
        set margin [cbflow_require fcfp floorplan,blockage_margin]
        createPlaceBlockage -type hard -name macro_blockage -inst [dbGet top.insts.name *macro*]
    }

    puts " Macros placed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     ASSIGN IO                                              │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc assign_io {
    global fcfp project tech flow
    handle_info "Assigning IO placement..."

    # Load IO constraint file if available
    if {[info exists fcfp(floorplan,io_constraint_file)] && $fcfp(floorplan,io_constraint_file) ne ""} {
        set io_file $fcfp(floorplan,io_constraint_file)
        if {![file exists $io_file]} {
            handle_error "fcfp(floorplan,io_constraint_file) not found: $io_file"
            return
        }
        puts "   Loading IO constraints: $io_file"
        loadIoFile $io_file
    } else {
        # Auto-assign IOs — pin layer/geometry from FCFP_innovus_config
        puts "   Running automatic IO assignment..."
        set pin_layer [cbflow_require fcfp floorplan,io_pin_layer]
        set pin_w     [cbflow_require fcfp floorplan,io_pin_width]
        set pin_d     [cbflow_require fcfp floorplan,io_pin_depth]
        foreach _side {Top Bottom Left Right} {
            editPin -pinWidth $pin_w -pinDepth $pin_d -fixOverlap 1 -layer $pin_layer -spreadType center -side $_side
        }
    }

    # Add IO filler cells
    if {[info exists fcfp(floorplan,io_filler_cells)] && $fcfp(floorplan,io_filler_cells) ne ""} {
        puts "   Adding IO filler cells..."
        place_io_fill -cells $fcfp(floorplan,io_filler_cells)
    }

    puts " IO assignment completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global fcfp project tech flow
    handle_info "Generating floorplan reports..."

    file mkdir "$::REPORTS_DIR"

    # Floorplan summary
    reportFloorPlan > "$::REPORTS_DIR/floorplan_summary.rpt"

    # Macro placement report
    dbGet top.insts.cell.name -u > "$::REPORTS_DIR/macro_placement.rpt"

    # Area utilization report
    report_area > "$::REPORTS_DIR/area_utilization.rpt"

    # Pin assignment report
    reportPin > "$::REPORTS_DIR/pin_assignment.rpt"

    # Generate summary file
    set summary_file "$::REPORTS_DIR/fc_floorplan_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow FCFP Floorplan Summary - Innovus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Innovus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    if {[info exists fcfp(floorplan,utilization)]} {
        puts $fp "Target utilization: $fcfp(floorplan,utilization)"
    }
    puts $fp ""
    puts $fp "Reports:"
    puts $fp "  Floorplan:    reports/fcfp/floorplan/floorplan_summary.rpt"
    puts $fp "  Macros:       reports/fcfp/floorplan/macro_placement.rpt"
    puts $fp "  Area:         reports/fcfp/floorplan/area_utilization.rpt"
    puts $fp "  Pins:         reports/fcfp/floorplan/pin_assignment.rpt"
    close $fp

    # Save floorplan result
    file copy -force -- "$::REPORTS_DIR/fc_floorplan_summary.rpt" "results/fcfp/fc_floorplan_summary.rpt"

    handle_info "  Summary: $summary_file"
    puts " Floorplan reports generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow FCFP fc_floorplan with Innovus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc fc_floorplan_flow {
    handle_info "Executing FCFP fc_floorplan flow..."
    flow_exec initialize_floorplan
    flow_exec place_partitions
    flow_exec place_macros
    flow_exec assign_io
    flow_exec generate_report
    handle_info "FCFP fc_floorplan completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_floorplan_flow } else { puts " FCFP fc_floorplan procedures loaded" }

# Exit tool after stage completion
exit
