#!/usr/bin/env tclsh
#===============================================================================
# CBFlow XTerm Display Utilities
#
# Description: XTerm integration for displaying critical errors with red color
#              and cursor positioning to specific error lines
# Version: 1.0.0
# Author: CBFlow Management System
#
# Features:
# - Red color xterm display for critical errors
# - Cursor positioning to specific error lines
# - Alternative terminal support
# - Error context display
# - Integration with CBFlow error handling
#===============================================================================

# Clean namespace for CBFlow XTerm utilities
namespace eval ::CBFlowXTerm {

    #===========================================================================
    # VERSION AND CONSTANTS
    #===========================================================================

    variable XTERM_VERSION "1.0.0"
    variable XTERM_DATE "2025-10-02"

    # Default configuration
    variable config
    array set config {
        default_fg_color    "red"
        default_bg_color    "black"
        default_title       "CBFlow Critical Error"
        default_geometry    "120x40"
        context_lines       5
        timeout_seconds     30
        debug_mode          0
    }

    # Terminal availability cache
    variable terminal_cache
    array set terminal_cache {}

    # Error display queue
    variable error_queue {}

    #===========================================================================
    # TERMINAL DETECTION PROCEDURES
    #===========================================================================

    proc detect_available_terminals {} {
        variable terminal_cache

        set terminals {
            xterm
            gnome-terminal
            konsole
            rxvt
            urxvt
            terminology
            mate-terminal
            xfce4-terminal
        }

        set available_terminals {}

        foreach terminal $terminals {
            if {![info exists terminal_cache($terminal)]} {
                set terminal_cache($terminal) [check_terminal_available $terminal]
            }

            if {$terminal_cache($terminal)} {
                lappend available_terminals $terminal
            }
        }

        return $available_terminals
    }

    proc check_terminal_available {terminal} {
        if {[catch {exec which $terminal} result]} {
            return 0
        }
        return 1
    }

    proc get_best_terminal {} {
        set available [detect_available_terminals]

        if {[llength $available] == 0} {
            return ""
        }

        # Preference order: xterm, gnome-terminal, konsole, others
        set preference_order {xterm gnome-terminal konsole rxvt urxvt}

        foreach preferred $preference_order {
            if {$preferred in $available} {
                return $preferred
            }
        }

        # Return first available if none of the preferred ones are found
        return [lindex $available 0]
    }

    #===========================================================================
    # ERROR LINE DETECTION PROCEDURES
    #===========================================================================

    proc find_error_lines {log_file error_patterns} {
        variable config

        if {![file exists $log_file]} {
            handle_error "Log file not found: $log_file"
            return {}
        }

        set error_lines {}
        set fp [open $log_file r]
        set line_num 0

        while {[gets $fp line] >= 0} {
            incr line_num

            # Check each error pattern
            foreach pattern $error_patterns {
                if {[regexp -nocase $pattern $line]} {
                    lappend error_lines [list $line_num $line $pattern]
                    if {$config(debug_mode)} {
                        puts "DEBUG: Found error at line $line_num: [string range $line 0 80]..."
                    }
                    break
                }
            }
        }

        close $fp
        return $error_lines
    }

    proc find_critical_error_line {log_file critical_patterns} {
        set error_lines [find_error_lines $log_file $critical_patterns]

        if {[llength $error_lines] == 0} {
            return 0
        }

        # Return first critical error line number
        return [lindex [lindex $error_lines 0] 0]
    }

    proc get_error_context {log_file error_line} {
        variable config

        if {![file exists $log_file]} {
            return ""
        }

        set context_start [expr {max(1, $error_line - $config(context_lines))}]
        set context_end [expr {$error_line + $config(context_lines)}]

        set fp [open $log_file r]
        set current_line 0
        set context_lines {}

        while {[gets $fp line] >= 0} {
            incr current_line

            if {$current_line >= $context_start && $current_line <= $context_end} {
                set marker [expr {$current_line == $error_line ? ">>> " : "    "}]
                lappend context_lines "$marker$current_line: $line"
            }

            if {$current_line > $context_end} {
                break
            }
        }

        close $fp
        return [join $context_lines "\n"]
    }

    #===========================================================================
    # XTERM COMMAND CONSTRUCTION
    #===========================================================================

