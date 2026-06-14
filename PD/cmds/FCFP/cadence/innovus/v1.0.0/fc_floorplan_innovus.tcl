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
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/FCFP/fc_floorplan/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/fc_floorplan"
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

    # Get floorplan parameters from config
    if {[info exists fcfp(floorplan,site_name)]} {
        set site_name $fcfp(floorplan,site_name)
    } else {
        set site_name "core"
    }

    # Initialize floorplan using site
    if {[info exists fcfp(floorplan,die_width)] && [info exists fcfp(floorplan,die_height)]} {
        # Fixed die size mode
        puts "Floorplan mode: fixed die size"
        puts "Die size: $fcfp(floorplan,die_width) x $fcfp(floorplan,die_height)"

        if {[info exists fcfp(floorplan,core_margin_left)]} {
            floorPlan -site $site_name \
                -d $fcfp(floorplan,die_width) $fcfp(floorplan,die_height) \
                $fcfp(floorplan,core_margin_left) \
                $fcfp(floorplan,core_margin_bottom) \
                $fcfp(floorplan,core_margin_right) \
                $fcfp(floorplan,core_margin_top)
        } else {
            floorPlan -site $site_name \
                -d $fcfp(floorplan,die_width) $fcfp(floorplan,die_height) \
                10 10 10 10
        }
    } elseif {[info exists fcfp(floorplan,utilization)]} {
        # Utilization-based mode
        puts "Floorplan mode: utilization-based"
        puts "Target utilization: $fcfp(floorplan,utilization)"

        if {[info exists fcfp(floorplan,aspect_ratio)]} {
            set aspect $fcfp(floorplan,aspect_ratio)
        } else {
            set aspect 1.0
        }

        floorPlan -site $site_name \
            -r $aspect $fcfp(floorplan,utilization) \
            10 10 10 10
    } else {
        # Default
        puts "Floorplan mode: default utilization 0.7"
        floorPlan -site $site_name \
            -r 1.0 0.7 10 10 10 10
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

    # Apply partition constraints from config
    if {[info exists fcfp(floorplan,partition_constraints_file)]} {
        set constraint_file $fcfp(floorplan,partition_constraints_file)
        if {[file exists $constraint_file]} {
            puts "   Sourcing partition constraints: $constraint_file"
            source $constraint_file
        }
    }

    # Set partition pin assignment mode
    if {[info exists fcfp(floorplan,partition_pin_mode)]} {
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
    if {[info exists fcfp(floorplan,macro_placement_file)]} {
        set macro_file $fcfp(floorplan,macro_placement_file)
        if {[file exists $macro_file]} {
            puts "   Loading macro placement: $macro_file"
            source $macro_file
        }
    } else {
        # Auto-place macros using Innovus macro placer
        puts "   Running automatic macro placement..."
        if {[info exists fcfp(floorplan,macro_halo_x)]} {
            set halo_x $fcfp(floorplan,macro_halo_x)
            set halo_y $fcfp(floorplan,macro_halo_y)
        } else {
            set halo_x 5.0
            set halo_y 5.0
        }

        # Add halos around macros
        addHaloToBlock $halo_x $halo_y $halo_x $halo_y -allBlock
        puts "   Macro halo: ${halo_x}um x ${halo_y}um"

        # Place macros
        planDesign
    }

    # Create blockages around macros
    if {[info exists fcfp(floorplan,create_macro_blockage)] && $fcfp(floorplan,create_macro_blockage) eq "true"} {
        puts "   Creating placement blockages around macros..."
        if {[info exists fcfp(floorplan,blockage_margin)]} {
            set margin $fcfp(floorplan,blockage_margin)
        } else {
            set margin 2.0
        }
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
    if {[info exists fcfp(floorplan,io_constraint_file)]} {
        set io_file $fcfp(floorplan,io_constraint_file)
        if {[file exists $io_file]} {
            puts "   Loading IO constraints: $io_file"
            loadIoFile $io_file
        }
    } else {
        # Auto-assign IOs
        puts "   Running automatic IO assignment..."

        # Set IO filler cells
        if {[info exists fcfp(floorplan,io_filler_cells)]} {
            set io_fillers $fcfp(floorplan,io_filler_cells)
        } else {
            set io_fillers {}
        }

        # Place IO pins
        if {[info exists fcfp(floorplan,io_pin_layer)]} {
            set pin_layer $fcfp(floorplan,io_pin_layer)
        } else {
            set pin_layer "metal4"
        }
        editPin -pinWidth 0.1 -pinDepth 0.5 -fixOverlap 1 -layer $pin_layer -spreadType center -side Top
        editPin -pinWidth 0.1 -pinDepth 0.5 -fixOverlap 1 -layer $pin_layer -spreadType center -side Bottom
        editPin -pinWidth 0.1 -pinDepth 0.5 -fixOverlap 1 -layer $pin_layer -spreadType center -side Left
        editPin -pinWidth 0.1 -pinDepth 0.5 -fixOverlap 1 -layer $pin_layer -spreadType center -side Right
    }

    # Add IO filler cells
    if {[info exists fcfp(floorplan,io_filler_cells)]} {
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
