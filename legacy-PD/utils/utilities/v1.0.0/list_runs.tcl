#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow List Runs Script
# Description: Lists all valid CBFlow runs by checking for environment files
# Version: v1.0.0
# Usage: tclsh list_runs.tcl [directory]
# ═══════════════════════════════════════════════════════════════════════════════

# TCL-First Environment Loading - Clean and Simple Approach
proc load_tcl_environment {{search_dir "."}} {
    puts "Loading CBFlow environment from native TCL files..."

    # Look for TCL environment files in priority order
    set env_files [list "$search_dir/.cbflow.tcl" "$search_dir/../.cbflow.tcl"]

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            puts "Found CBFlow TCL environment file: $env_file"
            if {[catch {source $env_file} error]} {
                puts stderr "ERROR: Failed to source TCL environment file: $error"
                exit 1
            }
            puts "✓ Environment variables loaded from native TCL file"
            return true
        }
    }

    puts stderr "WARNING: No CBFlow TCL environment file found - using basic functionality"
    return false
}

# Load TCL environment if available
load_tcl_environment

# Source utils.tcl for logging functions
if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
    source $::env(UTILS_TCL)
} elseif {[file exists "../utils.tcl"]} {
    source "../utils.tcl"
} elseif {[file exists "../../utils.tcl"]} {
    source "../../utils.tcl"
}

# Define basic logging functions if not available
if {[info procs handle_info] eq ""} {
    proc handle_info {message} { puts "INFO: $message" }
}
if {[info procs handle_warning] eq ""} {
    proc handle_warning {message} { puts "WARNING: $message" }
}
if {[info procs handle_error] eq ""} {
    proc handle_error {message} { puts stderr "ERROR: $message" }
}

global argc argv argv0

# ┌─ Run Status Configuration ────────────────────────────────────────────────────┐
# Run status icons
array set STATUS_ICONS {
    "Ready"       "⏳"
    "Running"     "🔄"
    "Complete"    "✅"
    "Error"       "❌"
    "In Progress" "🔨"
    "Unknown"     "❓"
}

# ┌─ Run Detection Functions ─────────────────────────────────────────────────┐

proc get_status_icon {status} {
    global STATUS_ICONS
    if {[info exists STATUS_ICONS($status)]} {
        return $STATUS_ICONS($status)
    } else {
        return $STATUS_ICONS(Unknown)
    }
}

proc parse_run_directory_name {run_dir} {
    set phase "UNKNOWN"
    set flow_type "UNKNOWN"
    set run_name "UNKNOWN"

    # Pattern 1: P0_run_SYNTH_simple_test_001
    if {[regexp {([^_]+)_run_([^_]+)_(.+)$} $run_dir -> extracted_phase extracted_flow extracted_name]} {
        set phase $extracted_phase
        set flow_type $extracted_flow
        set run_name $extracted_name
    # Pattern 2: run_SYNTH_simple_test_001
    } elseif {[regexp {^run_([^_]+)_(.+)$} $run_dir -> extracted_flow extracted_name]} {
        set phase "N/A"
        set flow_type $extracted_flow
        set run_name $extracted_name
    # Pattern 3: SYNTH_simple_test_001
    } elseif {[regexp {^([^_]+)_(.+)$} $run_dir -> extracted_flow extracted_name]} {
        set phase "N/A"
        set flow_type $extracted_flow
        set run_name $extracted_name
    } else {
        set run_name $run_dir
    }

    return [list $phase $flow_type $run_name]
}

proc get_run_status {run_dir} {
    set status "Ready"

    # Check .run.status file first
    if {[file exists "$run_dir/.run.status"]} {
        if {[catch {
            set fp [open "$run_dir/.run.status" r]
            set content [read $fp]
            close $fp

            if {[string match "*ERROR*" $content]} {
                set status "Error"
            } elseif {[string match "*COMPLETE*" $content]} {
                set status "Complete"
            } elseif {[string match "*RUNNING*" $content]} {
                set status "Running"
            } else {
                set status "In Progress"
            }
        }]} {
            # Fall back to checking log files
            if {[file exists "$run_dir/logs"]} {
                set log_files [glob -nocomplain "$run_dir/logs/*.log"]
                if {[llength $log_files] > 0} {
                    set latest_log [lindex [lsort -decreasing $log_files] 0]
                    if {[catch {
                        set fp [open $latest_log r]
                        set content [read $fp]
                        close $fp

                        if {[string match "*COMPLETE*" $content]} {
                            set status "Complete"
                        } elseif {[string match "*ERROR*" $content]} {
                            set status "Error"
                        } else {
                            set status "In Progress"
                        }
                    }]} {
                        set status "Unknown"
                    }
                }
            }
        }
    }

    return $status
}