    proc build_xterm_command {terminal log_file error_line {fg_color ""} {bg_color ""} {title ""}} {
        variable config

        # Use defaults if not specified
        if {$fg_color eq ""} { set fg_color $config(default_fg_color) }
        if {$bg_color eq ""} { set bg_color $config(default_bg_color) }
        if {$title eq ""} { set title $config(default_title) }

        switch $terminal {
            "xterm" {
                return [list xterm \
                    -fg $fg_color \
                    -bg $bg_color \
                    -title $title \
                    -geometry $config(default_geometry) \
                    -e less +$error_line $log_file]
            }
            "gnome-terminal" {
                return [list gnome-terminal \
                    --title=$title \
                    --geometry=$config(default_geometry) \
                    -- less +$error_line $log_file]
            }
            "konsole" {
                return [list konsole \
                    --title $title \
                    -e less +$error_line $log_file]
            }
            "rxvt" - "urxvt" {
                return [list $terminal \
                    -fg $fg_color \
                    -bg $bg_color \
                    -title $title \
                    -geometry $config(default_geometry) \
                    -e less +$error_line $log_file]
            }
            default {
                # Generic terminal command
                return [list $terminal -e less +$error_line $log_file]
            }
        }
    }

    proc build_alternative_viewer_command {log_file error_line} {
        # Fallback to system pager with line positioning
        if {[check_terminal_available "less"]} {
            return [list less +$error_line $log_file]
        } elseif {[check_terminal_available "more"]} {
            return [list more +$error_line $log_file]
        } elseif {[check_terminal_available "vi"]} {
            return [list vi +$error_line $log_file]
        } else {
            return [list cat $log_file]
        }
    }

    #===========================================================================
    # MAIN XTERM DISPLAY PROCEDURES
    #===========================================================================

    proc launch_error_viewer {log_file error_line {options {}}} {
        variable config

        # Parse options
        array set opts {
            fg_color    ""
            bg_color    ""
            title       ""
            background  1
            timeout     0
        }
        array set opts $options

        if {$opts(timeout) == 0} {
            set opts(timeout) $config(timeout_seconds)
        }

        # Find best available terminal
        set terminal [get_best_terminal]
        if {$terminal eq ""} {
            handle_warning "No terminal emulator found, using alternative viewer"
            return [launch_alternative_viewer $log_file $error_line]
        }

        # Build terminal command
        set cmd [build_xterm_command $terminal $log_file $error_line \
                    $opts(fg_color) $opts(bg_color) $opts(title)]

        handle_info "Launching error viewer: $terminal at line $error_line"
        handle_info "Log file: $log_file"

        # Execute command
        if {$opts(background)} {
            if {[catch {exec {*}$cmd &} error]} {
                handle_warning "Failed to launch $terminal: $error"
                return [launch_alternative_viewer $log_file $error_line]
            }
        } else {
            if {[catch {exec {*}$cmd} error]} {
                handle_warning "Failed to launch $terminal: $error"
                return [launch_alternative_viewer $log_file $error_line]
            }
        }

        return 1
    }

    proc launch_alternative_viewer {log_file error_line} {
        handle_info "Using alternative viewer for line $error_line"

        set cmd [build_alternative_viewer_command $log_file $error_line]

        if {[catch {exec {*}$cmd} error]} {
            handle_error "Failed to launch alternative viewer: $error"
            return 0
        }

        return 1
    }

    proc launch_critical_error_display {log_file critical_patterns {flow_type ""} {stage_name ""}} {
        global validation

        # Find the first critical error line
        set error_line [find_critical_error_line $log_file $critical_patterns]

        if {$error_line == 0} {
            handle_info "No critical errors found in log file"
            return 0
        }

        # Build enhanced title with flow and stage information
        set title "CBFlow Critical Error"
        if {$flow_type ne ""} {
            append title " - $flow_type"
        }
        if {$stage_name ne ""} {
            append title " ($stage_name)"
        }

        # Get error context for logging
        set context [get_error_context $log_file $error_line]
        handle_info "Critical error context:\n$context"

        # Launch viewer with red color scheme
        set options [list \
            fg_color "red" \
            bg_color "black" \
            title $title \
            background 1 \
        ]

        if {[info exists validation(validation_timeout)]} {
            lappend options timeout $validation(validation_timeout)
        }

        return [launch_error_viewer $log_file $error_line $options]
    }

    #===========================================================================
    # BATCH ERROR DISPLAY PROCEDURES
    #===========================================================================

    proc queue_error_display {log_file error_line title} {
        variable error_queue
        lappend error_queue [list $log_file $error_line $title]
    }

    proc process_error_queue {} {
        variable error_queue

        if {[llength $error_queue] == 0} {
            return 0
        }

        handle_info "Processing [llength $error_queue] queued error displays"

        set displayed 0
        foreach error_entry $error_queue {
            lassign $error_entry log_file error_line title

            set options [list title $title background 1]
            if {[launch_error_viewer $log_file $error_line $options]} {
                incr displayed
            }

            # Small delay between launches to prevent overwhelming the desktop
            after 1000
        }

        # Clear the queue
        set error_queue {}
        return $displayed
    }

