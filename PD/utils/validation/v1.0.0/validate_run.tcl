#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Run Validation Script with MMMC Support
# Description: Validates stage outputs, checks logs for errors/warnings, validates MMMC scenarios
# Usage: tclsh validate_run.tcl <FLOW_TYPE> <STAGE_NAME> <run_dir> [flow_dir]
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command line arguments
if {$argc < 3 || $argc > 4} {
    if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
        source $::env(UTILS_TCL)
    } else {
        puts "ERROR: UTILS_TCL not found in environment"
        exit 1
    }
    handle_error "Invalid number of arguments.\nUsage: tclsh validate_run.tcl <FLOW_TYPE> <STAGE_NAME> <run_dir> [flow_dir]\n  FLOW_TYPE: Any supported flow type (see flow configuration)\n  STAGE_NAME: Stage to validate (e.g., init_design, floorplan)\n  run_dir: Run directory path\n  flow_dir: Flow directory path (optional)\n\nThis script validates:\n  • Mandatory output files existence and non-empty status\n  • Log files for errors and warnings\n  • Waivered patterns against project configuration\n  • Generates comprehensive validation report"
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

# Validate flow_type against defined flow types
# Load flow configuration if not already loaded
if {![info exists flow(types)]} {
    if {[info exists ::env(FLOW_DIR)] && [file exists "$::env(FLOW_DIR)/config/flow/$::env(CONFIG_VERSION)/flow_config.tcl"]} {
        source "$::env(FLOW_DIR)/config/flow/$::env(CONFIG_VERSION)/flow_config.tcl"
    } else {
        handle_error "Cannot load flow configuration - FLOW_DIR environment variable required"
    }
}

if {$flow_type ni $flow(types)} {
    handle_error "Invalid flow_type '$flow_type'. Must be one of: [join $flow(types) {, }]"
}

# Global validation state
set validation_errors 0
set validation_warnings 0
set validation_waivers_applied 0
set validation_log_file ""

# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION AND UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

proc init_validation {} {
    global run_dir stage_name flow_dir validation_log_file MANDATORY_OUTPUT_FILES FLOW_DIR

    # Change to run directory
    if {![file exists $run_dir]} {
        handle_error "Run directory not found: $run_dir"
    }
    cd $run_dir

    # Set FLOW_DIR environment variable for other scripts
    set ::env(FLOW_DIR) $flow_dir
    set FLOW_DIR $flow_dir

    # Initialize validation log
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set validation_log_file "logs/validate_${stage_name}_${timestamp}.log"
    
    # Ensure logs directory exists
    file mkdir [file dirname $validation_log_file]
    
    # Source utilities and configuration
    if {[file exists "$flow_dir/utils/utils.tcl"]} {
        source "$flow_dir/utils/utils.tcl"
    } else {
        handle_error "Cannot find flow utilities at $flow_dir/utils/utils.tcl"
    }
    
    # Load flow configuration including MMMC settings
    if {[file exists "$flow_dir/config/flow_config.tcl"]} {
        source "$flow_dir/config/flow_config.tcl"
    } else {
        handle_warning "Cannot find flow configuration at $flow_dir/config/flow_config.tcl"
    }
    
    # Load consolidated configuration
    if {[file exists ".config.tcl"]} {
        source ".config.tcl"
    } else {
        handle_error "Configuration file not found: .config.tcl"
    }
    
    # Initialize validation log file
    set fp [open $validation_log_file w]
    puts $fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "# OMNI FLOW Validation Report"
    puts $fp "# Generated: [clock format [clock seconds]]"
    puts $fp "# Stage: $stage_name"
    puts $fp "# Run Directory: $run_dir"
    puts $fp "# ═══════════════════════════════════════════════════════════════════════════════"
    puts $fp ""
    close $fp
    
    log_validation "INFO" "Validation initialized for stage: $stage_name"
}

