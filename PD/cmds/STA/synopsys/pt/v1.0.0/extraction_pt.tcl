#!/usr/bin/env tclsh
# CBFlow STA extraction - Synopsys PrimeTime | Parasitic extraction and annotation
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/STA/extraction/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global sta project tech flow
handle_info "Starting STA extraction with Synopsys PrimeTime..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/STA/extraction"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: configure_extraction
# Configure extraction settings and corner parameters
# ---------------------------------------------------------------------------
flow_proc configure_extraction {
    handle_info "Configuring extraction parameters..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/extraction"
    file mkdir "$::REPORTS_DIR"

    # Set extraction corner
    if {[info exists ::sta(EXTRACTION_CORNER)]} {
        set_extraction_corner $::sta(EXTRACTION_CORNER)
        handle_info "Extraction corner: $::sta(EXTRACTION_CORNER)"
    }

    # Set extraction mode
    if {[info exists ::sta(EXTRACTION_MODE)]} {
        set_extraction_mode $::sta(EXTRACTION_MODE)
    } else {
        set_extraction_mode -detail_cap true
        handle_info "Using detailed extraction mode"
    }

    # Set coupling capacitance options
    if {[info exists ::sta(COUPLING_CAP_THRESHOLD)]} {
        set_coupling_cap_threshold $::sta(COUPLING_CAP_THRESHOLD)
    }

    # Set temperature for extraction
    if {[info exists ::sta(TEMPERATURE)]} {
        set_temperature $::sta(TEMPERATURE)
        handle_info "Temperature set: $::sta(TEMPERATURE)"
    }

    # Set process variation parameters
    if {[info exists ::sta(PROCESS_CORNER)]} {
        set_process_corner $::sta(PROCESS_CORNER)
        handle_info "Process corner: $::sta(PROCESS_CORNER)"
    }

    # Configure SPEF writing options
    if {[info exists ::sta(SPEF_PRECISION)]} {
        set_app_var spef_output_precision $::sta(SPEF_PRECISION)
    }

    handle_info "Extraction configuration completed"
}

# ---------------------------------------------------------------------------
# flow_proc: run_extraction
# Execute parasitic extraction using extract_rc
# ---------------------------------------------------------------------------
flow_proc run_extraction {
    handle_info "Running parasitic extraction..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$::OUTPUTS_DIR/extraction"
    set rpt_dir "$::REPORTS_DIR"

    # Run RC extraction
    handle_info "Extracting RC parasitics..."
    extract_rc

    # Write extracted SPEF
    set spef_out "$res_dir/parasitic.spef"
    write_parasitics -format spef -output $spef_out
    handle_info "SPEF written: $spef_out"

    # Write compressed SPEF for storage
    if {[info exists ::sta(COMPRESS_SPEF)] && $::sta(COMPRESS_SPEF)} {
        write_parasitics -format spef -compress -output "${spef_out}.gz"
        handle_info "Compressed SPEF written: ${spef_out}.gz"
    }

    # Report annotated parasitics
    report_annotated_parasitics > "$rpt_dir/annotated_parasitics.rpt"

    # Report extraction statistics
    report_parasitics -statistics > "$rpt_dir/extraction_statistics.rpt"

    # Report net RC
    report_net -connections -verbose > "$rpt_dir/net_connections.rpt"

    handle_info "Parasitic extraction completed"
}

# ---------------------------------------------------------------------------
# flow_proc: validate_extraction
# Validate extraction results for completeness and quality
# ---------------------------------------------------------------------------
flow_proc validate_extraction {
    handle_info "Validating extraction results..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$::OUTPUTS_DIR/extraction"
    set rpt_dir "$::REPORTS_DIR"
    set errors 0

    # Check SPEF file exists and is non-empty
    set spef_file "$res_dir/parasitic.spef"
    if {![file exists $spef_file]} {
        handle_error "Missing SPEF output: $spef_file"
        incr errors
    } elseif {[file size $spef_file] == 0} {
        handle_error "Empty SPEF file: $spef_file"
        incr errors
    } else {
        handle_info "SPEF file size: [expr {[file size $spef_file] / 1024}] KB"
    }

    # Check annotation coverage
    report_annotated_parasitics -check > "$rpt_dir/annotation_coverage.rpt"

    set cov_rpt "$rpt_dir/annotation_coverage.rpt"
    if {[file exists $cov_rpt]} {
        set fp [open $cov_rpt r]
        set content [read $fp]
        close $fp
        if {[string match "*unannotated*" $content]} {
            handle_warning "Some nets have unannotated parasitics"
        }
    }

    # Write validation summary
    set fp [open "$rpt_dir/extraction_validation.rpt" w]
    puts $fp "Extraction Validation Report - [clock format [clock seconds]]"
    puts $fp "============================================================"
    puts $fp "SPEF file:  $spef_file"
    if {[file exists $spef_file]} {
        puts $fp "File size:  [expr {[file size $spef_file] / 1024}] KB"
    }
    puts $fp "Errors:     $errors"
    close $fp

    if {$errors > 0} {
        handle_error "Extraction validation failed"
        return -code error "Validation failed"
    }
    handle_info "Extraction validation passed"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_report
# Generate extraction summary report
# ---------------------------------------------------------------------------
flow_proc generate_report {
    handle_info "Generating extraction summary report..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/extraction"

    # Timing update with extracted parasitics
    update_timing -full

    # Post-extraction timing summary
    report_timing -delay max -max_paths 20 > "$rpt_dir/post_extraction_timing.rpt"

    # Summary
    set fp [open "$res_dir/extraction_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "STA Extraction Summary - PrimeTime"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Extraction steps:"
    puts $fp "  1. Configuration (corner, mode, temperature)"
    puts $fp "  2. RC extraction (extract_rc)"
    puts $fp "  3. SPEF generation"
    puts $fp "  4. Validation and coverage check"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$rpt_dir/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Extraction summary report generated"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all extraction flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc extraction_flow {
    handle_info "Executing STA extraction flow..."
    flow_exec configure_extraction
    flow_exec run_extraction
    flow_exec validate_extraction
    flow_exec generate_report
    handle_info "STA extraction completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec extraction_flow } else { puts " STA extraction procedures loaded" }
exit
