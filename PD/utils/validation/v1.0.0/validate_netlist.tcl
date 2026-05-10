#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Netlist Validation Script (Refactored)
# Description: Validate netlist files for design flows
# Version: v1.0.0
# Namespace: ::CBFlow::Validation::NetlistValidator
# Usage: tclsh validate_netlist_refactored.tcl <run_dir>
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Script Initialization ──────────────────────────────────────────────────────┐
# Load common configuration loader first
set script_dir [file dirname [file normalize [info script]]]
source "$::env(FLOW_DIR)/utils/common/config_loader.tcl"

# Initialize CBFlow environment
if {![cbflow_init -debug false]} {
    puts stderr "Failed to initialize CBFlow environment"
    exit 1
}

# ┌─ Global Scope Setup ─────────────────────────────────────────────────────────┐
# Ensure all required global variables are available AFTER initialization
global flow STAGE_TYPES DEPENDENCY_STAGES NODE_TYPE_DESCRIPTIONS
global argc argv argv0

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Validation::NetlistValidator {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Validation patterns for netlist files
    variable NETLIST_EXTENSIONS {".v" ".vg" ".sv"}
    variable REQUIRED_NETLIST_PATTERNS {
        "results/netlist/*.v"
        "results/netlist/*.vg"
    }

    # ┌─ Import Global Arrays ────────────────────────────────────────────────────┐
    # Ensure all global configuration arrays are available in this namespace
    proc initialize_global_access {} {
        global flow STAGE_TYPES DEPENDENCY_STAGES NODE_TYPE_DESCRIPTIONS

        # Use try-catch to verify that arrays are loaded
        if {[catch {array size NODE_TYPE_DESCRIPTIONS} node_count]} {
            handle_error "NODE_TYPE_DESCRIPTIONS array not accessible: $node_count"
            return false
        }
        if {[catch {array size STAGE_TYPES} stage_count]} {
            handle_error "STAGE_TYPES array not accessible: $stage_count"
            return false
        }
        if {[catch {array size DEPENDENCY_STAGES} dep_count]} {
            handle_error "DEPENDENCY_STAGES array not accessible: $dep_count"
            return false
        }

        handle_debug "Global arrays successfully imported: $node_count node types, $stage_count stage types, $dep_count dependencies"
        return true
    }

    # ┌─ Common Functions ────────────────────────────────────────────────────────┐
    # Use full namespace paths for clarity
    proc handle_error {message} {
        return [::CBFlow::Common::ConfigLoader::handle_error $message]
    }

    proc handle_warning {message} {
        return [::CBFlow::Common::ConfigLoader::handle_warning $message]
    }

    proc handle_info {message} {
        return [::CBFlow::Common::ConfigLoader::handle_info $message]
    }

    proc handle_debug {message} {
        return [::CBFlow::Common::ConfigLoader::handle_debug $message]
    }

    # ┌─ Validation Functions ────────────────────────────────────────────────────┐

    proc validate_run_directory {run_dir} {
        if {![file exists $run_dir]} {
            handle_error "Run directory does not exist: $run_dir"
            return false
        }

        if {![file isdirectory $run_dir]} {
            handle_error "Path is not a directory: $run_dir"
            return false
        }

        return true
    }

    proc find_netlist_files {run_dir} {
        variable REQUIRED_NETLIST_PATTERNS

        set found_files {}

        foreach pattern $REQUIRED_NETLIST_PATTERNS {
            set full_pattern [file join $run_dir $pattern]
            set matches [glob -nocomplain $full_pattern]

            foreach match $matches {
                if {[file isfile $match]} {
                    lappend found_files $match
                }
            }
        }

        return $found_files
    }

    proc validate_netlist_syntax {netlist_file} {
        handle_info "Validating netlist syntax: [file tail $netlist_file]"

        if {[catch {open $netlist_file r} fd]} {
            handle_error "Cannot open netlist file: $netlist_file"
            return false
        }

        set module_count 0
        set has_timescale false
        set line_number 0
        set syntax_valid true

        while {[gets $fd line] >= 0} {
            incr line_number
            set line [string trim $line]

            # Skip empty lines and comments
            if {$line eq "" || [string match "//*" $line]} continue

            # Check for timescale directive
            if {[string match "`timescale*" $line]} {
                set has_timescale true
                handle_debug "Found timescale: $line"
            }

            # Check for module declarations
            if {[regexp {^module\s+(\w+)} $line -> module_name]} {
                incr module_count
                handle_debug "Found module: $module_name"
            }

            # Check for basic syntax errors (very simple check)
            if {[regexp {[{}]} $line] && ![regexp {always|initial|generate} $line]} {
                handle_warning "Line $line_number: Suspicious syntax - $line"
            }
        }

        close $fd

        # Validate basic structure
        if {$module_count == 0} {
            handle_error "No modules found in netlist file"
            set syntax_valid false
        } else {
            handle_info "Found $module_count modules in netlist"
        }

        if {!$has_timescale} {
            handle_warning "No timescale directive found (may be optional)"
        }

        if {$syntax_valid} {
            handle_info "✓ Basic netlist syntax validation passed"
        } else {
            handle_error "✗ Basic netlist syntax validation failed"
        }

        return $syntax_valid
    }

    proc perform_netlist_validation {run_dir} {
        handle_info "Starting netlist validation for: $run_dir"

        # Validate run directory
        if {![validate_run_directory $run_dir]} {
            return false
        }

        # Find netlist files
        set netlist_files [find_netlist_files $run_dir]

        if {[llength $netlist_files] == 0} {
            handle_error "No netlist files found in expected locations"
            handle_info "Expected patterns:"
            variable REQUIRED_NETLIST_PATTERNS
            foreach pattern $REQUIRED_NETLIST_PATTERNS {
                handle_info "  - $pattern"
            }
            return false
        }

        handle_info "Found [llength $netlist_files] netlist files:"
        foreach file $netlist_files {
            set rel_path [file join "..." [file tail [file dirname $file]] [file tail $file]]
            set size [file size $file]
            handle_info "  - $rel_path ($size bytes)"
        }

        # Validate each netlist file
        set validation_passed true
        foreach netlist_file $netlist_files {
            if {![validate_netlist_syntax $netlist_file]} {
                set validation_passed false
            }
        }

        if {$validation_passed} {
            handle_info "✓ Netlist validation completed successfully"
            return true
        } else {
            handle_error "✗ Netlist validation failed"
            return false
        }
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Netlist Validation (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] <run_dir>"
        puts ""
        puts "Arguments:"
        puts "  run_dir: Run directory containing netlist files"
        puts ""
        puts "Description:"
        puts "  Validates netlist files for syntax and basic structure"
        puts ""
        puts "Supported extensions:"
        variable NETLIST_EXTENSIONS
        foreach ext $NETLIST_EXTENSIONS {
            puts "  - $ext"
        }
        puts ""
        puts "Search patterns:"
        variable REQUIRED_NETLIST_PATTERNS
        foreach pattern $REQUIRED_NETLIST_PATTERNS {
            puts "  - $pattern"
        }
        puts ""
    }

    proc main {argc argv} {
        # Ensure global arrays are accessible
        if {![initialize_global_access]} {
            return 1
        }

        if {$argc == 0 || ([lindex $argv 0] in {"help" "--help" "-h"})} {
            show_help
            return 0
        }

        if {$argc < 1} {
            handle_error "Invalid number of arguments"
            show_help
            return 1
        }

        set run_dir [lindex $argv 0]

        # Perform the validation
        if {[perform_netlist_validation $run_dir]} {
            return 0
        } else {
            return 1
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

# Only run main if this script is executed directly (not sourced)
if {[info script] eq $argv0} {
    exit [::CBFlow::Validation::NetlistValidator::main $argc $argv]
}