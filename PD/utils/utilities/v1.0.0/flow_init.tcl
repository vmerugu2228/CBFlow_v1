#!/usr/bin/env tclsh

#===============================================================================
# CBFlow Initialization Script
#
# Description: Initialize CBFlow environment using project-specific configuration
# Version: 1.0.0
# Author: CBFlow Management System
#
# Usage: flow_init.tcl <initialization_config_path> <workarea_path>
#
# Features:
# - Load project-specific initialization configuration
# - Validate all required files and paths exist
# - Generate .cbflow.env files with all flow pointers
# - Comprehensive error handling and validation
#===============================================================================

# Load error handling utilities first
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir "error_utils.tcl"]

# Configure error handling system
::CBFlowError::configure -timestamps 1 -exit_on_error 1

#===============================================================================
# INITIALIZATION FUNCTIONS
#===============================================================================

proc print_usage {} {
    puts "Usage: flow_init.tcl <initialization_config_path> <workarea_path>"
    puts ""
    puts "Arguments:"
    puts "  initialization_config_path - Path to project-specific initialization_config.tcl"
    puts "  workarea_path             - Path to workarea directory"
    puts ""
    puts "Example:"
    puts "  flow_init.tcl /path/to/project/config/initialization_config.tcl /path/to/workarea"
    puts ""
    exit 1
}

proc validate_arguments {init_config_path workarea_path} {
    CBFLOW_INFO "Validating command line arguments" "INIT"

    # Check if initialization config file exists
    if {![file exists $init_config_path]} {
        CBFLOW_ERROR "Initialization config file does not exist: $init_config_path" "INIT"
        return false
    }

    if {![file isfile $init_config_path]} {
        CBFLOW_ERROR "Initialization config path is not a file: $init_config_path" "INIT"
        return false
    }

    # Check if workarea path exists
    if {![file exists $workarea_path]} {
        CBFLOW_ERROR "Workarea directory does not exist: $workarea_path" "INIT"
        return false
    }

    if {![file isdirectory $workarea_path]} {
        CBFLOW_ERROR "Workarea path is not a directory: $workarea_path" "INIT"
        return false
    }

    # Check if workarea is writable
    if {![file writable $workarea_path]} {
        CBFLOW_ERROR "Workarea directory is not writable: $workarea_path" "INIT"
        return false
    }

    CBFLOW_SUCCESS "Command line arguments validated successfully" "INIT"
    return true
}