proc get_run_details {run_dir} {
    # Check for environment file - prioritize native TCL files
    set env_files [list "$run_dir/.run.cbflow.tcl" "$run_dir/.cbflow.tcl" "$run_dir/.run.cbflow.env" "$run_dir/.cbflow.env" "$run_dir/.env.tcl"]
    set has_env_file false

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            set has_env_file true
            break
        }
    }

    if {!$has_env_file} {
        return {}
    }

    # Parse directory name
    lassign [parse_run_directory_name $run_dir] phase flow_type run_name

    # Get creation time
    set created [clock format [file mtime $run_dir] -format "%Y-%m-%d %H:%M"]

    # Count log files
    set log_count 0
    if {[file exists "$run_dir/logs"]} {
        set log_files [glob -nocomplain "$run_dir/logs/*.log"]
        set log_count [llength $log_files]
    }

    # Get status
    set status [get_run_status $run_dir]

    return [list $phase $flow_type $run_name $created $log_count $status]
}

# ┌─ Display Functions ───────────────────────────────────────────────────────┐

proc print_header {title} {
    puts ""
    puts "═══════════════════════════════════════════════════════════════"
    puts "  $title"
    puts "═══════════════════════════════════════════════════════════════"
    puts ""
}

proc print_section {title} {
    puts "───────────────────────────────────────────────────────────────"
    puts "$title"
    puts "───────────────────────────────────────────────────────────────"
}

proc list_runs {search_dir} {
    handle_info "Scanning for CBFlow runs in: $search_dir"

    set valid_runs {}
    set all_dirs [glob -nocomplain "$search_dir/*"]

    foreach dir $all_dirs {
        if {[file isdirectory $dir]} {
            set run_info [get_run_details $dir]
            if {[llength $run_info] > 0} {
                lappend valid_runs [list [file tail $dir] {*}$run_info]
            }
        }
    }

    if {[llength $valid_runs] == 0} {
        handle_warning "No CBFlow runs found in $search_dir"
        handle_info "  (Looking for directories containing .run.cbflow.tcl, .cbflow.tcl, .run.cbflow.env, .cbflow.env, or .env.tcl files)"
        return true
    }

    # Group runs by flow type
    array set flow_runs {}
    foreach run $valid_runs {
        lassign $run dir_name phase flow_type run_name created log_count status

        if {![info exists flow_runs($flow_type)]} {
            set flow_runs($flow_type) {}
        }
        lappend flow_runs($flow_type) [list $dir_name $phase $run_name $created $log_count $status]
    }

    # Display runs
    print_header "CBFlow Runs"

    # Sort flow types with priority order
    set flow_order {}
    foreach priority_flow {"SYNTH" "PNR" "SIGNOFF"} {
        if {[info exists flow_runs($priority_flow)]} {
            lappend flow_order $priority_flow
        }
    }
    foreach flow_type [lsort [array names flow_runs]] {
        if {$flow_type ni {"SYNTH" "PNR" "SIGNOFF"}} {
            lappend flow_order $flow_type
        }
    }

    foreach flow_type $flow_order {
        print_section " $flow_type Runs"

        # Sort runs by creation time (newest first)
        set sorted_runs [lsort -index 3 -decreasing $flow_runs($flow_type)]

        foreach run $sorted_runs {
            lassign $run dir_name phase run_name created log_count status

            set status_icon [get_status_icon $status]
            puts "  📁 $dir_name"
            puts "    Phase: $phase | Run: $run_name | Created: $created"
            puts "    Logs: $log_count files | Status: $status_icon $status"
            puts ""
        }
    }

    set total_runs [llength $valid_runs]
    handle_info "Total: $total_runs CBFlow runs found"

    return true
}

# ┌─ Command Line Interface ─────────────────────────────────────────────────┐

proc show_help {} {
    puts "CBFlow Run Lister v1.0.0"
    puts "Usage: tclsh [info script] \\[directory\\]"
    puts ""
    puts "Arguments:"
    puts "  directory: Directory to search for runs (default: current directory)"
    puts ""
    puts "Description:"
    puts "  Lists all valid CBFlow runs by checking for environment files"
    puts "  Supports .run.cbflow.tcl, .cbflow.tcl, .run.cbflow.env, .cbflow.env, and .env.tcl files"
    puts ""
    puts "Status Icons:"
    global STATUS_ICONS
    foreach {status icon} [array get STATUS_ICONS] {
        puts "  $icon $status"
    }
    puts ""
}

proc main {argc argv} {
    if {$argc > 0 && ([lindex $argv 0] in {"help" "--help" "-h"})} {
        show_help
        return 0
    }

    # Parse arguments
    set search_dir "."
    if {$argc >= 1} {
        set search_dir [lindex $argv 0]
    }

    # Validate search directory
    if {![file exists $search_dir]} {
        handle_error "Directory does not exist: $search_dir"
        return 1
    }

    if {![file isdirectory $search_dir]} {
        handle_error "Path is not a directory: $search_dir"
        return 1
    }

    # List the runs
    if {[list_runs $search_dir]} {
        return 0
    } else {
        return 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

# Only run main if this script is executed directly (not sourced)
if {[info script] eq $argv0} {
    exit [main $argc $argv]
}