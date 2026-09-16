#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Enhanced Run Validation Script with XTerm Integration
# Description: Enhanced validation with critical error detection and xterm display
# Usage: tclsh enhanced_validate_run.tcl <FLOW_TYPE> <STAGE_NAME> <run_dir> [flow_dir]
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command line arguments
if {$argc < 3 || $argc > 4} {
    puts "ERROR: Invalid number of arguments."
    puts "Usage: tclsh enhanced_validate_run.tcl <FLOW_TYPE> <STAGE_NAME> <run_dir> [flow_dir]"
    puts "  FLOW_TYPE: SYNTH, PNR, FP"
    puts "  STAGE_NAME: Stage to validate (e.g., synthesis, import_design, floorplan)"
    puts "  run_dir: Run directory path"
    puts "  flow_dir: Flow directory path (optional)"
    puts ""
    puts "Enhanced features:"
    puts "  • Critical error detection with configurable patterns"
    puts "  • XTerm red color display for critical errors"
    puts "  • Cursor positioning to error lines"
    puts "  • Tool-specific error ID recognition"
    puts "  • Enhanced error categorization and reporting"
    exit 1
}

set flow_type [lindex $argv 0]
set stage_name [lindex $argv 1]
set run_dir [lindex $argv 2]

if {$argc == 4} {
    set flow_dir [lindex $argv 3]
} else {
    # Try to determine flow_dir from environment or run directory
    if {[info exists env(FLOW_DIR)]} {
        set flow_dir $env(FLOW_DIR)
    } else {
        set flow_dir "../flow"
    }
}

# Validate flow_type
if {$flow_type ni {SYNTH PNR FP SIGNOFF}} {
    puts "ERROR: Invalid flow_type '$flow_type'. Must be SYNTH, PNR, FP, or SIGNOFF"
    exit 1
}

# Global enhanced validation state
set enhanced_validation_errors 0
set enhanced_validation_warnings 0
set enhanced_validation_critical_errors 0
set enhanced_validation_log_file ""
set critical_errors_found {}

# ═══════════════════════════════════════════════════════════════════════════════
# ENHANCED INITIALIZATION AND UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

proc init_enhanced_validation {} {
    global run_dir stage_name flow_dir enhanced_validation_log_file FLOW_DIR
    global validation

    # Change to run directory
    if {![file exists $run_dir]} {
        puts "ERROR: Run directory not found: $run_dir"
        exit 1
    }
    cd $run_dir

    # Set FLOW_DIR environment variable
    set ::env(FLOW_DIR) $flow_dir
    set FLOW_DIR $flow_dir

    # Initialize enhanced validation log
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set enhanced_validation_log_file "logs/enhanced_validate_${stage_name}_${timestamp}.log"

    # Ensure logs directory exists
    file mkdir [file dirname $enhanced_validation_log_file]

    # Source core utilities
    if {[file exists "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"]} {
        source "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
    } else {
        puts "ERROR: Cannot find flow utilities at $flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
        exit 1
    }

    # Source error utilities
    if {[file exists "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"]} {
        source "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
    } else {
        puts "WARNING: Error utilities not found, using basic error handling"
    }

    # Source xterm display utilities
    if {[file exists "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/xterm_display.tcl"]} {
        source "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/xterm_display.tcl"
    } else {
        puts "WARNING: XTerm display utilities not found, xterm display disabled"
    }

    # Load enhanced validation configuration
    if {[file exists "$flow_dir/config/flow/v1.0.0/validation_config.tcl"]} {
        source "$flow_dir/config/flow/v1.0.0/validation_config.tcl"
        handle_info "Enhanced validation configuration loaded"
    } else {
        puts "WARNING: Enhanced validation config not found, using basic validation"
        # Set minimal defaults
        array set validation {
            enable_xterm_display 0
            enable_enhanced_patterns 0
            xterm_display_threshold 1
        }
    }

    # Load existing validation infrastructure
    if {[file exists "$flow_dir/utils/validation/$::env(VALIDATION_VERSION)/validate_run.tcl"]} {
        # Source the existing validation functions without running main
        set temp_argv0 $::argv0
        set ::argv0 "sourced_validation"
        source "$flow_dir/utils/validation/$::env(VALIDATION_VERSION)/validate_run.tcl"
        set ::argv0 $temp_argv0
        handle_info "Base validation infrastructure loaded"
    } else {
        puts "ERROR: Base validation script not found"
        exit 1
    }

    # Load flow configuration including MMMC settings
    if {[file exists "$flow_dir/config/flow/v1.0.0/flow_config.tcl"]} {
        source "$flow_dir/config/flow/v1.0.0/flow_config.tcl"
    } else {
        handle_warning "Cannot find flow configuration at $flow_dir/config/flow/v1.0.0/flow_config.tcl"
    }

    # Load consolidated configuration
    if {[file exists "work/$flow_type/$stage_name/run/config.tcl"]} {
        source "work/$flow_type/$stage_name/run/config.tcl"
    } else {
        handle_warning "Stage configuration file not found: work/$flow_type/$stage_name/run/config.tcl"
    }

    # Initialize enhanced validation log file
    set fp [open $enhanced_validation_log_file w]
    puts $fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "# CBFlow Enhanced Validation Report"
    puts $fp "# Generated: [clock format [clock seconds]]"
    puts $fp "# Flow Type: $flow_type"
    puts $fp "# Stage: $stage_name"
    puts $fp "# Run Directory: $run_dir"
    puts $fp "# Enhanced Features: Critical Error Detection, XTerm Integration"
    puts $fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fp ""
    close $fp

    handle_info "Enhanced validation initialized for $flow_type flow, stage: $stage_name"
}