proc log_validation {level message} {
    global validation_log_file
    
    set timestamp [clock format [clock seconds] -format "%H:%M:%S"]
    set log_entry "\[$timestamp\] \[$level\] $message"
    
    # Print to console using utils.tcl functions (with logo prefix)
    switch $level {
        "INFO" {
            handle_info "$message"
        }
        "WARNING" {
            handle_warning "$message"  
        }
        "ERROR" {
            handle_error "$message"
        }
        default {
            puts $log_entry
        }
    }
    
    # Write to validation log
    if {$validation_log_file ne ""} {
        set fp [open $validation_log_file a]
        puts $fp $log_entry
        close $fp
    }
}

proc increment_error {} {
    global validation_errors
    incr validation_errors
}

proc increment_warning {} {
    global validation_warnings
    incr validation_warnings
}

proc increment_waiver {} {
    global validation_waivers_applied
    incr validation_waivers_applied
}

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT FILE VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

proc get_mandatory_output_files {flow_type stage_name} {
    global MANDATORY_OUTPUT_FILES
    
    set flow_type_upper [string toupper $flow_type]
    set stage_key "$flow_type_upper,$stage_name"
    
    if {[info exists MANDATORY_OUTPUT_FILES($stage_key)]} {
        return $MANDATORY_OUTPUT_FILES($stage_key)
    } else {
        log_validation "WARNING" "No mandatory outputs defined for $stage_key"
        return {}
    }
}

proc validate_output_files {flow_type stage_name} {
    log_validation "INFO" "Validating mandatory output files for $stage_name..."
    
    set mandatory_files [get_mandatory_output_files $flow_type $stage_name]
    set missing_files {}
    set empty_files {}
    set valid_files {}
    
    foreach file_path $mandatory_files {
        if {![file exists $file_path]} {
            lappend missing_files $file_path
            log_validation "ERROR" "Missing mandatory output: $file_path"
            increment_error
        } elseif {[file size $file_path] == 0} {
            lappend empty_files $file_path
            log_validation "ERROR" "Empty mandatory output: $file_path"
            increment_error
        } else {
            lappend valid_files $file_path
            log_validation "INFO" "✓ Valid output: $file_path ([format_file_size [file size $file_path]])"
        }
    }
    
    # Summary
    set total_files [llength $mandatory_files]
    set valid_count [llength $valid_files]
    set missing_count [llength $missing_files]
    set empty_count [llength $empty_files]
    
    log_validation "INFO" "Output file validation summary:"
    log_validation "INFO" "  Total mandatory files: $total_files"
    log_validation "INFO" "  Valid files: $valid_count"
    log_validation "INFO" "  Missing files: $missing_count"
    log_validation "INFO" "  Empty files: $empty_count"
    
    if {$missing_count > 0 || $empty_count > 0} {
        log_validation "ERROR" "Output file validation FAILED"
        return false
    } else {
        log_validation "INFO" "Output file validation PASSED"
        return true
    }
}

