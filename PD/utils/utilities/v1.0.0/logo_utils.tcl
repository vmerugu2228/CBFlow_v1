#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Logo Utilities
#
# Description: Logo display, branding, and template utilities with version-based architecture
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

# Clean namespace for CBFlow logo utilities
namespace eval ::CBFlow::Logo {

    #===========================================================================
    # VERSION AND CONSTANTS
    #===========================================================================

    variable LOGO_VERSION "1.0.0"
    variable LOGO_DATE "2025-09-24"

    #===========================================================================
    # ENVIRONMENT VALIDATION PROCEDURES
    #===========================================================================

    proc validate_environment {} {
        CBFLOW_HEADER "CBFlow Logo Utilities - Environment Validation"

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
            CBFLOW_PROJECT_NAME
        }

        foreach var $optional_vars {
            if {[info exists ::env($var)]} {
                CBFLOW_DEBUG "Runtime variable '$var' = $::env($var)" "ENV_VALIDATION"
            } else {
                CBFLOW_DEBUG "Runtime variable '$var' not set" "ENV_VALIDATION"
            }
        }

        CBFLOW_SUCCESS "Logo utilities environment validation completed" "ENV_VALIDATION"
        return 1
    }

    #===========================================================================
    # FLOW SUPPORT PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_supported_flows
    # PURPOSE: Dynamically read supported flows from flow_config.tcl
    # PARAMETERS: None
    # RETURNS: List of supported flow types (UPPERCASE)
    # DEPENDENCIES: flow_config.tcl for flow(types) variable
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_supported_flows {} {
        global flow

        # Try to load flow config if not already loaded using version-based paths
        if {![info exists flow(types)]} {
            set flow_root $::env(FLOW_ROOT)
            set flow_config "$flow_root/config/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
            if {[file exists $flow_config]} {
                if {[catch {source $flow_config} error]} {
                    CBFLOW_WARNING "Failed to load flow configuration: $error" "CONFIG"
                } else {
                    CBFLOW_DEBUG "Loaded flow configuration: $flow_config" "CONFIG"
                }
            } else {
                CBFLOW_WARNING "Flow configuration not found: $flow_config" "CONFIG"
            }
        }

        # Return flow types if available, otherwise return default
        if {[info exists flow(types)]} {
            return $flow(types)
        }

        # Fallback if flow_config.tcl is not available
        return {SYNTH FP PNR LEC EMIR ECO CLP POPT FCFP}
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_flow_description
    # PURPOSE: Get flow description from flow_config.tcl
    # PARAMETERS:
    #   flow_type - Flow type (automatically converted to UPPERCASE)
    # RETURNS: Flow description string
    # DEPENDENCIES: flow_config.tcl for flow(type_descriptions) variable
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_flow_description {flow_type} {
        global flow

        # Ensure flow_type is uppercase
        set flow_type [string toupper $flow_type]

        # Try to load flow config if not already loaded using version-based paths
        if {![info exists flow(type_descriptions)]} {
            set flow_root $::env(FLOW_ROOT)
            set flow_config "$flow_root/config/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
            if {[file exists $flow_config]} {
                if {[catch {source $flow_config} error]} {
                    CBFLOW_WARNING "Failed to load flow configuration: $error" "CONFIG"
                } else {
                    CBFLOW_DEBUG "Loaded flow configuration: $flow_config" "CONFIG"
                }
            } else {
                CBFLOW_WARNING "Flow configuration not found: $flow_config" "CONFIG"
            }
        }

        # Return description if available
        if {[info exists flow(type_descriptions)]} {
            foreach {type desc} $flow(type_descriptions) {
                if {$type eq $flow_type} {
                    return $desc
                }
            }
        }

        # Fallback descriptions
        switch $flow_type {
            "SYNTH" { return "Logic synthesis and optimization" }
            "PNR"   { return "Place and route implementation" }
            "FP"    { return "Floorplanning and power planning" }
            "LEC"   { return "Logic equivalence checking" }
            "EMIR"  { return "Power and thermal analysis" }
            "ECO"   { return "Engineering change orders" }
            "CLP"   { return "Conformal low power verification" }
            "POPT"  { return "Power optimization" }
            "FCFP"  { return "Fullchip floorplanning" }
            default { return "Unknown flow type" }
        }
    }

    #===========================================================================
    # LOGO ACCESS PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_name_for_display
    # PURPOSE: Returns the logo name formatted for display (UPPERCASE)
    # PARAMETERS: None
    # RETURNS: Logo name in UPPERCASE format
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_name_for_display {} {
        global logo
        if {[info exists logo(name)] && $logo(name) ne ""} {
            return [string toupper $logo(name)]
        }
        return "CBFLOW"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_version
    # PURPOSE: Returns the logo version information
    # PARAMETERS: None
    # RETURNS: Version string
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_version {} {
        global logo
        if {[info exists logo(version)]} {
            return $logo(version)
        }
        return "1.0"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_tagline
    # PURPOSE: Returns the logo tagline
    # PARAMETERS: None
    # RETURNS: Tagline string
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_tagline {} {
        global logo
        if {[info exists logo(tagline)]} {
            return $logo(tagline)
        }
        return "Physical Design Automation Framework"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_copyright
    # PURPOSE: Returns the copyright information
    # PARAMETERS: None
    # RETURNS: Copyright string
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_copyright {} {
        global logo
        if {[info exists logo(copyright)]} {
            return $logo(copyright)
        }
        return "© 2024 CBFlow Development Team"
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_message
    # PURPOSE: Returns the welcome message
    # PARAMETERS: None
    # RETURNS: Welcome message string
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_message {} {
        global logo
        if {[info exists logo(message)]} {
            return $logo(message)
        }
        return "Welcome to CBFlow Physical Design Framework"
    }

    #===========================================================================
    # CONFIGURATION VALIDATION PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: validate_config
    # PURPOSE: Validates that all required logo variables are set
    # PARAMETERS: None
    # RETURNS: true if valid, false if missing variables
    # DEPENDENCIES: logo() global array from logo_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc validate_config {} {
        global logo

        set required_vars {name description version copyright}
        set missing_vars {}

        foreach var $required_vars {
            if {![info exists logo($var)] || $logo($var) eq ""} {
                lappend missing_vars $var
            }
        }

        if {[llength $missing_vars] > 0} {
            CBFLOW_WARNING "Missing logo configuration variables: [join $missing_vars {, }]" "VALIDATION"
            return false
        }

        return true
    }

    #===========================================================================
    # TEMPLATE AND VARIABLE SUBSTITUTION PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: substitute_variables
    # PURPOSE: Substitutes logo variables in template strings
    # PARAMETERS:
    #   template_string - Template string with {VARIABLE} placeholders
    # RETURNS: String with variables substituted
    # DEPENDENCIES: logo() array, team() array from team_config.tcl
    # ═══════════════════════════════════════════════════════════════════════════════
    proc substitute_variables {template_string} {
        global logo

        # Source team config for company information using version-based paths
        set flow_root $::env(FLOW_ROOT)

        # Use project name from environment
        if {[info exists ::env(CBFLOW_PROJECT_NAME)] && $::env(CBFLOW_PROJECT_NAME) ne ""} {
            set project_name $::env(CBFLOW_PROJECT_NAME)
        } elseif {[info exists ::env(PROJECT_NAME)] && $::env(PROJECT_NAME) ne ""} {
            set project_name $::env(PROJECT_NAME)
        } else {
            puts "WARNING: project name not available"; set project_name ""
        }

        set team_config "$flow_root/config/project/$project_name/$::env(PROJECT_CONFIG_VERSION)/team_config.tcl"
        if {[file exists $team_config]} {
            if {[catch {source $team_config} error]} {
                CBFLOW_WARNING "Failed to load team configuration: $error" "CONFIG"
            } else {
                CBFLOW_DEBUG "Loaded team configuration: $team_config" "CONFIG"
            }
        } else {
            CBFLOW_DEBUG "Team configuration not found: $team_config" "CONFIG"
        }

        set result $template_string

        # Logo-based substitutions
        if {[info exists logo(name)]} {
            set result [string map [list "{LOGO_NAME}" $logo(name)] $result]
        }
        if {[info exists logo(version)]} {
            set result [string map [list "{VERSION}" $logo(version)] $result]
        }

        # Company information from team config
        global team
        if {[info exists team(company)]} {
            set result [string map [list "{COMPANY}" $team(company)] $result]
        }

        # Add timestamp
        set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
        set result [string map [list "{TIMESTAMP}" $timestamp] $result]

        return $result
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_display_width
    # PURPOSE: Returns the configured display width for logo
    # PARAMETERS: None
    # RETURNS: Display width integer
    # DEPENDENCIES: logo() global array
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_display_width {} {
        global logo
        if {[info exists logo(display,logo_width)]} {
            return $logo(display,logo_width)
        }
        return 77
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: use_unicode_borders
    # PURPOSE: Returns whether to use unicode borders in display
    # PARAMETERS: None
    # RETURNS: Boolean (true/false)
    # DEPENDENCIES: logo() global array
    # ═══════════════════════════════════════════════════════════════════════════════
    proc use_unicode_borders {} {
        global logo
        if {[info exists logo(display,use_unicode_borders)]} {
            return $logo(display,use_unicode_borders)
        }
        return true
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: center_text
    # PURPOSE: Returns whether to center text in logo display
    # PARAMETERS: None
    # RETURNS: Boolean (true/false)
    # DEPENDENCIES: logo() global array
    # ═══════════════════════════════════════════════════════════════════════════════
    proc center_text {} {
        global logo
        if {[info exists logo(display,center_text)]} {
            return $logo(display,center_text)
        }
        return true
    }

    #===========================================================================
    # PUBLIC INFORMATION PROCEDURES
    #===========================================================================

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROCEDURE: get_all_info
    # PURPOSE: Returns all logo information as a dictionary
    # PARAMETERS: None
    # RETURNS: Dictionary with all logo information
    # DEPENDENCIES: logo() global array
    # ═══════════════════════════════════════════════════════════════════════════════
    proc get_all_info {} {
        global logo

        set info_dict [dict create]

        # Add all logo array elements to dictionary
        if {[info exists logo]} {
            foreach key [array names logo] {
                dict set info_dict $key $logo($key)
            }
        }

        return $info_dict
    }

    #===========================================================================
    # MAIN INITIALIZATION PROCEDURE
    #===========================================================================

    proc initialize_logo_utilities {} {
        # Main initialization procedure
        CBFLOW_HEADER "CBFlow Logo Utilities v$::CBFlow::Logo::LOGO_VERSION"

        # Step 1: Validate environment
        if {![validate_environment]} {
            CBFLOW_WARNING "Environment validation issues detected" "INIT"
        }

        # Step 2: Display initialization message
        CBFLOW_SUCCESS "CBFlow Logo Utilities v$::CBFlow::Logo::LOGO_VERSION loaded" "INIT"

        return 1
    }
}

#===============================================================================
# GLOBAL BACKWARD COMPATIBILITY
#===============================================================================

# Export utility procedures to global namespace for backward compatibility
namespace eval :: {
    # Import logo utility procedures
    namespace import ::CBFlow::Logo::get_supported_flows
    namespace import ::CBFlow::Logo::get_flow_description
    namespace import ::CBFlow::Logo::get_name_for_display
    namespace import ::CBFlow::Logo::get_version
    namespace import ::CBFlow::Logo::get_tagline
    namespace import ::CBFlow::Logo::get_copyright
    namespace import ::CBFlow::Logo::get_message
    namespace import ::CBFlow::Logo::validate_config
    namespace import ::CBFlow::Logo::substitute_variables
    namespace import ::CBFlow::Logo::get_display_width
    namespace import ::CBFlow::Logo::use_unicode_borders
    namespace import ::CBFlow::Logo::center_text
    namespace import ::CBFlow::Logo::get_all_info
}

#===============================================================================
# PUBLIC INTERFACE - GLOBAL PROCEDURES FOR BACKWARD COMPATIBILITY
#===============================================================================

# Create aliases for the old function names to maintain compatibility
proc get_supported_flows {} {
    return [::CBFlow::Logo::get_supported_flows]
}

proc get_flow_description {flow_type} {
    return [::CBFlow::Logo::get_flow_description $flow_type]
}

proc get_logo_name_for_display {} {
    return [::CBFlow::Logo::get_name_for_display]
}

proc get_logo_version {} {
    return [::CBFlow::Logo::get_version]
}

proc get_logo_tagline {} {
    return [::CBFlow::Logo::get_tagline]
}

proc get_logo_copyright {} {
    return [::CBFlow::Logo::get_copyright]
}

proc get_logo_message {} {
    return [::CBFlow::Logo::get_message]
}

proc validate_logo_config {} {
    return [::CBFlow::Logo::validate_config]
}

proc substitute_logo_variables {template_string} {
    return [::CBFlow::Logo::substitute_variables $template_string]
}

#===============================================================================
# AUTO-INITIALIZATION
#===============================================================================

# Initialize logo utilities when sourced
if {![info exists ::cbflow_logo_utils_loaded]} {
    if {[::CBFlow::Logo::initialize_logo_utilities]} {
        set ::cbflow_logo_utils_loaded true
    }
}

#===============================================================================
# END OF LOGO UTILITIES
#===============================================================================