proc log_enhanced_validation {level message} {
    global enhanced_validation_log_file

    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]
    set log_entry "\[$timestamp\] \[ENHANCED_$level\] $message"

    # Print to console using error utilities if available
    if {[info procs handle_info] ne ""} {
        switch $level {
            "INFO" { handle_info "$message" }
            "WARNING" { handle_warning "$message" }
            "ERROR" { handle_error "$message" "" 0 }
            "CRITICAL" {
                if {[info procs CBFLOW_ERROR] ne ""} {
                    CBFLOW_ERROR "CRITICAL: $message" "ENHANCED_VALIDATION"
                } else {
                    puts "CRITICAL ERROR: $message"
                }
            }
            default { puts $log_entry }
        }
    } else {
        puts $log_entry
    }

    # Write to enhanced validation log
    if {$enhanced_validation_log_file ne ""} {
        set fp [open $enhanced_validation_log_file a]
        puts $fp $log_entry
        close $fp
    }
}

proc increment_enhanced_counter {type} {
    global enhanced_validation_errors enhanced_validation_warnings enhanced_validation_critical_errors

    switch $type {
        "error" { incr enhanced_validation_errors }
        "warning" { incr enhanced_validation_warnings }
        "critical" { incr enhanced_validation_critical_errors }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENHANCED CRITICAL ERROR DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

proc get_critical_error_patterns {flow_type stage_name} {
    global validation

    set critical_patterns {}

    # Get tool-specific critical error IDs
    set tool_key "critical_error_ids,${flow_type}"
    if {[info exists validation($tool_key)]} {
        set critical_patterns [concat $critical_patterns $validation($tool_key)]
    }

    # Get flow-specific error patterns
    set flow_pattern_key "error_patterns,${flow_type}"
    if {[info exists validation($flow_pattern_key)]} {
        set critical_patterns [concat $critical_patterns $validation($flow_pattern_key)]
    }

    # Get stage-specific error patterns
    set stage_pattern_key "error_patterns,${flow_type},${stage_name}"
    if {[info exists validation($stage_pattern_key)]} {
        set critical_patterns [concat $critical_patterns $validation($stage_pattern_key)]
    }

    # Add tool crash patterns
    if {[info exists validation(tool_crash_patterns)]} {
        set critical_patterns [concat $critical_patterns $validation(tool_crash_patterns)]
    }

    # Add license error patterns
    if {[info exists validation(license_error_patterns)]} {
        set critical_patterns [concat $critical_patterns $validation(license_error_patterns)]
    }

    return $critical_patterns
}

proc get_critical_warning_patterns {flow_type stage_name} {
    global validation

    set critical_warning_patterns {}

    # Get flow-specific warning patterns
    set flow_pattern_key "warning_patterns,${flow_type}"
    if {[info exists validation($flow_pattern_key)]} {
        set critical_warning_patterns [concat $critical_warning_patterns $validation($flow_pattern_key)]
    }

    # Get stage-specific warning patterns
    set stage_pattern_key "warning_patterns,${flow_type},${stage_name}"
    if {[info exists validation($stage_pattern_key)]} {
        set critical_warning_patterns [concat $critical_warning_patterns $validation($stage_pattern_key)]
    }

    return $critical_warning_patterns
}

proc detect_critical_errors_in_log {log_file flow_type stage_name} {
    global critical_errors_found validation

    log_enhanced_validation "INFO" "Analyzing log file for critical errors: [file tail $log_file]"

    if {![file exists $log_file]} {
        log_enhanced_validation "WARNING" "Log file not found: $log_file"
        return {}
    }

    set critical_patterns [get_critical_error_patterns $flow_type $stage_name]
    log_enhanced_validation "INFO" "Using [llength $critical_patterns] critical error patterns"

    set waiver_patterns [get_waiver_patterns $flow_type $stage_name]
    log_enhanced_validation "INFO" "Using [llength $waiver_patterns] waiver patterns"

    set critical_errors {}
    set fp [open $log_file r]
    set line_num 0

    while {[gets $fp line] >= 0} {
        incr line_num

        # Check for critical error patterns
        foreach pattern $critical_patterns {
            if {[regexp -nocase $pattern $line]} {
                # Check if this error is waivered
                set waiver_pattern [is_waivered $line $waiver_patterns]
                if {$waiver_pattern eq ""} {
                    # This is an unwaivered critical error
                    lappend critical_errors [list $line_num $line $pattern $log_file]
                    increment_enhanced_counter "critical"
                    log_enhanced_validation "CRITICAL" "Critical error at $log_file:$line_num"
                    log_enhanced_validation "CRITICAL" "  Pattern: $pattern"
                    log_enhanced_validation "CRITICAL" "  Line: [string trim $line]"
                } else {
                    log_enhanced_validation "INFO" "Critical error waivered at $log_file:$line_num (pattern: $waiver_pattern)"
                }
                break
            }
        }
    }

    close $fp

    set critical_errors_found [concat $critical_errors_found $critical_errors]
    return $critical_errors
}

proc validate_enhanced_log_files {flow_type stage_name} {
    global validation

    log_enhanced_validation "INFO" "Enhanced log file validation for $stage_name..."

    # Get log files using existing infrastructure
    set log_files [get_stage_log_files $flow_type $stage_name]

    if {[llength $log_files] == 0} {
        log_enhanced_validation "WARNING" "No log files found for enhanced validation"
        return true
    }

    set total_critical_errors 0
    set critical_error_logs {}

    # Analyze each log file for critical errors
    foreach log_file $log_files {
        set critical_errors [detect_critical_errors_in_log $log_file $flow_type $stage_name]

        if {[llength $critical_errors] > 0} {
            set total_critical_errors [expr {$total_critical_errors + [llength $critical_errors]}]
            lappend critical_error_logs $log_file

            log_enhanced_validation "ERROR" "Found [llength $critical_errors] critical errors in $log_file"

            # Display first critical error if xterm is enabled
            if {[info exists validation(enable_xterm_display)] && $validation(enable_xterm_display)} {
                set first_error [lindex $critical_errors 0]
                set error_line [lindex $first_error 0]

                if {[info procs cbflow_display_critical_errors] ne ""} {
                    set critical_patterns [get_critical_error_patterns $flow_type $stage_name]
                    cbflow_display_critical_errors $log_file $critical_patterns $flow_type $stage_name
                    log_enhanced_validation "INFO" "XTerm error viewer launched for $log_file at line $error_line"
                } else {
                    log_enhanced_validation "WARNING" "XTerm display requested but utilities not available"
                }
            }
        }
    }

    # Also run the base validation for comprehensive coverage
    log_enhanced_validation "INFO" "Running base validation for comprehensive coverage..."
    set base_validation_result [validate_log_files $flow_type $stage_name]

    # Summary
    log_enhanced_validation "INFO" "Enhanced validation summary:"
    log_enhanced_validation "INFO" "  Log files analyzed: [llength $log_files]"
    log_enhanced_validation "INFO" "  Critical errors found: $total_critical_errors"
    log_enhanced_validation "INFO" "  Log files with critical errors: [llength $critical_error_logs]"
    log_enhanced_validation "INFO" "  Base validation result: [expr {$base_validation_result ? \"PASSED\" : \"FAILED\"}]"

    # Check threshold for additional actions
    if {[info exists validation(xterm_display_threshold)]} {
        if {$total_critical_errors >= $validation(xterm_display_threshold)} {
            log_enhanced_validation "CRITICAL" "Critical error threshold exceeded: $total_critical_errors >= $validation(xterm_display_threshold)"
            return false
        }
    }

    # Return combined result
    return [expr {$base_validation_result && $total_critical_errors == 0}]
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENHANCED REPORTING
# ═══════════════════════════════════════════════════════════════════════════════

proc generate_enhanced_validation_summary {} {
    global enhanced_validation_errors enhanced_validation_warnings enhanced_validation_critical_errors
    global stage_name enhanced_validation_log_file critical_errors_found flow_type

    log_enhanced_validation "INFO" "═══════════════════════════════════════════════════════"
    log_enhanced_validation "INFO" "ENHANCED VALIDATION SUMMARY FOR STAGE: $stage_name"
    log_enhanced_validation "INFO" "═══════════════════════════════════════════════════════"
    log_enhanced_validation "INFO" "Enhanced Errors: $enhanced_validation_errors"
    log_enhanced_validation "INFO" "Enhanced Warnings: $enhanced_validation_warnings"
    log_enhanced_validation "INFO" "Critical Errors: $enhanced_validation_critical_errors"
    log_enhanced_validation "INFO" "Critical Error Details: [llength $critical_errors_found] entries"

    # Generate detailed critical error report
    if {[llength $critical_errors_found] > 0} {
        log_enhanced_validation "CRITICAL" "CRITICAL ERROR DETAILS:"
        foreach critical_error $critical_errors_found {
            lassign $critical_error line_num line pattern log_file
            log_enhanced_validation "CRITICAL" "  File: [file tail $log_file]:$line_num"
            log_enhanced_validation "CRITICAL" "  Pattern: $pattern"
            log_enhanced_validation "CRITICAL" "  Content: [string trim $line]"
        }
    }

    if {$enhanced_validation_critical_errors > 0} {
        log_enhanced_validation "ERROR" "ENHANCED VALIDATION FAILED: $enhanced_validation_critical_errors critical error(s) found"
        log_enhanced_validation "INFO" "Enhanced validation report: $enhanced_validation_log_file"
        return false
    } else {
        log_enhanced_validation "INFO" "ENHANCED VALIDATION PASSED: No critical errors found"
        if {$enhanced_validation_warnings > 0} {
            log_enhanced_validation "INFO" "Note: $enhanced_validation_warnings enhanced warning(s) found but validation considered passing"
        }
        log_enhanced_validation "INFO" "Enhanced validation report: $enhanced_validation_log_file"
        return true
    }
}

proc run_enhanced_validation_hooks {hook_type} {
    global validation flow_type stage_name

    set hook_key "${hook_type}_hooks"
    if {![info exists validation($hook_key)]} {
        return
    }

    log_enhanced_validation "INFO" "Running $hook_type hooks..."

    foreach hook $validation($hook_key) {
        if {[info procs $hook] ne ""} {
            log_enhanced_validation "INFO" "Executing hook: $hook"
            if {[catch {$hook $flow_type $stage_name} error]} {
                log_enhanced_validation "WARNING" "Hook $hook failed: $error"
            }
        } else {
            log_enhanced_validation "WARNING" "Hook procedure not found: $hook"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN ENHANCED EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

proc main_enhanced {} {
    global flow_type stage_name

    # Initialize enhanced validation environment
    init_enhanced_validation

    log_enhanced_validation "INFO" "Starting enhanced validation for $flow_type flow, stage: $stage_name"

    # Run pre-validation hooks
    run_enhanced_validation_hooks "pre_validation"

    # Validate output files using existing infrastructure
    set outputs_valid [validate_output_files $flow_type $stage_name]
    log_enhanced_validation "INFO" "Output files validation: [expr {$outputs_valid ? \"PASSED\" : \"FAILED\"}]"

    # Enhanced log file validation with critical error detection
    set logs_valid [validate_enhanced_log_files $flow_type $stage_name]
    log_enhanced_validation "INFO" "Enhanced log validation: [expr {$logs_valid ? \"PASSED\" : \"FAILED\"}]"

    # Validate MMMC reports if applicable using existing infrastructure
    set mmmc_valid [validate_mmmc_reports $flow_type $stage_name]
    log_enhanced_validation "INFO" "MMMC validation: [expr {$mmmc_valid ? \"PASSED\" : \"FAILED\"}]"

    # Run critical error hooks if critical errors found
    global enhanced_validation_critical_errors
    if {$enhanced_validation_critical_errors > 0} {
        run_enhanced_validation_hooks "critical_error"
    }

    # Generate enhanced summary and determine overall result
    set overall_valid [expr {$outputs_valid && $logs_valid && $mmmc_valid}]
    set enhanced_validation_passed [generate_enhanced_validation_summary]

    # Run post-validation hooks
    run_enhanced_validation_hooks "post_validation"

    # Update stage status using existing infrastructure
    if {[info procs update_stage_status] ne ""} {
        update_stage_status $enhanced_validation_passed
    }

    # Exit with appropriate code
    if {$enhanced_validation_passed} {
        log_enhanced_validation "INFO" "Enhanced validation for stage $stage_name completed successfully"
        exit 0
    } else {
        log_enhanced_validation "ERROR" "Enhanced validation for stage $stage_name failed"
        exit 1
    }
}

# Execute main enhanced validation function
if {[info script] eq $argv0} {
    main_enhanced
}