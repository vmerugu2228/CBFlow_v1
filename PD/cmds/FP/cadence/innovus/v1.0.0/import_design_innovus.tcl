#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP Import Design Stage for Innovus
# Description: Import design into Innovus for floorplanning
# Usage: Source this file in Innovus or run via CBFlow
# Output: import_design.enc - Imported design database
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

set WORK_DIR "$run_dir/work/FP/import_design"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting CBFlow FP import_design stage for Innovus"

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
        # Create the procedure directly
        proc $name {} $body
        handle_info "Flow procedure '$name' defined"
    }
}

# Source generated configuration file (from setup stage)
set flow_type "FP"
set config_files [list \
    "config.tcl" \
    "work/$flow_type/import_design/run/config.tcl" \
    "../work/$flow_type/import_design/run/config.tcl" \
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
    handle_error "Cannot find generated config file. Run 'make import_design_setup' first."
    exit 1
}

# Setup file will source this command file - no need to source setup here to avoid circular dependency

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOKS - Design Import Process
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc initialize_import_environment {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Initializing import design environment..."

    # Set Innovus mode to floorplan
    if {[info exists innovus(common,tool_mode)]} {
        handle_info "Setting tool mode: $innovus(common,tool_mode)"
        set_global _INNOVUS_MODE_ $innovus(common,tool_mode)
    }

    # Configure design import settings
    if {[info exists innovus(common,import_mode)] && $innovus(common,import_mode) eq "incremental"} {
        handle_info "Enabling incremental import mode"
        set_global incremental_import true
    }

    # Set up working directories
    set work_dirs {"reports" "results" "logs" "scripts"}
    foreach dir $work_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created directory: $dir"
        }
    }

    handle_info "Import environment initialized"
}

flow_proc setup_technology_libraries {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Setting up technology libraries for import..."

    # ROOT_DIR should be project root, construct from FLOW_DIR
    set project_root [file dirname $FLOW_DIR]

    # Read LEF files for import
    if {[info exists tech(lef,technology)]} {
        # Expand any variables in the LEF path
        set expanded_lef [subst $tech(lef,technology)]
        set lef_path [file join $project_root $expanded_lef]
        if {[file exists $lef_path]} {
            handle_info "Reading technology LEF: [file tail $tech(lef,technology)]"
            read_lef $lef_path
        } else {
            handle_warning "Technology LEF not found: $lef_path"
        }
    }

    # Read standard cell LEF
    if {[info exists tech(lef,standard_cells)]} {
        set expanded_lef [subst $tech(lef,standard_cells)]
        set lef_path [file join $project_root $expanded_lef]
        if {[file exists $lef_path]} {
            handle_info "Reading standard cell LEF: [file tail $tech(lef,standard_cells)]"
            read_lef $lef_path
        } else {
            handle_warning "Standard cell LEF not found: $lef_path"
        }
    }

    # Read macro LEF files if any
    if {[info exists tech(lef,macros)]} {
        foreach lef $tech(lef,macros) {
            if {[file exists $lef]} {
                handle_info "Reading macro LEF: [file tail $lef]"
                read_lef $lef
            } else {
                handle_warning "Macro LEF not found: $lef"
            }
        }
    }

    # Set up timing libraries for import verification
    if {[info exists tech(lib,timing)]} {
        foreach lib $tech(lib,timing) {
            if {[file exists $lib]} {
                handle_info "Reading timing library: [file tail $lib]"
                read_lib $lib
            } else {
                handle_warning "Timing library not found: $lib"
            }
        }
    }

    handle_info "Technology libraries setup completed"
}

flow_proc import_design_netlist {
    handle_info "Importing design netlist..."

    global fp project

    # Get netlist file from inputs
    if {![info exists fp(input,netlist)]} {
        handle_error "fp(input,netlist) not defined. Check inputs stage."
        return 0
    }

    set netlist_file $fp(input,netlist)
    if {![file exists $netlist_file]} {
        handle_error "Netlist file not found: $netlist_file"
        return 0
    }

    handle_info "Reading netlist: [file tail $netlist_file]"
    read_netlist $netlist_file

    # Set top module
    if {[info exists project(top_module)]} {
        handle_info "Setting top module: $project(top_module)"
        set_top_module $project(top_module)
    }

    handle_info "Design netlist imported successfully"
    return 1
}

