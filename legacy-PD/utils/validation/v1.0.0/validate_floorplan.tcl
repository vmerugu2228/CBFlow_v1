#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Floorplan Validation Script (Refactored)
# Description: Validate floorplan DEF files for PNR flow
# Version: v1.0.0
# Namespace: ::CBFlow::Validation::FloorplanValidator
# Usage: tclsh validate_floorplan_refactored.tcl <run_dir>
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
namespace eval ::CBFlow::Validation::FloorplanValidator {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Validation patterns for floorplan files
    variable REQUIRED_FLOORPLAN_FILES {
        "results/def/floorplan.def"
        "results/netlist/floorplan.v"
    }

    variable OPTIONAL_FLOORPLAN_FILES {
        "results/spef/floorplan.spef"
        "results/sdc/floorplan.sdc"
        "reports/floorplan/area.rpt"
        "reports/floorplan/utilization.rpt"
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

        # Check for basic run directory structure
        set required_dirs {"results" "reports" "setup"}
        foreach dir $required_dirs {
            set dir_path [file join $run_dir $dir]
            if {![file exists $dir_path]} {
                handle_warning "Missing directory: $dir"
            }
        }

        return true
    }

    proc check_file_exists {run_dir filepath description} {
        set full_path [file join $run_dir $filepath]

        if {[file exists $full_path]} {
            if {[file size $full_path] > 0} {
                handle_info "✓ $description: $filepath ([file size $full_path] bytes)"
                return true
            } else {
                handle_warning "⚠ $description exists but is empty: $filepath"
                return false
            }
        } else {
            handle_warning "✗ $description not found: $filepath"
            return false
        }
    }

    proc validate_def_file {run_dir def_file} {
        set full_path [file join $run_dir $def_file]

        if {![file exists $full_path]} {
            return false
        }

        handle_info "Validating DEF file structure: $def_file"

        # Read and validate basic DEF structure
        if {[catch {open $full_path r} fd]} {
            handle_error "Cannot open DEF file: $full_path"
            return false
        }

        set has_design false
        set has_units false
        set has_diearea false
        set has_end false

        while {[gets $fd line] >= 0} {
            set line [string trim $line]

            if {[string match "DESIGN *" $line]} {
                set has_design true
                handle_debug "Found DESIGN statement: $line"
            } elseif {[string match "UNITS DISTANCE MICRONS *" $line]} {
                set has_units true
                handle_debug "Found UNITS statement: $line"
            } elseif {[string match "DIEAREA*" $line]} {
                set has_diearea true
                handle_debug "Found DIEAREA statement: $line"
            } elseif {[string match "END DESIGN" $line]} {
                set has_end true
                handle_debug "Found END DESIGN statement"
                break
            }
        }

        close $fd

        # Validate required sections
        set valid true
        if {!$has_design} {
            handle_error "DEF file missing DESIGN statement"
            set valid false
        }
        if {!$has_units} {
            handle_error "DEF file missing UNITS statement"
            set valid false
        }
        if {!$has_diearea} {
            handle_error "DEF file missing DIEAREA statement"
            set valid false
        }
        if {!$has_end} {
            handle_error "DEF file missing END DESIGN statement"
            set valid false
        }

        if {$valid} {
            handle_info "✓ DEF file structure validation passed"
        } else {
            handle_error "DEF file structure validation failed"
        }

        return $valid
    }

    proc perform_floorplan_validation {run_dir} {
        variable REQUIRED_FLOORPLAN_FILES
        variable OPTIONAL_FLOORPLAN_FILES

        handle_info "Starting floorplan validation for: $run_dir"

        # Validate run directory
        if {![validate_run_directory $run_dir]} {
            return false
        }

        set validation_passed true

        # Check required files
        handle_info "Checking required floorplan files..."
        foreach file $REQUIRED_FLOORPLAN_FILES {
            if {![check_file_exists $run_dir $file "Required file"]} {
                set validation_passed false
            }
        }

        # Check optional files (just report, don't fail)
        handle_info "Checking optional floorplan files..."
        foreach file $OPTIONAL_FLOORPLAN_FILES {
            check_file_exists $run_dir $file "Optional file"
        }

        # Special validation for DEF files
        foreach file $REQUIRED_FLOORPLAN_FILES {
            if {[file extension $file] eq ".def"} {
                if {![validate_def_file $run_dir $file]} {
                    set validation_passed false
                }
            }
        }

        if {$validation_passed} {
            handle_info "✓ Floorplan validation completed successfully"
            return true
        } else {
            handle_error "✗ Floorplan validation failed"
            return false
        }
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Floorplan Validation (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] <run_dir>"
        puts ""
        puts "Arguments:"
        puts "  run_dir: Run directory containing floorplan results"
        puts ""
        puts "Description:"
        puts "  Validates floorplan DEF files and related deliverables for PNR flow"
        puts ""
        puts "Validated files:"
        variable REQUIRED_FLOORPLAN_FILES
        foreach file $REQUIRED_FLOORPLAN_FILES {
            puts "  - $file (required)"
        }
        variable OPTIONAL_FLOORPLAN_FILES
        foreach file $OPTIONAL_FLOORPLAN_FILES {
            puts "  - $file (optional)"
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
        if {[perform_floorplan_validation $run_dir]} {
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
    exit [::CBFlow::Validation::FloorplanValidator::main $argc $argv]
}