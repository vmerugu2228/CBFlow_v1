#!/usr/bin/env tclsh
# CBFlow FCFP place_pins - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "place_pins"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for place_pins..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(place_pins,from_label)] ? $fcfp(place_pins,from_label) : "create_power"}]
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
    if {[info exists fcfp(common,check_design)] && $fcfp(common,check_design)} {
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
    if {[info exists fcfp(common,fix_port_placement)] && $fcfp(common,fix_port_placement)} {
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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Place_pins reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
