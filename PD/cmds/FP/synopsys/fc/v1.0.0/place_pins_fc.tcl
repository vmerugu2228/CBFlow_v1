#!/usr/bin/env tclsh
# CBFlow FP place_pins - Synopsys Fusion Compiler
# FC-RM: place_pins.tcl -- Finalize pin placement, legalize, export constraints
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "place_pins"
set NODE_NAME "place_pins1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from create_power, link_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for place_pins..."
    global fp flow

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]
    set lib_name [expr {[info exists fp(common,design_lib_name)] ? $fp(common,design_lib_name) : "${design_name}.nlib"}]

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
    if {[info exists fp(place_pins,constraint_file)] && $fp(place_pins,constraint_file) ne ""} {
        if {[file exists $fp(place_pins,constraint_file)]} {
            handle_info "Reading pin constraints: $fp(place_pins,constraint_file)"
            read_pin_constraints -file_name $fp(place_pins,constraint_file)
        }
    }

    # FC-RM: place_pins with legalization
    set legalize false
    if {[info exists fp(place_pins,legalize)]} { set legalize $fp(place_pins,legalize) }

    if {$legalize} {
        handle_info "Running place_pins -self -legalize"
        place_pins -self -legalize
    } else {
        handle_info "Running place_pins -self"
        place_pins -self
    }

    # FC-RM: Fix port positions
    if {[info exists fp(place_pins,fix_ports)] && $fp(place_pins,fix_ports)} {
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

    set design_name [expr {[info exists fp(common,design_name)] ? $fp(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists fp(output,block_labeling)] && $fp(output,block_labeling)} {
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
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.place_pins.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
