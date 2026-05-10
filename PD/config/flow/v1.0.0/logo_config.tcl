#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Logo Configuration
#
# Description: Logo and branding configuration with clean namespace architecture
# Version: 1.0.0
# Author: CBFlow Management System
#
# Features:
# - Clean namespace architecture
# - Environment variable integration
# - Standardized error handling
# - Configuration validation
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
    # Use environment variable for error_utils.tcl path
    set error_utils_path "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
    if {[file exists $error_utils_path]} {
        source $error_utils_path
        # Set FLOW_ROOT if not already set
        if {![info exists ::env(FLOW_ROOT)]} {
            set ::env(FLOW_ROOT) [file dirname [file dirname [file dirname $script_dir]]]
        }
        if {![info exists ::env(UTILITIES_VERSION)]} {
            set ::env(UTILITIES_VERSION) [expr {[info exists ::env(CBFLOW_RELEASE_VERSION)] ? $::env(CBFLOW_RELEASE_VERSION) : "v1.0.0"}]
        }
    } else {
        puts "ERROR: Cannot find error_utils.tcl. Please ensure FLOW_ROOT and UTILITIES_VERSION are set."
        exit 1
    }
}

# Clean namespace for logo configuration
namespace eval ::CBFlow::Configuration::Logo {

    #===========================================================================
    # LOGO CONFIGURATION DATA
    #===========================================================================

    # ┌─ Logo Configuration Array ─────────────────────────────────────────────┐
    variable logo_data
    array set logo_data {
        name "CBFlow"
        description "Physical Design Automation Framework"
        tagline "Chip Design Excellence Through Innovation"
        motto "Building Tomorrow's Processors Today"
        copyright "© 2024 CBFlow Development Team. All rights reserved."
        contact "support@cbflow.dev"
        website "https://www.cbflow.dev"
        features {
            "• Multi-flow support with dynamic flow detection"
            "• Advanced version management system"
            "• Enterprise workspace development"
            "• Comprehensive validation framework"
            "• Professional error handling"
        }
        ascii_art "CBFlow - Physical Design Automation Framework"
        message "Welcome to the Advanced Physical Design Flow\nBuilding the future of chip design, one transistor at a time\nOptimized for performance, power, and area\n\nProject: CBflow Physical Design Automation\nStatus: Ready for synthesis and implementation"
        author "Physical Design Flow Development Team"
        display,use_unicode_borders true
        display,logo_width 77
        display,center_text true
    }

    #===========================================================================
    # ENVIRONMENT VALIDATION PROCEDURES
    #===========================================================================

    proc validate_environment {} {
        CBFLOW_SECTION "Logo Configuration - Environment Validation"

        # Optional environment variables - not required for basic functionality
        set optional_vars {
            RELEASE_FLOW_VERSION
            CBFLOW_DESIGN_NAME
            CBFLOW_PROJECT_PHASE
        }

        foreach var $optional_vars {
            if {[info exists ::env($var)]} {
                CBFLOW_DEBUG "Optional environment variable '$var' = $::env($var)" "ENV_VALIDATION"
            } else {
                CBFLOW_DEBUG "Optional environment variable '$var' not set (using defaults)" "ENV_VALIDATION"
            }
        }

        CBFLOW_SUCCESS "Logo environment validation completed" "ENV_VALIDATION"
        return 1
    }

    #===========================================================================
    # CONFIGURATION LOADING PROCEDURES
    #===========================================================================

    proc load_logo_configuration {} {
        variable logo_data
        global logo

        CBFLOW_HEADER "CBFlow Logo Configuration"

        # Step 1: Validate environment
        if {![validate_environment]} {
            CBFLOW_ERROR "Logo environment validation failed" "CONFIG"
            return 0
        }

        # Step 2: Copy logo data to global logo array
        CBFLOW_SECTION "Loading Logo Configuration Data"
        array set logo [array get logo_data]

        # Step 3: Add dynamic version information from environment
        if {[info exists ::env(RELEASE_FLOW_VERSION)]} {
            set logo(version) $::env(RELEASE_FLOW_VERSION)
            CBFLOW_DEBUG "Added version from environment: $logo(version)" "CONFIG"
        } else {
            set logo(version) "v1.0.0"
            CBFLOW_DEBUG "Using default version: $logo(version)" "CONFIG"
        }

        # Set dynamic build date
        set logo(build_date) [clock format [clock seconds] -format "%Y-%m-%d"]
        CBFLOW_DEBUG "Added build date: $logo(build_date)" "CONFIG"

        # Step 4: Add dynamic project information
        if {[info exists ::env(CBFLOW_DESIGN_NAME)]} {
            set logo(current_design) $::env(CBFLOW_DESIGN_NAME)
            CBFLOW_DEBUG "Added current design: $logo(current_design)" "CONFIG"
        }

        if {[info exists ::env(CBFLOW_PROJECT_PHASE)]} {
            set logo(current_phase) $::env(CBFLOW_PROJECT_PHASE)
            CBFLOW_DEBUG "Added current phase: $logo(current_phase)" "CONFIG"
        }

        # Step 5: Validate configuration completeness
        if {![validate_logo_configuration]} {
            CBFLOW_ERROR "Logo configuration validation failed" "CONFIG"
            return 0
        }

        # Step 6: Display success message
        set version_info ""
        if {[info exists logo(version)]} {
            set version_info " v$logo(version)"
        }

        CBFLOW_SUCCESS "Logo configuration loaded successfully - $logo(name)$version_info" "CONFIG"
        return 1
    }

    proc validate_logo_configuration {} {
        global logo

        set required_fields {name description tagline}
        set validation_failed 0

        CBFLOW_SECTION "Logo Configuration Validation"

        foreach field $required_fields {
            if {![info exists logo($field)] || $logo($field) eq ""} {
                CBFLOW_ERROR "Required logo field '$field' is missing or empty" "VALIDATION"
                set validation_failed 1
            } else {
                CBFLOW_DEBUG "Logo field '$field' validated: $logo($field)" "VALIDATION"
            }
        }

        if {$validation_failed} {
            CBFLOW_ERROR "Logo configuration validation failed" "VALIDATION"
            return 0
        }

        CBFLOW_SUCCESS "Logo configuration validation passed" "VALIDATION"
        return 1
    }

    #===========================================================================
    # UTILITY PROCEDURES
    #===========================================================================

    proc get_logo_info {field} {
        global logo
        if {[info exists logo($field)]} {
            return $logo($field)
        } else {
            CBFLOW_WARNING "Logo field '$field' not found" "UTILITY"
            return ""
        }
    }

    proc display_logo_banner {} {
        global logo
        if {[info exists logo(ascii_art)]} {
            puts ""
            foreach line $logo(ascii_art) {
                puts "  $line"
            }
            puts ""
            if {[info exists logo(tagline)]} {
                puts "  $logo(tagline)"
                puts ""
            }
        }
    }

    proc get_version_string {} {
        global logo
        set version_str $logo(name)
        if {[info exists logo(version)]} {
            append version_str " v$logo(version)"
        }
        return $version_str
    }
}

#===============================================================================
# MAIN INTERFACE
#===============================================================================

# If run directly (not sourced), execute the main procedure
if {[info exists argv0] && $argv0 eq [info script]} {
    if {![::CBFlow::Configuration::Logo::load_logo_configuration]} {
        exit 1
    }
} else {
    # When sourced, automatically load configuration if not already loaded
    if {![info exists ::logo_config_loaded]} {
        if {[::CBFlow::Configuration::Logo::load_logo_configuration]} {
            set ::logo_config_loaded true
        }
    }
}