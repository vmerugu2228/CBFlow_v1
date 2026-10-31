#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Directory Utilities
#
# Description: Directory management and path construction utilities with version-based architecture
# Version: 1.0.0
# Author: CBFlow Management System
#
# Features:
# - Clean namespace architecture
# - Environment variable integration
# - Standardized error handling
# - Version-based configuration loading
#===============================================================================

# Load standardized error handling utilities using version-based paths
if {[info exists ::env(FLOW_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    # Use FLOW_ROOT and UTILITIES_VERSION to construct path
    set error_utils_path "$::env(FLOW_ROOT)/utils/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
    if {[file exists $error_utils_path]} {
        source $error_utils_path
    } else {
        puts "ERROR: Cannot find error_utils.tcl at $error_utils_path"
        exit 1
    }
} else {
    # Fallback: try to find error_utils.tcl relative to this script
    set script_dir [file dirname [file normalize [info script]]]
    set error_utils_path "$script_dir/error_utils.tcl"
    if {[file exists $error_utils_path]} {
        source $error_utils_path
        # Set default versions for fallback
        if {![info exists ::env(FLOW_ROOT)]} {
            set ::env(FLOW_ROOT) [file dirname [file dirname [file dirname $script_dir]]]
        }
        if {![info exists ::env(UTILITIES_VERSION)]} {
            set ::env(UTILITIES_VERSION) "v1.0.0"
        }
    } else {
        puts "ERROR: Cannot find error_utils.tcl. Please ensure FLOW_ROOT and UTILITIES_VERSION are set."
        exit 1
    }
}

# Clean namespace for CBFlow directory utilities
namespace eval ::CBFlow::Directory {

    #===========================================================================
    # VERSION AND CONSTANTS
    #===========================================================================

    variable DIRECTORY_VERSION "1.0.0"
    variable DIRECTORY_DATE "2025-09-24"

    #===========================================================================
    # ENVIRONMENT VALIDATION PROCEDURES
    #===========================================================================

    proc validate_environment {} {
        CBFLOW_HEADER "CBFlow Directory Utilities - Environment Validation"

        # Check for FLOW_ROOT or calculate it
        if {![info exists ::env(FLOW_ROOT)] || $::env(FLOW_ROOT) eq ""} {
            # Try to calculate from current script location
            set script_dir [file dirname [file normalize [info script]]]
            set utils_parent [file dirname [file dirname $script_dir]]
            set calculated_flow_root [file dirname $utils_parent]
            set ::env(FLOW_ROOT) $calculated_flow_root
            CBFLOW_DEBUG "Calculated FLOW_ROOT = $calculated_flow_root" "ENV_VALIDATION"
        } else {
            CBFLOW_DEBUG "FLOW_ROOT = $::env(FLOW_ROOT)" "ENV_VALIDATION"
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
                CBFLOW_DEBUG "Using default version for $var = v1.0.0" "ENV_VALIDATION"
            }
        }

        # Optional run-specific variables
        set optional_vars {
            CBFLOW_DESIGN_NAME
            CBFLOW_PROJECT_PHASE
            CBFLOW_FLOW_TYPE
        }

        foreach var $optional_vars {
            if {[info exists ::env($var)]} {
                CBFLOW_DEBUG "Runtime variable '$var' = $::env($var)" "ENV_VALIDATION"
            } else {
                CBFLOW_DEBUG "Runtime variable '$var' not set" "ENV_VALIDATION"
            }
        }

        CBFLOW_SUCCESS "Directory utilities environment validation completed" "ENV_VALIDATION"
        return 1
    }

    #===========================================================================
    # DIRECTORY CREATION PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: create_directories
    # PURPOSE: Creates the complete directory structure for a flow type
    # PARAMETERS:
    #   flow_type - Flow type (SYNTH, PNR, FP, etc.) - always UPPERCASE
    #   run_dir - Base run directory path
    # RETURNS: true if successful, false otherwise
    # DEPENDENCIES: directory() global array from dir_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc create_directories {flow_type run_dir} {
        global directory

        # Ensure flow_type is uppercase
        set flow_type [string toupper $flow_type]

        # Load directory configuration using version-based paths
        set flow_root $::env(FLOW_ROOT)
        set dir_config "$flow_root/config/flow/$::env(FLOW_CONFIG_VERSION)/dir_config.tcl"

        if {![file exists $dir_config]} {
            CBFLOW_ERROR "Directory configuration not found: $dir_config" "CONFIG"
            return false
        }

        # Source the directory configuration
        if {[catch {source $dir_config} error]} {
            CBFLOW_ERROR "Failed to load directory configuration: $error" "CONFIG"
            return false
        }

        # Create flow-specific directories
        if {[info exists directory($flow_type)]} {
            foreach dir $directory($flow_type) {
                set full_path [file join $run_dir $dir]
                if {![file exists $full_path]} {
                    if {[catch {file mkdir $full_path} error]} {
                        CBFLOW_ERROR "Error creating directory $full_path: $error" "DIR_CREATE"
                        return false
                    } else {
                        CBFLOW_DEBUG "Created directory: $full_path" "DIR_CREATE"
                    }
                } else {
                    CBFLOW_DEBUG "Directory already exists: $full_path" "DIR_CREATE"
                }
            }
        } else {
            CBFLOW_ERROR "No directory structure defined for flow type: $flow_type" "CONFIG"
            return false
        }

        return true
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_work_path
    # PURPOSE: Returns the work directory path for a specific stage and flow type
    # PARAMETERS:
    #   stage_name - Stage name (e.g., synthesis, place, route)
    #   flow_type - Flow type (SYNTH, PNR, FP, etc.) - always UPPERCASE
    # RETURNS: Work directory path string
    # DEPENDENCIES: None (dynamic construction)
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_work_path {stage_name flow_type} {
        # Ensure flow_type is uppercase
        set flow_type [string toupper $flow_type]

        # Default to flow-type based work directory
        switch $flow_type {
            "SYNTH" { return "work/SYNTH" }
            "FP"    { return "work/FP" }
            "PNR"   { return "work/PNR" }
            "ECO"   { return "work/ECO" }
            "LEC"   { return "work/LEC" }
            "EMIR"  { return "work/EMIR" }
            "CLP"   { return "work/CLP" }
            "POPT"  { return "work/POPT" }
            "FCFP"  { return "work/FCFP" }
            default { return "work" }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_reports_path
    # PURPOSE: Returns the appropriate reports directory for a report type
    # PARAMETERS:
    #   report_type - Type of report (timing, power, synthesis, etc.)
    # RETURNS: Reports directory path string
    # DEPENDENCIES: None (dynamic construction)
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_reports_path {report_type} {
        # Map report types to directory paths
        switch -glob $report_type {
            "*synthesis*" { return "reports/synthesis" }
            "*timing*"    { return "reports/timing" }
            "*power*"     { return "reports/power" }
            "*place*"     { return "reports/place" }
            "*cts*"       { return "reports/cts" }
            "*route*"     { return "reports/route" }
            "*verification*" { return "reports/verification" }
            "*drc*"       { return "reports/drc" }
            "*lvs*"       { return "reports/lvs" }
            "*erc*"       { return "reports/erc" }
            "*floorplan*" { return "reports/floorplan" }
            "*area*"      { return "reports/area" }
            "*utilization*" { return "reports/utilization" }
            "*congestion*" { return "reports/congestion" }
            default       { return "reports" }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_results_path
    # PURPOSE: Returns the appropriate results directory for a result type
    # PARAMETERS:
    #   result_type - Type of result (netlist, def, gds, etc.)
    # RETURNS: Results directory path string
    # DEPENDENCIES: None (dynamic construction)
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_results_path {result_type} {
        # Map result types to directory paths
        switch -glob $result_type {
            "*netlist*"    { return "results/netlist" }
            "*def*"        { return "results/def" }
            "*gds*"        { return "results/gds" }
            "*database*"   { return "results/database" }
            "*db*"         { return "results/db" }
            "*timing*"     { return "results/timing" }
            "*verification*" { return "results/verification" }
            "*sdc*"        { return "results/sdc" }
            "*spef*"       { return "results/spef" }
            "*lib*"        { return "results/lib" }
            "*floorplan*"  { return "results/floorplan" }
            "*extraction*" { return "results/extraction" }
            "*eco*"        { return "results/eco" }
            "*lec*"        { return "results/lec" }
            "*emir*"       { return "results/emir" }
            "*power*"      { return "results/power" }
            default        { return "results" }
        }
    }

    #===========================================================================
    # DIRECTORY VALIDATION PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: validate_structure
    # PURPOSE: Validates that all required directories exist for a flow type
    # PARAMETERS:
    #   flow_type - Flow type (SYNTH, PNR, FP, etc.) - always UPPERCASE
    #   run_dir - Base run directory path
    # RETURNS: true if all directories exist, false otherwise
    # DEPENDENCIES: directory() global array from dir_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc validate_structure {flow_type run_dir} {
        global directory

        # Ensure flow_type is uppercase
        set flow_type [string toupper $flow_type]

        set missing_dirs {}

        # Load directory configuration using version-based paths
        set flow_root $::env(FLOW_ROOT)
        set dir_config "$flow_root/config/flow/$::env(FLOW_CONFIG_VERSION)/dir_config.tcl"

        if {![file exists $dir_config]} {
            CBFLOW_ERROR "Directory configuration not found: $dir_config" "CONFIG"
            return false
        }

        # Source the directory configuration
        if {[catch {source $dir_config} error]} {
            CBFLOW_ERROR "Failed to load directory configuration: $error" "CONFIG"
            return false
        }

        # Check flow-specific directories
        if {[info exists directory($flow_type)]} {
            foreach dir $directory($flow_type) {
                set full_path [file join $run_dir $dir]
                if {![file exists $full_path]} {
                    lappend missing_dirs $dir
                }
            }
        } else {
            CBFLOW_ERROR "No directory structure defined for flow type: $flow_type" "CONFIG"
            return false
        }

        if {[llength $missing_dirs] > 0} {
            CBFLOW_WARNING "Missing directories: [join $missing_dirs {, }]" "VALIDATION"
            return false
        }

        return true
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: cleanup_empty
    # PURPOSE: Removes empty directories from the run directory
    # PARAMETERS:
    #   run_dir - Base run directory path
    # RETURNS: Number of directories removed
    # DEPENDENCIES: None
    # ═══════════════════════════════════════════════════════════════════════════════
    proc cleanup_empty {run_dir} {
        set dirs_to_check [glob -nocomplain -type d [file join $run_dir "*"]]
        set removed_count 0

        foreach dir $dirs_to_check {
            if {[llength [glob -nocomplain [file join $dir "*"]]] == 0} {
                if {[catch {file delete $dir} error]} {
                    CBFLOW_WARNING "Could not remove empty directory $dir: $error" "CLEANUP"
                } else {
                    CBFLOW_DEBUG "Removed empty directory: $dir" "CLEANUP"
                    incr removed_count
                }
            }
        }

        return $removed_count
    }

    #===========================================================================
    # PATH CONSTRUCTION UTILITIES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: construct_path
    # PURPOSE: Constructs a complete file path based on category
    # PARAMETERS:
    #   base_dir - Base directory path
    #   category - Category type (work, reports, results)
    #   file_name - File name or identifier
    # RETURNS: Complete file path string
    # DEPENDENCIES: get_*_path procedures
    # ═══════════════════════════════════════════════════════════════════════════════
    proc construct_path {base_dir category file_name} {
        switch $category {
            "reports" {
                set category_dir [get_reports_path $file_name]
            }
            "results" {
                set category_dir [get_results_path $file_name]
            }
            "work" {
                # For work directories, we need flow_type, default to generic work
                set category_dir "work"
            }
            default {
                set category_dir $category
            }
        }

        return [file join $base_dir $category_dir $file_name]
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_stage_path
    # PURPOSE: Returns the directory for a specific flow stage
    # PARAMETERS:
    #   flow_type - Flow type (SYNTH, PNR, FP, etc.) - always UPPERCASE
    #   stage_name - Stage name
    # RETURNS: Stage directory path string
    # DEPENDENCIES: get_work_path procedure
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_stage_path {flow_type stage_name} {
        set work_dir [get_work_path $stage_name $flow_type]
        return [file join $work_dir $stage_name]
    }

    #===========================================================================
    # PUBLIC INTERFACE PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_supported_flow_types
    # PURPOSE: Returns list of all supported flow types
    # PARAMETERS: None
    # RETURNS: List of supported flow types (all UPPERCASE)
    # DEPENDENCIES: None
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_supported_flow_types {} {
        return {SYNTH FP PNR LEC EMIR ECO CLP POPT FCFP}
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: is_valid_flow_type
    # PURPOSE: Validates if a flow type is supported
    # PARAMETERS:
    #   flow_type - Flow type to validate
    # RETURNS: true if valid, false otherwise
    # DEPENDENCIES: get_supported_flow_types procedure
    # ═══════════════════════════════════════════════════════════════════════════════
    proc is_valid_flow_type {flow_type} {
        set flow_type [string toupper $flow_type]
        set supported_types [get_supported_flow_types]
        return [expr {$flow_type in $supported_types}]
    }

    #===========================================================================
    # MAIN INITIALIZATION PROCEDURE
    #===========================================================================

    proc initialize_directory_utilities {} {
        # Main initialization procedure
        CBFLOW_HEADER "CBFlow Directory Utilities v$::CBFlow::Directory::DIRECTORY_VERSION"

        # Step 1: Validate environment
        if {![validate_environment]} {
            CBFLOW_WARNING "Environment validation issues detected" "INIT"
        }

        # Step 2: Display initialization message
        CBFLOW_SUCCESS "CBFlow Directory Utilities v$::CBFlow::Directory::DIRECTORY_VERSION loaded" "INIT"

        return 1
    }
}

#===============================================================================
# GLOBAL BACKWARD COMPATIBILITY
#===============================================================================

# Export utility procedures to global namespace for backward compatibility
namespace eval :: {
    # Import directory utility procedures
    namespace import ::CBFlow::Directory::create_directories
    namespace import ::CBFlow::Directory::get_work_path
    namespace import ::CBFlow::Directory::get_reports_path
    namespace import ::CBFlow::Directory::get_results_path
    namespace import ::CBFlow::Directory::validate_structure
    namespace import ::CBFlow::Directory::cleanup_empty
    namespace import ::CBFlow::Directory::construct_path
    namespace import ::CBFlow::Directory::get_stage_path
    namespace import ::CBFlow::Directory::get_supported_flow_types
    namespace import ::CBFlow::Directory::is_valid_flow_type
}

#===============================================================================
# PUBLIC INTERFACE - GLOBAL PROCEDURES FOR BACKWARD COMPATIBILITY
#===============================================================================

# Create aliases for the old function names to maintain compatibility
proc create_flow_directories {flow_type run_dir} {
    return [::CBFlow::Directory::create_directories $flow_type $run_dir]
}

proc get_work_directory {stage_name flow_type} {
    return [::CBFlow::Directory::get_work_path $stage_name $flow_type]
}

proc get_reports_directory {report_type} {
    return [::CBFlow::Directory::get_reports_path $report_type]
}

proc get_results_directory {result_type} {
    return [::CBFlow::Directory::get_results_path $result_type]
}

proc validate_directory_structure {flow_type run_dir} {
    return [::CBFlow::Directory::validate_structure $flow_type $run_dir]
}

proc cleanup_empty_directories {run_dir} {
    return [::CBFlow::Directory::cleanup_empty $run_dir]
}

proc construct_file_path {base_dir category file_name} {
    return [::CBFlow::Directory::construct_path $base_dir $category $file_name]
}

proc get_stage_directory {flow_type stage_name} {
    return [::CBFlow::Directory::get_stage_path $flow_type $stage_name]
}

#===============================================================================
# AUTO-INITIALIZATION
#===============================================================================

# Initialize directory utilities when sourced
if {![info exists ::cbflow_directory_utils_loaded]} {
    if {[::CBFlow::Directory::initialize_directory_utilities]} {
        set ::cbflow_directory_utils_loaded true
    }
}

#===============================================================================
# END OF DIRECTORY UTILITIES
#===============================================================================