#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Error Handling Utilities
#
# Description: Standardized error handling procedures with version-based architecture
# Version: 1.0.0
# Author: CBFlow Management System
#
# Features:
# - Consistent error message formatting across all scripts
# - Severity levels: INFO, WARNING, ERROR
# - Color-coded output with timestamps
# - Logging capabilities
# - Exit code management
# - Environment variable integration
# - Version-based configuration loading
#===============================================================================

# Clean namespace for CBFlow error handling
namespace eval ::CBFlowError {

    #===========================================================================
    # VERSION AND CONSTANTS
    #===========================================================================

    variable ERROR_VERSION "1.0.0"
    variable ERROR_DATE "2025-09-24"
    # Color definitions
    variable colors
    array set colors {
        RED     ""
        GREEN   ""
        YELLOW  ""
        BLUE    ""
        PURPLE  ""
        CYAN    ""
        WHITE   ""
        BOLD    ""
        NC      ""
    }

    # Error symbols
    variable symbols
    array set symbols {
        INFO    "ℹ"
        WARNING "⚠"
        ERROR   "✗"
        SUCCESS "✓"
        DEBUG   "🔍"
        CONFIG  "⚙"
        FILE    "📁"
        NETWORK "🌐"
        TIME    "⏰"
    }

    # Configuration
    variable config
    array set config {
        enable_colors       1
        enable_timestamps   1
        enable_logging      0
        log_file           ""
        exit_on_error      1
        debug_mode         0
    }

    # Error counters
    variable counters
    array set counters {
        info     0
        warning  0
        error    0
        debug    0
    }

    #===========================================================================
    # ENVIRONMENT VALIDATION PROCEDURES
    #===========================================================================

    proc validate_environment {} {
        # Environment validation for error handling system
        # Note: Error handling is foundational, so it has minimal dependencies

        # Check for FLOW_ROOT or calculate it if needed
        if {![info exists ::env(FLOW_ROOT)] || $::env(FLOW_ROOT) eq ""} {
            # Try to calculate from current script location
            set script_dir [file dirname [file normalize [info script]]]
            set utils_parent [file dirname [file dirname $script_dir]]
            set calculated_flow_root [file dirname $utils_parent]
            set ::env(FLOW_ROOT) $calculated_flow_root
        }

        # Set default versions if not provided
        set version_vars {
            FLOW_CONFIG_VERSION
            PROJECT_CONFIG_VERSION
            UTILITIES_VERSION
        }

        foreach var $version_vars {
            if {![info exists ::env($var)] || $::env($var) eq ""} {
                set ::env($var) "v1.0.0"
            }
        }

        return 1
    }

    #===========================================================================
    # MAIN INITIALIZATION PROCEDURE
    #===========================================================================

    proc initialize_error_handling {} {
        # Initialize error handling system
        validate_environment
        return 1
    }
}

#===============================================================================
# CONFIGURATION PROCEDURES
#===============================================================================

proc ::CBFlowError::configure {args} {
    variable config

    foreach {key value} $args {
        switch -- $key {
            -colors {
                set config(enable_colors) $value
            }
            -timestamps {
                set config(enable_timestamps) $value
            }
            -logging {
                set config(enable_logging) $value
            }
            -logfile {
                set config(log_file) $value
                set config(enable_logging) 1
            }
            -exit_on_error {
                set config(exit_on_error) $value
            }
            -debug {
                set config(debug_mode) $value
            }
            default {
                CBFLOW_WARNING "Unknown configuration option: $key"
            }
        }
    }
}

proc ::CBFlowError::get_stats {} {
    variable counters
    return [array get counters]
}

proc ::CBFlowError::reset_stats {} {
    variable counters
    array set counters {
        info     0
        warning  0
        error    0
        debug    0
    }
}

#===============================================================================
# CORE ERROR HANDLING PROCEDURES
#===============================================================================

proc ::CBFlowError::format_message {level symbol message {context ""}} {
    variable config
    variable colors

    set timestamp ""
    if {$config(enable_timestamps)} {
        set timestamp "\[[clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]\] "
    }

    # Get component name for message prefix
    set component ""
    if {$context ne ""} {
        set component $context
    } elseif {[info exists ::logo(name)]} {
        set component $::logo(name)
    } else {
        set component "CBFlow"
    }

    set color_start ""
    set color_end ""
    if {$config(enable_colors)} {
        switch $level {
            "INFO"    { set color_start "$colors(CYAN)" }
            "WARNING" { set color_start "$colors(YELLOW)" }
            "ERROR"   { set color_start "$colors(RED)" }
            "SUCCESS" { set color_start "$colors(GREEN)" }
            "DEBUG"   { set color_start "$colors(PURPLE)" }
            default   { set color_start "$colors(WHITE)" }
        }
        set color_end $colors(NC)
    }

    return "${timestamp}${color_start}\[${level}\] \[${component}\]${color_end} ${message}"
}