proc format_file_size {size_bytes} {
    if {$size_bytes < 1024} {
        return "${size_bytes}B"
    } elseif {$size_bytes < 1048576} {
        return "[format %.1f [expr {$size_bytes / 1024.0}]]KB"
    } else {
        return "[format %.1f [expr {$size_bytes / 1048576.0}]]MB"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# LOG FILE VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

proc get_stage_log_files {flow_type stage_name} {
    global tools
    
    set log_files {}
    set flow_type_lower [string tolower $flow_type]
    
    # Determine tool for this stage/flow
    set tool_name ""
    if {[info exists tools($flow_type_lower,tool)]} {
        set tool_name $tools($flow_type_lower,tool)
    }
    
    # Standard log file patterns
    set log_patterns [list \
        "logs/${stage_name}_*.log" \
        "logs/${flow_type}_${stage_name}_*.log" \
        "work/${flow_type}/${stage_name}/*.log" \
        "work/${flow_type}/${stage_name}/run/*.log" \
    ]
    
    # Tool-specific log patterns
    if {$tool_name ne ""} {
        lappend log_patterns "logs/${stage_name}_${tool_name}_*.log"
        lappend log_patterns "work/${flow_type}/${stage_name}/${tool_name}.log"
    }
    
    # Find matching log files
    foreach pattern $log_patterns {
        set matches [glob -nocomplain $pattern]
        foreach match $matches {
            if {[lsearch $log_files $match] == -1} {
                lappend log_files $match
            }
        }
    }
    
    return $log_files
}

proc get_waiver_patterns {flow_type stage_name} {
    global project
    
    set waiver_patterns {}
    
    # Get global waivers
    if {[info exists project(validation,global_waivers)]} {
        set waiver_patterns [concat $waiver_patterns $project(validation,global_waivers)]
    }
    
    # Get stage-specific waivers
    set stage_key "validation,${stage_name}_waivers"
    if {[info exists project($stage_key)]} {
        set waiver_patterns [concat $waiver_patterns $project($stage_key)]
    }
    
    # Get flow-specific waivers
    set flow_key "validation,${flow_type}_waivers"
    if {[info exists project($flow_key)]} {
        set waiver_patterns [concat $waiver_patterns $project($flow_key)]
    }
    
    return $waiver_patterns
}

proc is_waivered {message waiver_patterns} {
    foreach pattern $waiver_patterns {
        if {[regexp -nocase $pattern $message]} {
            return $pattern
        }
    }
    return ""
}

proc validate_log_files {flow_type stage_name} {
    log_validation "INFO" "Validating log files for $stage_name..."
    
    set log_files [get_stage_log_files $flow_type $stage_name]
    
    if {[llength $log_files] == 0} {
        log_validation "WARNING" "No log files found for $stage_name"
        increment_warning
        return true
    }
    
    set waiver_patterns [get_waiver_patterns $flow_type $stage_name]
    log_validation "INFO" "Using [llength $waiver_patterns] waiver patterns"
    
    set total_errors 0
    set total_warnings 0
    set waivered_errors 0
    set waivered_warnings 0
    
    foreach log_file $log_files {
        log_validation "INFO" "Analyzing log file: $log_file"
        
        if {![file exists $log_file]} {
            log_validation "WARNING" "Log file not found: $log_file"
            increment_warning
            continue
        }
        
        set fp [open $log_file r]
        set line_num 0
        
        while {[gets $fp line] >= 0} {
            incr line_num
            
            # Check for error patterns
            if {[regexp -nocase {(error|fatal|fail|abort)} $line]} {
                incr total_errors
                
                set waiver_pattern [is_waivered $line $waiver_patterns]
                if {$waiver_pattern ne ""} {
                    incr waivered_errors
                    increment_waiver
                    log_validation "WAIVER" "Error waivered at $log_file:$line_num (pattern: $waiver_pattern)"
                    log_validation "WAIVER" "  Line: [string trim $line]"
                } else {
                    increment_error
                    log_validation "ERROR" "Unwaivered error at $log_file:$line_num"
                    log_validation "ERROR" "  Line: [string trim $line]"
                }
            }
            
            # Check for warning patterns
            if {[regexp -nocase {(warning|caution)} $line]} {
                incr total_warnings
                
                set waiver_pattern [is_waivered $line $waiver_patterns]
                if {$waiver_pattern ne ""} {
                    incr waivered_warnings
                    increment_waiver
                    log_validation "WAIVER" "Warning waivered at $log_file:$line_num (pattern: $waiver_pattern)"
                } else {
                    increment_warning
                    log_validation "WARNING" "Unwaivered warning at $log_file:$line_num"
                    log_validation "WARNING" "  Line: [string trim $line]"
                }
            }
        }
        
        close $fp
    }
    
    # Summary
    log_validation "INFO" "Log validation summary:"
    log_validation "INFO" "  Log files analyzed: [llength $log_files]"
    log_validation "INFO" "  Total errors found: $total_errors"
    log_validation "INFO" "  Total warnings found: $total_warnings"
    log_validation "INFO" "  Waivered errors: $waivered_errors"
    log_validation "INFO" "  Waivered warnings: $waivered_warnings"
    log_validation "INFO" "  Unwaivered errors: [expr {$total_errors - $waivered_errors}]"
    log_validation "INFO" "  Unwaivered warnings: [expr {$total_warnings - $waivered_warnings}]"
    
    # Determine pass/fail
    set unwaivered_errors [expr {$total_errors - $waivered_errors}]
    if {$unwaivered_errors > 0} {
        log_validation "ERROR" "Log validation FAILED ($unwaivered_errors unwaivered errors)"
        return false
    } else {
        log_validation "INFO" "Log validation PASSED"
        return true
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPREHENSIVE VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

proc generate_validation_summary {} {
    global validation_errors validation_warnings validation_waivers_applied
    global stage_name validation_log_file
    
    log_validation "INFO" "═══════════════════════════════════════════════════════"
    log_validation "INFO" "VALIDATION SUMMARY FOR STAGE: $stage_name"
    log_validation "INFO" "═══════════════════════════════════════════════════════"
    log_validation "INFO" "Total Errors: $validation_errors"
    log_validation "INFO" "Total Warnings: $validation_warnings"
    log_validation "INFO" "Waivers Applied: $validation_waivers_applied"
    
    if {$validation_errors > 0} {
        log_validation "ERROR" "VALIDATION FAILED: $validation_errors error(s) found"
        log_validation "INFO" "Validation report: $validation_log_file"
        return false
    } else {
        log_validation "INFO" "VALIDATION PASSED: No errors found"
        if {$validation_warnings > 0} {
            log_validation "INFO" "Note: $validation_warnings warning(s) found but stage considered passing"
        }
        log_validation "INFO" "Validation report: $validation_log_file"
        return true
    }
}

proc update_stage_status {passed} {
    global stage_name
    
    if {$passed} {
        log_stage_status $stage_name "VALIDATED" "Stage validation passed"
    } else {
        log_stage_status $stage_name "ERROR" "Stage validation failed"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MMMC VALIDATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

proc is_mmmc_enabled_stage {stage_name} {
    # Check if MMMC is enabled for this stage
    global flow
    
    # Debug: Check what's available
    if {[info exists flow(mmmc,enabled)]} {
        puts "DEBUG: flow(mmmc,enabled) = $flow(mmmc,enabled)"
    } else {
        puts "DEBUG: flow(mmmc,enabled) not defined"
    }
    
    if {[info exists flow(mmmc,enabled_stages)]} {
        puts "DEBUG: flow(mmmc,enabled_stages) = $flow(mmmc,enabled_stages)"
    } else {
        puts "DEBUG: flow(mmmc,enabled_stages) not defined"
    }
    
    if {![info exists flow(mmmc,enabled)] || !$flow(mmmc,enabled)} {
        return false
    }
    
    if {[info exists flow(mmmc,enabled_stages)] && [lsearch $flow(mmmc,enabled_stages) $stage_name] != -1} {
        return true
    }
    
    return false
}

proc validate_mmmc_reports {flow_type stage_name} {
    global validation_errors validation_warnings

    if {![is_mmmc_enabled_stage $stage_name]} {
        log_validation "INFO" "MMMC not enabled for stage $stage_name, skipping MMMC validation"
        return true
    }

    log_validation "INFO" "Validating MMMC reports for stage $stage_name"

    set mmmc_valid true
    set flow_type_upper [string toupper $flow_type]
    set flow_type_lower [string tolower $flow_type]

    # Extract base stage type from stage name (e.g., "signoff1" -> "signoff")
    set base_stage $stage_name
    if {[regexp {^(.+?)(\d+)$} $stage_name -> base suffix]} {
        set base_stage $base
    }

    # Get MMMC report expectations from config if available
    set expected_mmmc_files [list]
    set use_config false

    # Try to get MMMC report config from flow config array
    if {[info exists ::${flow_type_lower}] && [array exists ::${flow_type_lower}]} {
        upvar #0 $flow_type_lower flow_config

        # Add base MMMC reports (expected for all MMMC-enabled stages)
        if {[info exists flow_config(mmmc_reports,base)]} {
            foreach report_type $flow_config(mmmc_reports,base) {
                lappend expected_mmmc_files "work/$flow_type_upper/$stage_name/reports/${report_type}_${stage_name}.rpt"
            }
            set use_config true
        }

        # Add base MMMC utility files
        if {[info exists flow_config(mmmc_reports,base_files)]} {
            foreach file_type $flow_config(mmmc_reports,base_files) {
                lappend expected_mmmc_files "work/$flow_type_upper/$stage_name/utils/${file_type}_${stage_name}.tcl"
            }
        }

        # Add stage-specific MMMC reports
        if {[info exists flow_config(mmmc_reports,$base_stage)]} {
            foreach report_type $flow_config(mmmc_reports,$base_stage) {
                if {$report_type eq "mmmc_final_summary"} {
                    lappend expected_mmmc_files "work/$flow_type_upper/$stage_name/reports/${report_type}.rpt"
                } else {
                    lappend expected_mmmc_files "work/$flow_type_upper/$stage_name/reports/${report_type}_${stage_name}.rpt"
                }
            }
        }
    }

    # Fallback to defaults if config not available
    if {!$use_config} {
        set expected_mmmc_files [list \
            "work/$flow_type_upper/$stage_name/reports/mmmc_timing_${stage_name}.rpt" \
            "work/$flow_type_upper/$stage_name/reports/mmmc_scenarios_${stage_name}.rpt" \
            "work/$flow_type_upper/$stage_name/utils/mmmc_setup_${stage_name}.tcl" \
        ]
    }
    
    # Validate each MMMC file
    foreach mmmc_file $expected_mmmc_files {
        if {[file exists $mmmc_file]} {
            set file_size [file size $mmmc_file]
            if {$file_size > 0} {
                log_validation "PASS" "MMMC file found and non-empty: $mmmc_file ([format_file_size $file_size])"
                
                # Additional validation for key MMMC reports
                if {[string match "*mmmc_timing_*.rpt" $mmmc_file]} {
                    set timing_valid [validate_mmmc_timing_report $mmmc_file]
                    if {!$timing_valid} {
                        set mmmc_valid false
                    }
                }
                
                if {[string match "*mmmc_scenarios_*.rpt" $mmmc_file]} {
                    set scenarios_valid [validate_mmmc_scenarios_report $mmmc_file]
                    if {!$scenarios_valid} {
                        set mmmc_valid false
                    }
                }
                
            } else {
                log_validation "FAIL" "MMMC file is empty: $mmmc_file"
                incr validation_errors
                set mmmc_valid false
            }
        } else {
            # Check if it's a mandatory or optional MMMC file
            if {[string match "*mmmc_timing_*.rpt" $mmmc_file] || [string match "*mmmc_scenarios_*.rpt" $mmmc_file]} {
                log_validation "FAIL" "Mandatory MMMC file missing: $mmmc_file"
                incr validation_errors
                set mmmc_valid false
            } else {
                log_validation "WARN" "Optional MMMC file missing: $mmmc_file"
                incr validation_warnings
            }
        }
    }
    
    return $mmmc_valid
}

proc validate_mmmc_timing_report {timing_report} {
    log_validation "INFO" "Validating MMMC timing report: $timing_report"
    
    if {![file exists $timing_report]} {
        log_validation "FAIL" "MMMC timing report not found: $timing_report"
        return false
    }
    
    set fp [open $timing_report "r"]
    set content [read $fp]
    close $fp
    
    set valid true
    
    # Check for key MMMC timing indicators
    set mmmc_indicators [list \
        "Analysis View" \
        "Scenario" \
        "Corner" \
        "Setup Check" \
        "Hold Check" \
    ]
    
    foreach indicator $mmmc_indicators {
        if {[string first $indicator $content] == -1} {
            log_validation "WARN" "MMMC timing report missing indicator: $indicator"
        }
    }
    
    # Check for critical timing violations across scenarios
    if {[regexp -nocase {worst.*slack.*-[0-9]+} $content]} {
        log_validation "WARN" "MMMC timing report shows negative slack violations"
    }
    
    # Look for MMMC-specific timing summary
    if {[string first "Multi-Corner" $content] != -1 || [string first "MMMC" $content] != -1} {
        log_validation "PASS" "MMMC timing report contains multi-corner analysis"
    } else {
        log_validation "WARN" "MMMC timing report may not contain proper multi-corner analysis"
    }
    
    log_validation "INFO" "MMMC timing report validation completed"
    return $valid
}

proc validate_mmmc_scenarios_report {scenarios_report} {
    log_validation "INFO" "Validating MMMC scenarios report: $scenarios_report"
    
    if {![file exists $scenarios_report]} {
        log_validation "FAIL" "MMMC scenarios report not found: $scenarios_report"
        return false
    }
    
    set fp [open $scenarios_report "r"]
    set content [read $fp]
    close $fp
    
    # Expected scenarios based on stage
    global stage_name flow
    set expected_scenarios {}
    if {[info exists flow(mmmc,scenarios,$stage_name)]} {
        set expected_scenarios $flow(mmmc,scenarios,$stage_name)
    }
    
    set valid true
    set scenarios_found 0
    
    # Check for each expected scenario
    foreach scenario $expected_scenarios {
        if {[string first $scenario $content] != -1} {
            incr scenarios_found
            log_validation "PASS" "MMMC scenario found in report: $scenario"
        } else {
            log_validation "WARN" "Expected MMMC scenario not found in report: $scenario"
        }
    }
    
    if {$scenarios_found == 0} {
        log_validation "FAIL" "No expected MMMC scenarios found in scenarios report"
        set valid false
    } else {
        log_validation "PASS" "Found $scenarios_found MMMC scenarios in report"
    }
    
    # Check for analysis view information
    if {[string first "Analysis View" $content] != -1} {
        log_validation "PASS" "MMMC scenarios report contains analysis view information"
    } else {
        log_validation "WARN" "MMMC scenarios report missing analysis view information"
    }
    
    log_validation "INFO" "MMMC scenarios report validation completed"
    return $valid
}

proc validate_mmmc_setup_script {stage_name} {
    log_validation "INFO" "Validating MMMC setup script for stage $stage_name"
    
    set flow_type_upper [string toupper $::flow_type]
    set setup_script "work/$flow_type_upper/$stage_name/utils/mmmc_setup_${stage_name}.tcl"
    
    if {![file exists $setup_script]} {
        log_validation "FAIL" "MMMC setup script not found: $setup_script"
        return false
    }
    
    set fp [open $setup_script "r"]
    set content [read $fp]
    close $fp
    
    set valid true
    
    # Check for key MMMC setup commands
    set mmmc_commands [list \
        "create_analysis_view" \
        "set_analysis_view" \
        "library_set" \
        "rc_corner" \
    ]
    
    foreach command $mmmc_commands {
        if {[string first $command $content] != -1} {
            log_validation "PASS" "MMMC setup script contains command: $command"
        } else {
            log_validation "WARN" "MMMC setup script missing command: $command"
        }
    }
    
    # Check for scenario definitions
    global flow
    if {[info exists flow(mmmc,scenarios,$stage_name)]} {
        set expected_scenarios $flow(mmmc,scenarios,$stage_name)
        foreach scenario $expected_scenarios {
            if {[string first $scenario $content] != -1} {
                log_validation "PASS" "MMMC setup script defines scenario: $scenario"
            } else {
                log_validation "WARN" "MMMC setup script missing scenario: $scenario"
            }
        }
    }
    
    log_validation "INFO" "MMMC setup script validation completed"
    return $valid
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

proc main {} {
    global flow_type stage_name
    
    # Initialize validation environment
    init_validation
    
    log_validation "INFO" "Starting validation for $flow_type flow, stage: $stage_name"
    
    # Validate output files
    set outputs_valid [validate_output_files $flow_type $stage_name]
    
    # Validate log files
    set logs_valid [validate_log_files $flow_type $stage_name]
    
    # Validate MMMC reports if applicable
    set mmmc_valid [validate_mmmc_reports $flow_type $stage_name]
    
    # Generate summary and determine overall result
    set overall_valid [expr {$outputs_valid && $logs_valid && $mmmc_valid}]
    set validation_passed [generate_validation_summary]
    
    # Update stage status
    update_stage_status $validation_passed
    
    # Exit with appropriate code
    if {$validation_passed} {
        log_validation "INFO" "Stage $stage_name validation completed successfully"
        exit 0
    } else {
        log_validation "ERROR" "Stage $stage_name validation failed"
        exit 1
    }
}

# Execute main function
if {[info script] eq $argv0} {
    main
}