#!/usr/bin/env tclsh
# CBFlow FCFP fc_post_floorplan - Synopsys Fusion Compiler | Post-floorplan analysis
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
handle_info "Starting FCFP fc_post_floorplan with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FCFP/fc_post_floorplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: run_partition_check
# Run design rule checks on partition boundaries and constraints
# ---------------------------------------------------------------------------
flow_proc run_partition_check {
    handle_info "Running partition checks..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    # Check partition boundaries
    redirect -file $::REPORTS_DIR/partition_check.rpt {
        check_design -checks {dp_constraints dp_partitions}
    }

    # Check blockage overlaps
    redirect -file $::REPORTS_DIR/overlap_check.rpt { report_placement -overlap }

    # Check bound constraints
    redirect -file $::REPORTS_DIR/bounds.rpt { report_bounds }

    # Validate keepout regions
    redirect -file $::REPORTS_DIR/keepout_margins.rpt { report_keepout_margin }

    # Check for unplaced cells
    set unplaced [get_cells -filter "is_placed==false" -quiet]
    if {[sizeof_collection $unplaced] > 0} {
        handle_warning "[sizeof_collection $unplaced] unplaced cells found"
        redirect -file $::REPORTS_DIR/unplaced_cells.rpt { report_cell $unplaced }
    } else {
        handle_info "All cells placed"
    }

    handle_info "Partition check completed"
}

# ---------------------------------------------------------------------------
# flow_proc: run_congestion
# Run congestion analysis on the floorplan
# ---------------------------------------------------------------------------
flow_proc run_congestion {
    handle_info "Running congestion analysis..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Run global route estimation for congestion
    route_global -congestion_map_only true

    # Report congestion
    redirect -file $::REPORTS_DIR/congestion.rpt { report_congestion }
    redirect -file $::REPORTS_DIR/congestion_by_layer.rpt { report_congestion -by_layer }

    # Report utilization with density map
    redirect -file $::REPORTS_DIR/utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/utilization_by_layer.rpt { report_utilization -by_layer }

    # Check for congestion hotspots
    redirect -file $::REPORTS_DIR/congestion_hotspots.rpt { report_congestion -hotspot }

    # Parse congestion for overflow
    set cong_rpt "$::REPORTS_DIR/congestion.rpt"
    if {[file exists $cong_rpt]} {
        set fp [open $cong_rpt r]
        set content [read $fp]
        close $fp
        if {[string match "*overflow*" $content]} {
            handle_warning "Congestion overflow detected - review $cong_rpt"
        } else {
            handle_info "Congestion analysis clean"
        }
    }

    handle_info "Congestion analysis completed"
}

# ---------------------------------------------------------------------------
# flow_proc: run_timing
# Run virtual route timing estimation on the floorplan
# ---------------------------------------------------------------------------
flow_proc run_timing {
    handle_info "Running floorplan timing estimation..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Run timing with virtual route
    estimate_timing

    # Setup timing
    redirect -file $::REPORTS_DIR/setup_timing.rpt {
        report_timing -delay max -max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}] -nworst 3
    }

    # Hold timing
    redirect -file $::REPORTS_DIR/hold_timing.rpt {
        report_timing -delay min -max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}] -nworst 3
    }

    # Clock tree estimation
    redirect -file $::REPORTS_DIR/clock_timing.rpt { report_clock_timing -type summary }

    # QoR summary
    redirect -file $::REPORTS_DIR/floorplan_qor.rpt { report_qor }

    # Constraint check
    redirect -file $::REPORTS_DIR/timing_violations.rpt { report_constraint -all_violators }

    handle_info "Floorplan timing estimation completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_reports
# Generate consolidated post-floorplan summary
# ---------------------------------------------------------------------------
flow_proc generate_reports {
    handle_info "Generating post-floorplan summary reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"

    # Design summary
    redirect -file $::REPORTS_DIR/design_summary.rpt { report_design }
    redirect -file $::REPORTS_DIR/physical_summary.rpt { report_design -physical }

    # Create consolidated summary
    set fp [open "$res_dir/fc_post_floorplan_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "FCFP Post-Floorplan Analysis Summary - Fusion Compiler"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Analysis steps:"
    puts $fp "  1. Partition boundary check"
    puts $fp "  2. Congestion analysis"
    puts $fp "  3. Virtual route timing estimation"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Post-floorplan reports generated"
}

# ---------------------------------------------------------------------------
# flow_proc: read_pin_constraints
# Read pin constraint files for pin placement (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc read_pin_constraints {
    handle_info "Reading pin constraints..."
    global fcfp

    # Read TCL-format pin constraints
    if {[info exists fcfp(input,tcl_pin_constraint_file)] && [file exists $fcfp(input,tcl_pin_constraint_file)]} {
        handle_info "Sourcing TCL pin constraint file: $fcfp(input,tcl_pin_constraint_file)"
        source -e $fcfp(input,tcl_pin_constraint_file)
    }

    # Read pin constraint format file
    if {[info exists fcfp(input,pin_constraint_file)] && [file exists $fcfp(input,pin_constraint_file)]} {
        handle_info "Reading pin constraint file: $fcfp(input,pin_constraint_file)"
        read_pin_constraints -file_name $fcfp(input,pin_constraint_file)
    }

    # Pre-pin-placement design check
    if {[info exists fc(common,check_design)] && $fc(common,check_design)} {
        redirect -file $::REPORTS_DIR/check_design.pre_pin_placement {
            check_design -ems_database check_design.pre_pin_placement.ems -checks dp_pre_pin_placement
        }
    }

    handle_info "Pin constraints loaded"
}

