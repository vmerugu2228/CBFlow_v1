#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Logo Configuration
#
# Description: Logo and branding configuration. Populates the global `logo`
#              array consumed by logo_display.tcl and logo_utils.tcl.
# Version: 1.0.0
# Author: CBFlow Management System
#===============================================================================

# Load standardized error handling utilities. Try FLOW_ROOT first, fall back
# to FLOW_DIR; one of the two is always set by the CLI dispatcher.
set _root_env [expr {[info exists ::env(FLOW_ROOT)] ? $::env(FLOW_ROOT) \
                    : [expr {[info exists ::env(FLOW_DIR)] ? $::env(FLOW_DIR) : ""}]}]
set _utils_ver [expr {[info exists ::env(UTILITIES_VERSION)] ? $::env(UTILITIES_VERSION) \
                     : [expr {[info exists ::env(CBFLOW_RELEASE_VERSION)] ? $::env(CBFLOW_RELEASE_VERSION) : "v1.0.0"}]}]

if {$_root_env eq ""} {
    puts "ERROR: logo_config.tcl: neither FLOW_ROOT nor FLOW_DIR is set."
    exit 1
}

set _error_utils_path "$_root_env/utils/utilities/$_utils_ver/error_utils.tcl"
if {[file exists $_error_utils_path]} {
    source $_error_utils_path
} else {
    puts "ERROR: logo_config.tcl: error_utils.tcl not found at $_error_utils_path"
    exit 1
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
        display,use_unicode_borders true
        display,logo_width 77
        display,center_text true
    }

    #===========================================================================
    # CONFIGURATION LOADING PROCEDURES
    #===========================================================================

    proc load_logo_configuration {} {
        variable logo_data
        global logo

        CBFLOW_HEADER "CBFlow Logo Configuration"

        # Step 1: Copy logo data to global logo array
        CBFLOW_SECTION "Loading Logo Configuration Data"
        array set logo [array get logo_data]

        # Step 2: Add static version + dynamic build date
        set logo(version) "v1.0.0"
        set logo(build_date) [clock format [clock seconds] -format "%Y-%m-%d"]
        CBFLOW_DEBUG "Version: $logo(version)  build_date: $logo(build_date)" "CONFIG"

        # Step 3: Validate configuration completeness
        if {![validate_logo_configuration]} {
            CBFLOW_ERROR "Logo configuration validation failed" "CONFIG"
            return 0
        }

        CBFLOW_SUCCESS "Logo configuration loaded successfully - $logo(name) $logo(version)" "CONFIG"
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
