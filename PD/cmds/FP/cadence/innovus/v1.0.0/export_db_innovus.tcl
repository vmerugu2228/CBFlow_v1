#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP Export DB Stage for Innovus
# Description: Export DEF, design database, and reports for downstream flows
# Usage: Source this file in Innovus or run via CBFlow
# Output: DEF, .enc database, and summary reports
# ═══════════════════════════════════════════════════════════════════════════════

# Validate required environment variables
if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
    puts "ERROR: FLOW_DIR not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

set flow_dir $::env(FLOW_DIR)

# Source flow utilities using release version
set utils_path "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find flow utilities at: $utils_path"
    exit 1
}

set run_dir $::env(CBFLOW_RUN_DIR)

set WORK_DIR "$run_dir/work/FP/export_db"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting CBFlow FP export_db stage for Innovus"

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

# Source generated configuration file (from setup stage)
set flow_type "FP"
set config_files [list \
    "config.tcl" \
    "work/$flow_type/export_db/run/config.tcl" \
    "../work/$flow_type/export_db/run/config.tcl" \
]

set config_found 0
foreach config_file $config_files {
    if {[file exists $config_file]} {
        handle_info "Sourcing configuration: $config_file"
        if {[catch {source $config_file} error]} {

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
            handle_warning "Minor error in config file $config_file: $error"
            handle_info "Continuing with available configuration..."
        }
        set config_found 1
        break
    }
}

if {!$config_found} {
    handle_error "Cannot find generated config file. Run 'make export_db_setup' first."
    exit 1
}

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
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : "design"}]

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
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : "design"}]

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
    if {[info exists fp(input,upf)] || [info exists fp(input,cpf)]} {
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
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : "design"}]
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

foreach step $flow_steps {
    handle_info "Executing flow step: $step"

    if {[catch {$step} error]} {
        handle_error "Flow step '$step' failed: $error"
        exit 1
    }

    handle_info "Flow step '$step' completed successfully"
}

handle_info "CBFlow FP export_db stage completed successfully"

# Exit tool after stage completion
exit
