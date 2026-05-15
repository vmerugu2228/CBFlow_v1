#!/usr/bin/env tclsh
# CBFlow FP place_pins - Synopsys Fusion Compiler
# FC-RM: place_pins.tcl -- Finalize pin placement, legalize, export constraints
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FP/place_pins1/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP place_pins (FC-RM Y-2026.03 aligned)..."
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

set WORK_DIR "$run_dir/work/FP/place_pins1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from create_power, link_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for place_pins..."
    global fp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fc(common,design_lib_name)] ? $fc(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    copy_block -from ${design_name}/create_power -to ${design_name}/place_pins
    current_block ${design_name}/place_pins
    link_block

    handle_info "Design loaded: ${design_name}/place_pins"
}

# ==============================================================================
# flow_proc: place_pins_final
# FC-RM: read_pin_constraints, place_pins -self -legalize
# ==============================================================================
flow_proc place_pins_final {
    handle_info "Placing pins (final)..."
    global fp tech

    # FC-RM: Read pin constraints
    if {[info exists fc(place_pins,constraint_file)] && $fc(place_pins,constraint_file) ne ""} {
        if {[file exists $fc(place_pins,constraint_file)]} {
            handle_info "Reading pin constraints: $fc(place_pins,constraint_file)"
            read_pin_constraints -file_name $fc(place_pins,constraint_file)
        }
    }

    # FC-RM: place_pins with legalization
    set legalize false
    if {[info exists fc(place_pins,legalize)]} { set legalize $fc(place_pins,legalize) }

    if {$legalize} {
        handle_info "Running place_pins -self -legalize"
        place_pins -self -legalize
    } else {
        handle_info "Running place_pins -self"
        place_pins -self
    }

    # FC-RM: Fix port positions
    if {[info exists fc(place_pins,fix_ports)] && $fc(place_pins,fix_ports)} {
        catch {
            foreach_in_collection port [get_ports *] {
                set_attribute $port physical_status "fixed"
            }
        }
        handle_info "All port positions fixed"
    }

    handle_info "Pin placement completed"
}

# ==============================================================================
# flow_proc: check_pin_placement
# FC-RM: check_pin_placement with comprehensive checks
# ==============================================================================
flow_proc check_pin_placement {
    handle_info "Checking pin placement..."

    redirect -file $::REPORTS_DIR/check_pin_placement.rpt {
        check_pin_placement -pre_route true -pin_spacing true -sides true -layers true -stacking true
    }
    redirect -file $::REPORTS_DIR/report_pin_placement.rpt {
        report_pin_placement -self
    }

    handle_info "Pin placement checks completed"
}

# ==============================================================================
# flow_proc: write_pin_constraints
# FC-RM: write_pin_constraints to export actual pin locations
# ==============================================================================
flow_proc write_pin_constraints {
    handle_info "Writing pin constraints..."

    set out $::OUTPUTS_DIR
    write_pin_constraints -output ${out}/pin_constraints.tcl
    handle_info "Pin constraints exported to: ${out}/pin_constraints.tcl"
}

# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving place_pins design..."
    global fp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        save_block -as ${design_name}/place_pins
        handle_info "Block saved: ${design_name}/place_pins"
    }

    handle_info "Place pins design saved"
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: report_qor, run_end
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating place_pins reports..."

    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -summary }
    # run_end removed (not a valid FC command)
    # redirect -file $::REPORTS_DIR/run_end.rpt { run_end }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Place pins reports generated"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FP/place_pins1/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.place_pins.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