flow_proc apply_design_constraints {
    handle_info "Applying design constraints..."

    global fp

    # Read SDC constraints
    if {[info exists fp(input,sdc)]} {
        set sdc_file $fp(input,sdc)
        if {[file exists $sdc_file]} {
            handle_info "Reading SDC constraints: [file tail $sdc_file]"
            read_sdc $sdc_file
        } else {
            handle_warning "SDC file not found: $sdc_file"
        }
    }

    # Read UPF power intent if available
    if {[info exists fp(input,upf)]} {
        set upf_file $fp(input,upf)
        if {[file exists $upf_file]} {
            handle_info "Reading UPF power intent: [file tail $upf_file]"
            read_power_intent -1801 $upf_file
        } else {
            handle_info "UPF file not specified or not found: $upf_file"
        }
    }

    # Apply floorplan constraints if available
    if {[info exists fp(input,def)]} {
        set def_file $fp(input,def)
        if {[file exists $def_file]} {
            handle_info "Reading DEF floorplan: [file tail $def_file]"
            read_def $def_file
        } else {
            handle_info "DEF file not specified: $def_file"
        }
    }

    handle_info "Design constraints applied"
}

flow_proc perform_design_checks {
    handle_info "Performing design import checks..."

    # Check design connectivity
    handle_info "Checking design connectivity..."
    check_design -all

    # Verify timing constraints
    handle_info "Verifying timing constraints..."
    report_constraint -all_violators

    # Check for missing cells/macros
    handle_info "Checking for missing cells..."
    check_library_cells

    # Verify floorplan if DEF was read
    global fp
    if {[info exists fp(input,def)] && [file exists $fp(input,def)]} {
        handle_info "Verifying floorplan consistency..."
        check_floorplan
    }

    # Generate design import report
    set report_file "$::REPORTS_DIR/import_design_check.rpt"
    handle_info "Generating design check report: $report_file"
    report_design > $report_file

    handle_info "Design import checks completed"
}

flow_proc initialize_floorplan_environment {
    handle_info "Initializing floorplan environment..."

    global fp

    # Set core utilization if specified
    if {[info exists innovus(common,core_utilization)]} {
        handle_info "Setting core utilization: $innovus(common,core_utilization)"
        set_global core_utilization $innovus(common,core_utilization)
    }

    # Set aspect ratio if specified
    if {[info exists innovus(common,aspect_ratio)]} {
        handle_info "Setting aspect ratio: $innovus(common,aspect_ratio)"
        set_global aspect_ratio $innovus(common,aspect_ratio)
    }

    # Initialize power domains if UPF was read
    if {[info exists fp(input,upf)] && [file exists $fp(input,upf)]} {
        handle_info "Initializing power domains..."
        init_power_domain
    }

    # Set up design for floorplanning
    handle_info "Preparing design for floorplanning..."
    init_design

    handle_info "Floorplan environment initialized"
}

flow_proc save_import_design_database {
    handle_info "Saving import design database..."

    # Create results directory if it doesn't exist
    if {![file exists "results"]} {
        file mkdir "results"
    }

    # Save the imported design as .enc file
    set enc_file "results/import_design.enc"
    handle_info "Saving design database: $enc_file"
    save_design $enc_file

    # Also save as checkpoint for backup
    set checkpoint_file "results/import_design_checkpoint.enc"
    handle_info "Creating checkpoint: $checkpoint_file"
    save_design $checkpoint_file

    # Generate design summary report
    set summary_file "$::REPORTS_DIR/import_design_summary.rpt"
    handle_info "Generating design summary: $summary_file"
    report_summary > $summary_file

    handle_info "Import design database saved successfully"
    handle_info "Main database: $enc_file"
    handle_info "Checkpoint: $checkpoint_file"
}

flow_proc generate_import_reports {
    handle_info "Generating import design reports..."

    # Create reports directory
    if {![file exists "reports"]} {
        file mkdir "reports"
    }

    # Design statistics report
    handle_info "Generating design statistics..."
    report_design_statistics > $::REPORTS_DIR/design_statistics.rpt

    # Cell usage report
    handle_info "Generating cell usage report..."
    report_cells > $::REPORTS_DIR/cell_usage.rpt

    # Net statistics
    handle_info "Generating net statistics..."
    report_nets > $::REPORTS_DIR/net_statistics.rpt

    # Power domain report (if UPF was used)
    global fp
    if {[info exists fp(input,upf)] && [file exists $fp(input,upf)]} {
        handle_info "Generating power domain report..."
        report_power_domain > $::REPORTS_DIR/power_domains.rpt
    }

    # Constraint coverage report
    handle_info "Generating constraint coverage..."
    report_constraint_coverage > $::REPORTS_DIR/constraint_coverage.rpt

    handle_info "Import design reports generated in: $::REPORTS_DIR"
}