    proc display_multiple_errors {error_list} {
        handle_info "Displaying [llength $error_list] critical errors"

        set displayed 0
        foreach error_entry $error_list {
            if {[llength $error_entry] >= 3} {
                lassign $error_entry log_file error_line title
                set options [list title $title background 1]
                if {[launch_error_viewer $log_file $error_line $options]} {
                    incr displayed
                }
                after 1000  # Delay between launches
            }
        }

        return $displayed
    }

    #===========================================================================
    # CONFIGURATION PROCEDURES
    #===========================================================================

    proc configure_xterm {args} {
        variable config

        foreach {key value} $args {
            switch -- $key {
                -fg_color {
                    set config(default_fg_color) $value
                }
                -bg_color {
                    set config(default_bg_color) $value
                }
                -title {
                    set config(default_title) $value
                }
                -geometry {
                    set config(default_geometry) $value
                }
                -context_lines {
                    set config(context_lines) $value
                }
                -timeout {
                    set config(timeout_seconds) $value
                }
                -debug {
                    set config(debug_mode) $value
                }
                default {
                    handle_warning "Unknown xterm configuration option: $key"
                }
            }
        }
    }

    proc get_xterm_config {} {
        variable config
        return [array get config]
    }

    #===========================================================================
    # UTILITY PROCEDURES
    #===========================================================================

    proc test_xterm_display {} {
        set test_file "/tmp/cbflow_xterm_test.log"

        # Create test log file
        set fp [open $test_file w]
        puts $fp "Line 1: This is a test log file"
        puts $fp "Line 2: Normal operation message"
        puts $fp "Line 3: Another normal message"
        puts $fp "Line 4: ERROR: This is a test critical error"
        puts $fp "Line 5: More context after the error"
        puts $fp "Line 6: End of test log"
        close $fp

        handle_info "Testing XTerm display with test file: $test_file"

        set result [launch_error_viewer $test_file 4 [list title "CBFlow XTerm Test"]]

        # Cleanup
        file delete $test_file

        return $result
    }

    proc get_terminal_info {} {
        set available [detect_available_terminals]
        set best [get_best_terminal]

        set info "Available terminals: [join $available {, }]\n"
        append info "Best terminal: $best\n"
        append info "XTerm version: $::CBFlowXTerm::XTERM_VERSION"

        return $info
    }

    #===========================================================================
    # INTEGRATION PROCEDURES
    #===========================================================================

    proc integrate_with_validation {validation_config} {
        global validation

        # Load validation configuration if provided
        if {[file exists $validation_config]} {
            source $validation_config
        }

        # Configure XTerm based on validation settings
        if {[info exists validation(xterm_fg_color)]} {
            configure_xterm -fg_color $validation(xterm_fg_color)
        }

        if {[info exists validation(xterm_bg_color)]} {
            configure_xterm -bg_color $validation(xterm_bg_color)
        }

        if {[info exists validation(xterm_title)]} {
            configure_xterm -title $validation(xterm_title)
        }

        if {[info exists validation(error_context_lines)]} {
            configure_xterm -context_lines $validation(error_context_lines)
        }

        handle_info "XTerm utilities integrated with validation configuration"
        return 1
    }
}

#===============================================================================
# PUBLIC INTERFACE PROCEDURES
#===============================================================================

proc cbflow_launch_error_viewer {log_file error_line {options {}}} {
    return [::CBFlowXTerm::launch_error_viewer $log_file $error_line $options]
}

proc cbflow_display_critical_errors {log_file critical_patterns {flow_type ""} {stage_name ""}} {
    return [::CBFlowXTerm::launch_critical_error_display $log_file $critical_patterns $flow_type $stage_name]
}

proc cbflow_test_xterm {} {
    return [::CBFlowXTerm::test_xterm_display]
}

proc cbflow_configure_xterm {args} {
    return [::CBFlowXTerm::configure_xterm {*}$args]
}

proc cbflow_get_terminal_info {} {
    return [::CBFlowXTerm::get_terminal_info]
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Check if error utilities are available
if {![info exists ::cbflow_error_utils_loaded]} {
    # Provide basic fallback procedures if error_utils not loaded
    proc handle_info {msg} { puts "INFO: $msg" }
    proc handle_warning {msg} { puts "WARNING: $msg" }
    proc handle_error {msg} { puts "ERROR: $msg" }
}

# Set up terminal detection cache
::CBFlowXTerm::detect_available_terminals

# Legacy completion message
puts "INFO: CBFlow XTerm display utilities loaded successfully"