proc ::CBFlowError::log_message {formatted_message} {
    variable config

    if {$config(enable_logging) && $config(log_file) ne ""} {
        if {[catch {
            set fp [open $config(log_file) a]
            # Strip ANSI colors for log file
            set clean_message [regsub -all {\033\[[0-9;]*m} $formatted_message ""]
            puts $fp $clean_message
            close $fp
        } error]} {
            puts stderr "Warning: Failed to write to log file: $error"
        }
    }
}

proc ::CBFlowError::increment_counter {level} {
    variable counters
    set level [string tolower $level]
    if {[info exists counters($level)]} {
        incr counters($level)
    }
}

#===============================================================================
# PUBLIC ERROR HANDLING PROCEDURES
#===============================================================================

proc CBFLOW_INFO {message {context ""}} {
    variable ::CBFlowError::symbols
    variable ::CBFlowError::config

    ::CBFlowError::increment_counter "info"

    set formatted [::CBFlowError::format_message "INFO" $symbols(INFO) $message $context]
    puts $formatted
    ::CBFlowError::log_message $formatted
}

proc CBFLOW_WARNING {message {context ""}} {
    variable ::CBFlowError::symbols
    variable ::CBFlowError::config

    ::CBFlowError::increment_counter "warning"

    set formatted [::CBFlowError::format_message "WARNING" $symbols(WARNING) $message $context]
    puts $formatted
    ::CBFlowError::log_message $formatted
}

proc CBFLOW_ERROR {message {context ""} {exit_code 1}} {
    variable ::CBFlowError::symbols
    variable ::CBFlowError::config

    ::CBFlowError::increment_counter "error"

    set formatted [::CBFlowError::format_message "ERROR" $symbols(ERROR) $message $context]
    puts stderr $formatted
    ::CBFlowError::log_message $formatted

    if {$config(exit_on_error)} {
        exit $exit_code
    }

    return $exit_code
}

proc CBFLOW_SUCCESS {message {context ""}} {
    variable ::CBFlowError::symbols

    set formatted [::CBFlowError::format_message "SUCCESS" $symbols(SUCCESS) $message $context]
    puts $formatted
    ::CBFlowError::log_message $formatted
}

proc CBFLOW_DEBUG {message {context ""}} {
    variable ::CBFlowError::symbols
    variable ::CBFlowError::config

    if {!$config(debug_mode)} {
        return
    }

    ::CBFlowError::increment_counter "debug"

    set formatted [::CBFlowError::format_message "DEBUG" $symbols(DEBUG) $message $context]
    puts $formatted
    ::CBFlowError::log_message $formatted
}

#===============================================================================
# SPECIALIZED ERROR PROCEDURES
#===============================================================================

proc CBFLOW_CONFIG_ERROR {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_ERROR "$symbols(CONFIG) $message" $context
}

proc CBFLOW_CONFIG_WARNING {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_WARNING "$symbols(CONFIG) $message" $context
}

proc CBFLOW_CONFIG_INFO {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_INFO "$symbols(CONFIG) $message" $context
}

proc CBFLOW_FILE_ERROR {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_ERROR "$symbols(FILE) $message" $context
}

proc CBFLOW_FILE_WARNING {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_WARNING "$symbols(FILE) $message" $context
}

proc CBFLOW_FILE_INFO {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_INFO "$symbols(FILE) $message" $context
}

proc CBFLOW_TIME_INFO {message {context ""}} {
    variable ::CBFlowError::symbols
    CBFLOW_INFO "$symbols(TIME) $message" $context
}

#===============================================================================
# VALIDATION AND UTILITY PROCEDURES
#===============================================================================

proc CBFLOW_VALIDATE_FILE {filepath {context ""}} {
    if {![file exists $filepath]} {
        CBFLOW_FILE_ERROR "File not found: $filepath" $context
        return 0
    }

    if {![file readable $filepath]} {
        CBFLOW_FILE_ERROR "File not readable: $filepath" $context
        return 0
    }

    return 1
}

proc CBFLOW_VALIDATE_DIR {dirpath {context ""}} {
    if {![file exists $dirpath]} {
        CBFLOW_FILE_ERROR "Directory not found: $dirpath" $context
        return 0
    }

    if {![file isdirectory $dirpath]} {
        CBFLOW_FILE_ERROR "Path is not a directory: $dirpath" $context
        return 0
    }

    return 1
}

proc CBFLOW_VALIDATE_REQUIRED {varname value {context ""}} {
    if {$value eq "" || ![info exists value]} {
        CBFLOW_CONFIG_ERROR "Required parameter '$varname' is missing or empty" $context
        return 0
    }
    return 1
}

proc CBFLOW_VALIDATE_CHOICE {varname value choices {context ""}} {
    if {$value ni $choices} {
        CBFLOW_CONFIG_ERROR "Invalid value '$value' for '$varname'. Valid choices: [join $choices {, }]" $context
        return 0
    }
    return 1
}

#===============================================================================
# EXCEPTION HANDLING PROCEDURES
#===============================================================================

proc CBFLOW_TRY {script error_var error_script} {
    upvar $error_var error
    if {[catch {uplevel $script} error]} {
        uplevel $error_script
        return 0
    }
    return 1
}

proc CBFLOW_CATCH_AND_LOG {script {context ""}} {
    if {[catch {uplevel $script} error]} {
        CBFLOW_ERROR "Exception caught: $error" $context
        return 0
    }
    return 1
}

#===============================================================================
# PROGRESS AND STATUS PROCEDURES
#===============================================================================

proc CBFLOW_HEADER {title} {
    variable ::CBFlowError::colors
    variable ::CBFlowError::config

    set color_start ""
    set color_end ""
    if {$config(enable_colors)} {
        set color_start "$colors(CYAN)$colors(BOLD)"
        set color_end $colors(NC)
    }

    set separator [string repeat "=" [string length $title]]
    puts ""
    puts "${color_start}${title}${color_end}"
    puts "${color_start}${separator}${color_end}"
    puts ""
}

proc CBFLOW_SECTION {title} {
    variable ::CBFlowError::colors
    variable ::CBFlowError::config

    set color_start ""
    set color_end ""
    if {$config(enable_colors)} {
        set color_start "$colors(YELLOW)$colors(BOLD)"
        set color_end $colors(NC)
    }

    puts ""
    puts "${color_start}${title}:${color_end}"
}

proc CBFLOW_STEP {step_num total_steps description} {
    CBFLOW_INFO "Step $step_num/$total_steps: $description" "PROGRESS"
}

proc CBFLOW_SUMMARY {} {
    variable ::CBFlowError::counters

    CBFLOW_SECTION "CBFlow Execution Summary"
    CBFLOW_INFO "Total messages: [expr {$counters(info) + $counters(warning) + $counters(error)}]"
    CBFLOW_INFO "Info messages: $counters(info)"

    if {$counters(warning) > 0} {
        CBFLOW_WARNING "Warning messages: $counters(warning)"
    } else {
        CBFLOW_SUCCESS "Warning messages: $counters(warning)"
    }

    if {$counters(error) > 0} {
        CBFLOW_ERROR "Error messages: $counters(error)" "" 0
    } else {
        CBFLOW_SUCCESS "Error messages: $counters(error)"
    }

    if {$counters(debug) > 0} {
        CBFLOW_DEBUG "Debug messages: $counters(debug)"
    }
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Initialize the error handling system
namespace eval ::CBFlowError {
    # Set default configuration based on terminal capabilities
    if {[info exists ::env(TERM)] && $::env(TERM) ne "dumb"} {
        set config(enable_colors) 1
    } else {
        set config(enable_colors) 0
    }
}

# Export the public procedures
namespace export CBFLOW_INFO CBFLOW_WARNING CBFLOW_ERROR CBFLOW_SUCCESS CBFLOW_DEBUG
namespace export CBFLOW_CONFIG_* CBFLOW_FILE_* CBFLOW_TIME_*
namespace export CBFLOW_VALIDATE_* CBFLOW_TRY CBFLOW_CATCH_AND_LOG
namespace export CBFLOW_HEADER CBFLOW_SECTION CBFLOW_STEP CBFLOW_SUMMARY

#===============================================================================
# AUTO-INITIALIZATION
#===============================================================================

# Initialize error handling when sourced
if {![info exists ::cbflow_error_utils_loaded]} {
    if {[::CBFlowError::initialize_error_handling]} {
        set ::cbflow_error_utils_loaded true
    }
}

# Legacy completion message for immediate feedback
# CBFlow Error Handling Utilities loaded silently