flow_proc validate_fp_import_results {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR

    handle_info "Running enhanced validation for FP import_design stage..."

    # Determine current working directory and flow directory
    set current_dir $::env(CBFLOW_RUN_DIR)
    set validation_flow_dir ""

    if {[info exists FLOW_DIR]} {
        set validation_flow_dir $FLOW_DIR
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set validation_flow_dir $::env(FLOW_DIR)
    } else {
        # Try to determine flow directory from current location
        set script_dir [file dirname [file normalize [info script]]]
        set validation_flow_dir [file dirname [file dirname [file dirname [file dirname $script_dir]]]]
    }

    # Enhanced validation script path
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"

    if {![file exists $enhanced_validation_script]} {
        handle_warning "Enhanced validation script not found: $enhanced_validation_script"
        handle_info "Falling back to basic validation if available..."

        # Try basic validation
        set basic_validation_script "$validation_flow_dir/utils/validation/v1.0.0/validate_run.tcl"
        if {[file exists $basic_validation_script]} {
            handle_info "Running basic validation for FP import_design..."
            if {[catch {exec tclsh $basic_validation_script FP import_design $current_dir $validation_flow_dir} validation_result]} {
                handle_error "Basic validation failed: $validation_result"
                return 0
            } else {
                handle_info "Basic validation completed successfully"
                return 1
            }
        } else {
            handle_warning "No validation script available, skipping validation"
            return 1
        }
    }

    # Run enhanced validation
    handle_info "Executing enhanced validation with critical error detection..."
    handle_info "Command: tclsh $enhanced_validation_script FP import_design $current_dir $validation_flow_dir"

    if {[catch {exec tclsh $enhanced_validation_script FP import_design $current_dir $validation_flow_dir} validation_result]} {
        handle_error "Enhanced validation failed with critical errors detected"
        handle_info "Validation output: $validation_result"

        # Check if this is a critical error failure (exit code 1) vs other errors
        if {[string match "*critical*error*" [string tolower $validation_result]] ||
            [string match "*xterm*" [string tolower $validation_result]]} {
            handle_error "Critical errors detected in FP import_design logs - check xterm display"
        }
        return 0
    } else {
        handle_info "Enhanced validation completed successfully"
        handle_info "Validation output: $validation_result"
        return 1
    }
}

flow_proc import_design_complete {
    handle_info "Import design stage complete"

    # Run any custom completion hooks
    if {[info procs import_design_custom_init] ne ""} {
        handle_info "Running custom import_design initialization..."
        set result [import_design_custom_init]
        handle_info "Custom initialization result: $result"
    }

    # Final status message
    handle_info "═══════════════════════════════════════════════════════════════"
    handle_info "CBFlow FP Import Design Stage - COMPLETED SUCCESSFULLY"
    handle_info "Design Database: results/import_design.enc"
    handle_info "Reports: reports/"
    handle_info "Next Stage: floorplan (make floorplan)"
    handle_info "═══════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "═══════════════════════════════════════════════════════════════"
handle_info "CBFlow FP Import Design Stage - Starting Execution"
handle_info "═══════════════════════════════════════════════════════════════"

# Execute flow procedures in sequence
set flow_steps {
    initialize_import_environment
    setup_technology_libraries
    import_design_netlist
    apply_design_constraints
    perform_design_checks
    initialize_floorplan_environment
    save_import_design_database
    generate_import_reports
    validate_fp_import_results
    import_design_complete
}

foreach step $flow_steps {
    handle_info "Executing flow step: $step"

    if {[catch {$step} error]} {
        handle_error "Flow step '$step' failed: $error"
        exit 1
    }

    handle_info "Flow step '$step' completed successfully"
}

handle_info "CBFlow FP import_design stage completed successfully"
# Exit tool after stage completion
exit