proc load_initialization_config {init_config_path} {
    CBFLOW_INFO "Loading initialization configuration from: $init_config_path" "INIT"

    # Source the initialization config file in global scope
    if {[catch {uplevel #0 [list source $init_config_path]} error]} {
        CBFLOW_ERROR "Failed to load initialization config: $error" "INIT"
        return false
    }

    # Check if required functions exist
    set required_procs {
        generate_flow_paths generate_tcl_config_paths
        generate_shell_env generate_tcl_env generate_makefile_env
        validate_init_config validate_flow_paths initialize_flow_environment
    }

    foreach proc_name $required_procs {
        if {[info procs $proc_name] eq ""} {
            CBFLOW_ERROR "Required procedure '$proc_name' not found in initialization config" "INIT"
            return false
        }
    }

    # Check if required arrays exist in global scope
    set required_arrays {project technology flow_settings environment}
    foreach array_name $required_arrays {
        if {![uplevel #0 [list info exists $array_name]]} {
            CBFLOW_ERROR "Required array '$array_name' not found in initialization config" "INIT"
            return false
        }
    }

    # Test access to arrays
    set test_value [uplevel #0 {set project(name)}]
    if {$test_value eq ""} {
        CBFLOW_ERROR "Cannot access array values - initialization config may be incomplete" "INIT"
        return false
    }

    CBFLOW_SUCCESS "Initialization configuration loaded successfully" "INIT"
    return true
}

proc validate_flow_dependencies {workarea_path} {
    CBFLOW_INFO "Validating flow dependencies and file existence" "INIT"

    # Get paths from configuration (call in global scope)
    set paths [uplevel #0 [list generate_flow_paths $workarea_path]]
    set tcl_paths [uplevel #0 [list generate_tcl_config_paths $paths]]

    set validation_errors {}

    # Check critical directories exist
    set critical_dirs {flow_config utils_root config_root scripts_root}
    foreach dir_key $critical_dirs {
        if {[dict exists $paths $dir_key]} {
            set dir_path [dict get $paths $dir_key]
            if {![file exists $dir_path]} {
                lappend validation_errors "Critical directory does not exist: $dir_path"
            } elseif {![file isdirectory $dir_path]} {
                lappend validation_errors "Critical path is not a directory: $dir_path"
            }
        } else {
            lappend validation_errors "Critical directory key '$dir_key' not found in paths"
        }
    }

    # Check critical TCL files exist
    set critical_files {flow_config_tcl error_utils_tcl utils_tcl}
    foreach file_key $critical_files {
        if {[dict exists $tcl_paths $file_key]} {
            set file_path [dict get $tcl_paths $file_key]
            if {![file exists $file_path]} {
                lappend validation_errors "Critical TCL file does not exist: $file_path"
            } elseif {![file isfile $file_path]} {
                lappend validation_errors "Critical TCL path is not a file: $file_path"
            }
        } else {
            lappend validation_errors "Critical file key '$file_key' not found in tcl_paths"
        }
    }

    # Check if technology config path exists (if specified)
    if {[dict exists $paths tech_config]} {
        set tech_path [dict get $paths tech_config]
        if {![file exists $tech_path]} {
            CBFLOW_WARNING "Technology config directory does not exist: $tech_path" "INIT"
            CBFLOW_WARNING "This may be expected if technology is not yet configured" "INIT"
        }
    }

    # Check if project config path exists (if specified)
    if {[dict exists $paths project_config]} {
        set project_path [dict get $paths project_config]
        if {![file exists $project_path]} {
            CBFLOW_WARNING "Project config directory does not exist: $project_path" "INIT"
            CBFLOW_WARNING "This may be expected if project configs are not yet created" "INIT"
        }
    }

    # Report validation results
    if {[llength $validation_errors] > 0} {
        CBFLOW_ERROR "Flow dependency validation failed:" "INIT"
        foreach error $validation_errors {
            CBFLOW_ERROR "  - $error" "INIT"
        }
        return false
    }

    CBFLOW_SUCCESS "Flow dependencies validated successfully" "INIT"
    return true
}

proc generate_environment_files {workarea_path} {
    CBFLOW_INFO "Generating CBFlow environment files" "INIT"

    # Generate all three environment files
    set env_files [list \
        [list "shell" ".cbflow.env" "Shell environment variables"] \
        [list "tcl" ".cbflow.env.tcl" "TCL environment variables"] \
        [list "makefile" ".cbflow.env.make" "Makefile variables"] \
    ]

    set generated_files {}

    foreach file_info $env_files {
        set type [lindex $file_info 0]
        set filename [lindex $file_info 1]
        set description [lindex $file_info 2]
        set filepath [file join $workarea_path $filename]

        CBFLOW_INFO "Generating $description: $filepath" "INIT"

        if {[catch {
            switch $type {
                "shell" { uplevel #0 [list generate_shell_env $workarea_path $filepath] }
                "tcl" { uplevel #0 [list generate_tcl_env $workarea_path $filepath] }
                "makefile" { uplevel #0 [list generate_makefile_env $workarea_path $filepath] }
                default {
                    CBFLOW_ERROR "Unknown environment file type: $type" "INIT"
                    return false
                }
            }
        } error]} {
            CBFLOW_ERROR "Failed to generate $description: $error" "INIT"
            return false
        }

        # Verify file was created
        if {![file exists $filepath]} {
            CBFLOW_ERROR "Environment file was not created: $filepath" "INIT"
            return false
        }

        lappend generated_files $filepath
        CBFLOW_SUCCESS "Generated $description successfully" "INIT"
    }

    CBFLOW_SUCCESS "All environment files generated successfully" "INIT"
    CBFLOW_INFO "Generated files:" "INIT"
    foreach file $generated_files {
        CBFLOW_INFO "  - $file" "INIT"
    }

    return true
}

proc print_initialization_summary {workarea_path} {
    CBFLOW_HEADER "CBFlow Initialization Summary"

    # Print project information
    CBFLOW_SECTION "Project Configuration"
    puts "  Name:        [uplevel #0 {set project(name)}]"
    puts "  Version:     [uplevel #0 {set project(version)}]"
    puts "  Design:      [uplevel #0 {set project(design_top)}]"
    puts "  Description: [uplevel #0 {set project(description)}]"
    puts ""

    # Print technology information
    CBFLOW_SECTION "Technology Configuration"
    puts "  Vendor:      [uplevel #0 {set technology(vendor)}]"
    puts "  Node:        [uplevel #0 {set technology(node)}]"
    puts "  Process:     [uplevel #0 {set technology(process)}]"
    puts "  Version:     [uplevel #0 {set technology(version)}]"
    puts ""

    # Print flow information
    CBFLOW_SECTION "Flow Configuration"
    puts "  Release:     [uplevel #0 {set flow_settings(release_version)}]"
    puts "  Config:      [uplevel #0 {set flow_settings(config_version)}]"
    puts "  Default:     [uplevel #0 {set flow_settings(default_flow)}]"
    puts ""

    # Print generated paths
    CBFLOW_SECTION "Generated Paths"
    set paths [uplevel #0 [list generate_flow_paths $workarea_path]]
    dict for {key value} $paths {
        puts "  [format "%-15s" $key]: $value"
    }
    puts ""

    # Print environment files
    CBFLOW_SECTION "Environment Files Created"
    puts "  .cbflow.env       - Shell environment variables"
    puts "  .cbflow.env.tcl   - TCL environment variables"
    puts "  .cbflow.env.make  - Makefile variables"
    puts ""

    CBFLOW_SUCCESS "CBFlow environment initialized successfully" "INIT"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

proc main {argc argv} {
    CBFLOW_HEADER "CBFlow Initialization Tool"

    # Check command line arguments
    if {$argc != 2} {
        CBFLOW_ERROR "Invalid number of arguments. Expected 2, got $argc" "INIT"
        print_usage
    }

    set init_config_path [lindex $argv 0]
    set workarea_path [lindex $argv 1]

    CBFLOW_INFO "Initialization config: $init_config_path" "INIT"
    CBFLOW_INFO "Workarea path: $workarea_path" "INIT"
    puts ""

    # Step 1: Validate command line arguments
    if {![validate_arguments $init_config_path $workarea_path]} {
        CBFLOW_ERROR "Argument validation failed" "INIT"
        exit 1
    }

    # Step 2: Load initialization configuration
    if {![load_initialization_config $init_config_path]} {
        CBFLOW_ERROR "Failed to load initialization configuration" "INIT"
        exit 1
    }

    # Step 3: Validate configuration itself
    set config_errors [uplevel #0 {validate_init_config}]
    if {[llength $config_errors] > 0} {
        CBFLOW_ERROR "Configuration validation failed:" "INIT"
        foreach error $config_errors {
            CBFLOW_ERROR "  - $error" "INIT"
        }
        exit 1
    }

    # Step 4: Validate flow dependencies and file existence
    if {![validate_flow_dependencies $workarea_path]} {
        CBFLOW_ERROR "Flow dependency validation failed" "INIT"
        exit 1
    }

    # Step 5: Generate environment files
    if {![generate_environment_files $workarea_path]} {
        CBFLOW_ERROR "Failed to generate environment files" "INIT"
        exit 1
    }

    # Step 6: Print summary
    puts ""
    print_initialization_summary $workarea_path

    CBFLOW_SUCCESS "CBFlow initialization completed successfully!" "INIT"
    puts ""
    puts "Next steps:"
    puts "  1. Run 'make list_flows' to see available flows"
    puts "  2. Create user config and run 'make create_run USER_CONFIG=<file>'"
    puts ""

    return 0
}

# Execute main function
if {[info exists argv0] && [file tail $argv0] eq [file tail [info script]]} {
    exit [main $argc $argv]
}