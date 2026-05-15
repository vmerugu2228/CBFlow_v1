#!/usr/bin/env tclsh
# CBFlow FCFP place_pins - Synopsys Fusion Compiler
# FC-RM: place_pins.tcl (hier) -- Pin constraint reading, pin placement,
#         legalization, check, and constraint export
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/place_pins/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP place_pins..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/place_pins1"
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
    handle_info "Loading design for place_pins..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(place_pins,from_label)] ? $fc(place_pins,from_label) : "create_power"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/place_pins
    current_block ${design_name}/place_pins
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: place_pins_final
# FC-RM: read_pin_constraints, place_pins -self -legalize
# ==============================================================================
flow_proc place_pins_final {
    handle_info "Placing pins..."
    global fcfp

    # Read TCL-format pin constraints
    if {[info exists fcfp(input,tcl_pin_constraint_file)] && [file exists $fcfp(input,tcl_pin_constraint_file)]} {
        handle_info "Sourcing TCL pin constraints: $fcfp(input,tcl_pin_constraint_file)"
        source -e $fcfp(input,tcl_pin_constraint_file)
    }

    # Read pin constraint file
    if {[info exists fcfp(input,pin_constraint_file)] && [file exists $fcfp(input,pin_constraint_file)]} {
        handle_info "Reading pin constraints: $fcfp(input,pin_constraint_file)"
        read_pin_constraints -file_name $fcfp(input,pin_constraint_file)
    }

    # Pre-pin-placement design check
    if {[info exists fc(common,check_design)] && $fc(common,check_design)} {
        redirect -file $::REPORTS_DIR/check_design.pre_pin_placement {
            check_design -ems_database check_design.pre_pin_placement.ems \
                -checks dp_pre_pin_placement
        }
    }

    # Run pin placement with legalization
    if {[get_attribute -quiet [current_block] port_placement_export_file] ne ""} {
        handle_info "Restoring pin placement from floorplan export"
        set export_file [get_attribute [current_block] port_placement_export_file]
        redirect -var x {catch {source $export_file}}
        place_pins -self -legalize
    } else {
        handle_info "Running full pin placement"
        place_pins -self
    }

    # Legalize
    place_pins -self -legalize

    # Fix port placement
    if {[info exists fc(common,fix_port_placement)] && $fc(common,fix_port_placement)} {
        set port_list [get_ports -quiet -filter "port_type!=power && port_type!=ground && physical_status==placed"]
        if {[sizeof_collection $port_list] > 0} {
            set_attribute $port_list physical_status "fixed"
            handle_info "Fixed [sizeof_collection $port_list] ports"
        }
    }

    handle_info "Pin placement completed"
}

# ==============================================================================
# flow_proc: check_pin_placement
# FC-RM: check_pin_placement -self
# ==============================================================================
flow_proc check_pin_placement {
    handle_info "Checking pin placement..."

    redirect -file $::REPORTS_DIR/check_pin_placement.rpt {
        check_pin_placement -self -pre_route true -pin_spacing true \
            -sides true -layers true -stacking true
    }

    redirect -file $::REPORTS_DIR/report_pin_placement.rpt {
        report_pin_placement -self
    }

    # Report unplaced ports
    set unplaced_ports [get_ports -quiet -filter "port_type!=power && port_type!=ground && physical_status==unplaced"]
    if {[sizeof_collection $unplaced_ports] > 0} {
        handle_warning "[sizeof_collection $unplaced_ports] signal ports remain unplaced"
    }

    handle_info "Pin placement checks completed"
}

# ==============================================================================
# flow_proc: write_pin_constraints
# FC-RM: Write pin constraints for reuse in downstream stages
# ==============================================================================
flow_proc write_pin_constraints {
    handle_info "Writing pin constraints for reuse..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir $res_dir

    write_pin_constraints -self \
        -file_name "$res_dir/preferred_port_locations.tcl" \
        -physical_pin_constraint {side | offset | layer} \
        -from_existing_pins

    handle_info "Pin constraints written to: $res_dir/preferred_port_locations.tcl"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving place_pins block..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/place_pins
    handle_info "Block saved: ${design_name}/place_pins"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating place_pins reports..."
    global fcfp

    set max_paths [expr {[info exists fc(analysis,max_paths)] ? $fc(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Place_pins reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/place_pins/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.place_pins.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
