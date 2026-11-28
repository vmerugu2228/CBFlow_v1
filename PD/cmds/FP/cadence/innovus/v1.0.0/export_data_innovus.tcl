#!/usr/bin/env tclsh
# FP export_data - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "export_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting CBFlow FP export_data stage for Innovus"
# Define common procedures used in config files
if {[info procs INFO] eq ""} {
    proc INFO {} {
        return "INFO"
    }
}
if {[info procs WARNING] eq ""} {
    proc WARNING {} {
        return "WARNING"
    }
}
# Define flow_proc if not already defined
if {[info procs flow_proc] eq ""} {
    proc flow_proc {name body} {
        proc $name {} $body
        handle_info "Flow procedure '$name' defined"
    }
}
# Generated configuration: sourced by the bootstrap above from
# work/$FLOW_TYPE/$NODE_NAME/run/config.tcl (the old search list probed a
# non-existent work/FP/export_data/ dir and tolerated errors silently).

# Design name for every exported file — project(top_module), no fallback.
set EXPORT_TOP [cbflow_require project top_module]

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOKS - Export DB Process
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc export_def {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Exporting DEF file..."

    # Create results directory
    set results_dir "results"
    if {![file exists "${results_dir}/def"]} {
        file mkdir "${results_dir}/def"
    }

    # Get top module name
    set top_module $::EXPORT_TOP

    # DEF export path
    set def_file "${results_dir}/def/${top_module}_fp.def"
    handle_info "Writing DEF: $def_file"

    # Export DEF with floorplan and placement information
    defOut -floorplan -netlist -placement $def_file

    # Verify DEF was written
    if {[file exists $def_file]} {
        set def_size [file size $def_file]
        handle_info "DEF exported successfully: $def_file ([expr {$def_size / 1024}] KB)"
    } else {
        handle_error "DEF export failed - file not created: $def_file"
        return 0
    }

    handle_info "DEF export completed"
}

flow_proc export_design {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Exporting Innovus design database..."

    # Create results directory
    set results_dir "results"
    if {![file exists $results_dir]} {
        file mkdir $results_dir
    }

    # Get top module name
    set top_module $::EXPORT_TOP

    # Save primary design database
    set enc_file "${results_dir}/${top_module}_fp.enc"
    handle_info "Saving design database: $enc_file"
    saveDesign $enc_file

    # Save checkpoint for backup
    set checkpoint_dir "${results_dir}/checkpoints"
    if {![file exists $checkpoint_dir]} {
        file mkdir $checkpoint_dir
    }
    set checkpoint_file "${checkpoint_dir}/${top_module}_fp_checkpoint.enc"
    handle_info "Creating checkpoint: $checkpoint_file"
    saveDesign $checkpoint_file

    # Export Verilog netlist with floorplan annotations
    set netlist_dir "${results_dir}/netlist"
    if {![file exists $netlist_dir]} {
        file mkdir $netlist_dir
    }
    set netlist_file "${netlist_dir}/${top_module}_fp.v"
    handle_info "Saving netlist: $netlist_file"
    saveNetlist $netlist_file

    handle_info "Design database export completed"
    handle_info "  Database: $enc_file"
    handle_info "  Checkpoint: $checkpoint_file"
    handle_info "  Netlist: $netlist_file"
}

flow_proc export_reports {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Generating export reports..."

    # Create reports directory
    if {![file exists "reports"]} {
        file mkdir "reports"
    }

    # Design statistics
    handle_info "Generating design statistics..."
    if {[catch {report_design > $::REPORTS_DIR/export_design_summary.rpt} result]} {
        handle_warning "Could not generate design summary: $result"
    }

    # Area report
    handle_info "Generating area report..."
    if {[catch {report_area > $::REPORTS_DIR/export_area.rpt} result]} {
        handle_warning "Could not generate area report: $result"
    }

    # Cell usage report
    handle_info "Generating cell usage report..."
    if {[catch {report_cells > $::REPORTS_DIR/export_cell_usage.rpt} result]} {
        handle_warning "Could not generate cell usage report: $result"
    }

    # Net statistics
    handle_info "Generating net statistics..."
    if {[catch {report_nets > $::REPORTS_DIR/export_net_stats.rpt} result]} {
        handle_warning "Could not generate net statistics report: $result"
    }

    # Power domain report (if UPF/CPF was used)
    if {[info exists fp(input,upf_file)] || [info exists fp(input,cpf)]} {
        handle_info "Generating power domain report..."
        if {[catch {report_power_domain > $::REPORTS_DIR/export_power_domains.rpt} result]} {
            handle_warning "Could not generate power domain report: $result"
        }
    }

    # Constraint coverage
    handle_info "Generating constraint coverage..."
    if {[catch {report_constraint -all_violators > $::REPORTS_DIR/export_constraints.rpt} result]} {
        handle_warning "Could not generate constraint report: $result"
    }

    handle_info "Export reports generated in: $::REPORTS_DIR"
}

flow_proc validate_exports {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Validating exported files..."

    set results_dir "results"
    set top_module $::EXPORT_TOP
    set validation_errors 0

    # Check required output files
    set required_files [list \
        "${results_dir}/def/${top_module}_fp.def" \
        "${results_dir}/${top_module}_fp.enc" \
        "${results_dir}/netlist/${top_module}_fp.v" \
    ]

    foreach file $required_files {
        if {[file exists $file]} {
            set fsize [file size $file]
            handle_info "Validated: [file tail $file] ([expr {$fsize / 1024}] KB)"
        } else {
            handle_warning "Missing export file: $file"
            incr validation_errors
        }
    }

    # Check reports were generated
    set report_files [glob -nocomplain reports/export_*.rpt]
    handle_info "Generated [llength $report_files] export report(s)"

    if {$validation_errors > 0} {
        handle_warning "Export validation completed with $validation_errors missing file(s)"
    } else {
        handle_info "Export validation passed - all files present"
    }

    handle_info "═══════════════════════════════════════════════════════════════"
    handle_info "CBFlow FP Export DB Stage - COMPLETED SUCCESSFULLY"
    handle_info "Design Database: ${results_dir}/${top_module}_fp.enc"
    handle_info "DEF: ${results_dir}/def/${top_module}_fp.def"
    handle_info "Reports: reports/"
    handle_info "═══════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "═══════════════════════════════════════════════════════════════"
handle_info "CBFlow FP Export DB Stage - Starting Execution"
handle_info "═══════════════════════════════════════════════════════════════"

# Execute flow procedures in sequence
set flow_steps {
    export_def
    export_design
    export_reports
    validate_exports
}

flow_exec_all

handle_info "CBFlow FP export_data stage completed successfully"

# Exit tool after stage completion
exit