# ---------------------------------------------------------------------------
# flow_proc: run_pin_placement
# Place design pins (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc run_pin_placement {
    handle_info "Running pin placement..."
    global fcfp

    # Detect if pin placement was performed during floorplan (port_placement_export_file exists)
    # If so, restore and legalize; otherwise run full pin placement
    if {[get_attribute -quiet [current_block] port_placement_export_file] ne ""} {
        handle_info "Restoring pin placement from floorplan export file"
        set export_file [get_attribute [current_block] port_placement_export_file]
        redirect -var x {catch {source $export_file}}
        if {[regexp "^.*Error:" $x]} {
            handle_warning "Errors detected when loading port_placement_export_file -- please inspect logs"
        }
        place_pins -self -legalize
    } else {
        handle_info "Running full pin placement"
        place_pins -self
    }

    handle_info "Pin placement completed"
}

# ---------------------------------------------------------------------------
# flow_proc: legalize_pins
# Legalize pin placement (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc legalize_pins {
    handle_info "Legalizing pin placement..."

    place_pins -self -legalize

    handle_info "Pin legalization completed"
}

# ---------------------------------------------------------------------------
# flow_proc: fix_port_placement
# Fix port placement to prevent movement by downstream commands
# (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc fix_port_placement {
    handle_info "Fixing port placement..."
    global fcfp

    if {[info exists fc(common,fix_port_placement)] && $fc(common,fix_port_placement)} {
        set port_list [get_ports -quiet -filter "port_type!=power && port_type!=ground && physical_status==placed"]
        if {[sizeof_collection $port_list] > 0} {
            set_attribute $port_list physical_status "fixed"
            handle_info "Fixed [sizeof_collection $port_list] ports"
        } else {
            handle_info "No placed signal ports to fix"
        }
    } else {
        handle_info "Port fixing not enabled -- skipping"
    }

    # Report unplaced ports
    set unplaced_ports [get_ports -quiet -filter "port_type!=power && port_type!=ground && physical_status==unplaced"]
    if {[sizeof_collection $unplaced_ports] > 0} {
        handle_warning "[sizeof_collection $unplaced_ports] signal ports are unplaced"
        foreach_in_collection port $unplaced_ports {
            handle_warning "Unplaced port: [get_object_name $port]"
        }
    }

    handle_info "Port placement fixing completed"
}

# ---------------------------------------------------------------------------
# flow_proc: check_pin_placement
# Verify pin placement and generate reports (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc check_pin_placement {
    handle_info "Checking pin placement..."
    # Verify pin placement
    redirect -file $::REPORTS_DIR/check_pin_placement.rpt {
        check_pin_placement -self -pre_route true -pin_spacing true -sides true -layers true -stacking true
    }

    handle_info "Pin placement check completed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_pin_reports
# Generate pin placement reports and write constraints for reuse
# (ported from FC-RM place_pins.tcl)
# ---------------------------------------------------------------------------
flow_proc generate_pin_reports {
    handle_info "Generating pin placement reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir $res_dir

    # Report pin placement
    redirect -file $::REPORTS_DIR/report_pin_placement.rpt {
        report_pin_placement -self
    }

    # Write pin constraints for incremental reuse
    write_pin_constraints -self \
        -file_name "$res_dir/preferred_port_locations.tcl" \
        -physical_pin_constraint {side | offset | layer} \
        -from_existing_pins

    handle_info "Pin placement reports generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all post-floorplan flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc fc_post_floorplan_flow {
    handle_info "Executing FCFP fc_post_floorplan flow..."
    flow_exec run_partition_check
    flow_exec run_congestion
    flow_exec run_timing
    flow_exec read_pin_constraints
    flow_exec run_pin_placement
    flow_exec legalize_pins
    flow_exec fix_port_placement
    flow_exec check_pin_placement
    flow_exec generate_pin_reports
    flow_exec generate_reports
    handle_info "FCFP fc_post_floorplan completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_post_floorplan_flow } else { puts " FCFP fc_post_floorplan procedures loaded" }

# Exit tool after stage completion
exit
