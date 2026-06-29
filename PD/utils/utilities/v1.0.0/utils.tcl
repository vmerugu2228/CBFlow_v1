#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Utilities Library
#
# Description: Complete utilities library with clean namespace architecture
# Version: 3.0.0
# Author: CBFlow Management System
#
# Features:
# - Clean namespace architecture
# - Environment variable integration
# - Standardized error handling
# - Backward compatibility
# - Modular design
#===============================================================================

# Load standardized error handling utilities
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/error_utils.tcl"

# Clean namespace for CBFlow utilities
namespace eval ::CBFlow::Utilities {

    #===========================================================================
    # VERSION AND CONSTANTS
    #===========================================================================

    variable UTILS_VERSION "3.0.0"
    variable UTILS_DATE "2025-09-24"

    #===========================================================================
    # ENVIRONMENT VALIDATION PROCEDURES
    #===========================================================================

    proc validate_environment {} {
        CBFLOW_HEADER "CBFlow Utilities - Environment Validation"

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
            TECH_CONFIG_VERSION
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

        CBFLOW_SUCCESS "Utilities environment validation completed with version-based structure" "ENV_VALIDATION"
        return 1
    }

    #===========================================================================
    # LOGO AND BRANDING PROCEDURES
    #===========================================================================

    proc get_early_logo_name {{flow_dir ""}} {
        # Get logo name early by reading directly from logo configuration file
        # This avoids any conflicts with global flow array state

        # Construct logo config path using FLOW_ROOT and version
        if {[info exists ::env(FLOW_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
            set logo_config "$::env(FLOW_ROOT)/config/flow/$::env(FLOW_CONFIG_VERSION)/logo_config.tcl"
        } else {
            return "CBFlow"
        }

        if {![file exists $logo_config]} {
            return "CBFlow"
        }

        # Read logo name directly from file to avoid any global state conflicts
        if {[catch {
            set fp [open $logo_config r]
            set found_logo "CBFlow"

            while {[gets $fp line] >= 0} {
                # Look for logo(name) pattern in the new format
                if {[regexp {name\s+\"([^\"]+)\"} $line -> logo_name]} {
                    set found_logo $logo_name
                    break
                }
            }
            close $fp
        } error]} {
            CBFLOW_WARNING "Failed to read logo config: $error" "LOGO"
            return "CBFlow"
        }

        return $found_logo
    }

    proc get_logo_name {} {
        # Backward compatibility wrapper
        return [get_early_logo_name]
    }

    proc get_early_company_info {{flow_dir ""}} {
        # Get company information from logo configuration
        set company "CBFlow Development Team"
        set tagline "Physical Design Automation Framework"
        set copyright "© 2024 CBFlow Development Team. All rights reserved."
        set version "v3.0.0"
        set logo_message ""

        # Try to read from logo configuration using version-based path
        if {[info exists ::env(FLOW_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
            set logo_config "$::env(FLOW_ROOT)/config/flow/$::env(FLOW_CONFIG_VERSION)/logo_config.tcl"
            if {[file exists $logo_config]} {
                if {[catch {
                    # Load logo configuration to get updated info
                    global logo
                    source $logo_config

                if {[info exists logo(description)]} {
                    set tagline $logo(description)
                }
                if {[info exists logo(copyright)]} {
                    set copyright $logo(copyright)
                }
                if {[info exists logo(version)]} {
                    set version $logo(version)
                }
                if {[info exists logo(message)]} {
                    set logo_message $logo(message)
                }
            } error]} {
                CBFLOW_DEBUG "Could not load logo config: $error" "LOGO"
            }
        }

        return [list $company $tagline $copyright $version $logo_message]
    }

    #===========================================================================
    # LEGACY COMPATIBILITY PROCEDURES
    #===========================================================================

    # Legacy error handling procedures - redirect to new standardized functions
    proc handle_error {message {exit_code 1}} {
        CBFLOW_ERROR $message "LEGACY"
        if {$exit_code != 0} {
            exit $exit_code
        }
    }

    proc handle_warning {message} {
        CBFLOW_WARNING $message "LEGACY"
    }

    proc handle_info {message} {
        CBFLOW_INFO $message "LEGACY"
    }

    proc print_message {level message} {
        # Legacy message printing - redirect to new functions
        switch $level {
            "INFO" {
                CBFLOW_INFO $message "LEGACY"
            }
            "WARNING" {
                CBFLOW_WARNING $message "LEGACY"
            }
            "ERROR" {
                CBFLOW_ERROR $message "LEGACY" 0
            }
            default {
                puts $message
            }
        }
    }

    #===========================================================================
    # ASCII ART GENERATION PROCEDURES
    #===========================================================================

    proc generate_large_ascii_char {char} {
        # Generate large ASCII representation of a single character (5 lines tall)
        # Each character is 6 wide with 1 space padding for separation
        switch [string toupper $char] {
            "C" { return [list " █████ " "██     " "██     " "██     " " █████ "] }
            "B" { return [list "██████ " "██  ██ " "██████ " "██  ██ " "██████ "] }
            "F" { return [list "██████ " "██     " "█████  " "██     " "██     "] }
            "L" { return [list "██     " "██     " "██     " "██     " "██████ "] }
            "O" { return [list " █████ " "██  ██ " "██  ██ " "██  ██ " " █████ "] }
            "W" { return [list "██  ██ " "██  ██ " "██  ██ " "██████ " "██████ "] }
            " " { return [list "       " "       " "       " "       " "       "] }
            default { return [list "██████ " "██  ██ " "██  ██ " "██  ██ " "██████ "] }
        }
    }

    proc generate_text_logo {text} {
        # Generate large ASCII art for given text
        set lines [list "" "" "" "" ""]

        for {set i 0} {$i < [string length $text]} {incr i} {
            set char [string index $text $i]
            set char_lines [generate_large_ascii_char $char]

            for {set j 0} {$j < 5} {incr j} {
                lset lines $j "[lindex $lines $j][lindex $char_lines $j]"
            }
        }

        return $lines
    }

    #===========================================================================
    # PROGRESS AND STATUS PROCEDURES
    #===========================================================================

    proc print_header {title} {
        CBFLOW_HEADER $title
    }

    proc print_separator {} {
        puts [string repeat "=" 80]
    }

    proc show_progress {percentage message} {
        # Simple progress display
        set bar_width 40
        set filled [expr {int($percentage * $bar_width / 100)}]
        set empty [expr {$bar_width - $filled}]

        set progress_bar "[string repeat "█" $filled][string repeat "░" $empty]"
        puts -nonewline "\r\[${progress_bar}\] ${percentage}% - $message"
        flush stdout
    }

    #===========================================================================
    # CONFIGURATION LOADING PROCEDURES
    #===========================================================================

    proc load_hierarchical_configuration {} {
        # Load hierarchical configuration if available
        global pnr synth project tech flow runtime tools output

        # Initialize global arrays for backward compatibility (handle existing variables gracefully)
        foreach var_name {pnr synth project tech flow runtime tools output} {
            if {![info exists $var_name]} {
                array set $var_name {}
            } elseif {![array exists $var_name]} {
                # Variable exists but is not an array - convert it
                set temp_value [set $var_name]
                unset $var_name
                array set $var_name {}
                CBFLOW_DEBUG "Converted variable '$var_name' from scalar to array (was: $temp_value)" "CONFIG"
            }
        }

        CBFLOW_SECTION "Loading Hierarchical Configuration"

        # Construct configuration paths using FLOW_ROOT and versions
        set flow_root $::env(FLOW_ROOT)
        set config_files [list]

        # Flow configuration
        lappend config_files "$flow_root/config/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"

        # Project configuration (use default if not specified)
        if {[info exists ::env(CBFLOW_PROJECT_NAME)] && $::env(CBFLOW_PROJECT_NAME) ne ""} {
            set project_name $::env(CBFLOW_PROJECT_NAME)
        } elseif {[info exists ::env(PROJECT_NAME)] && $::env(PROJECT_NAME) ne ""} {
            set project_name $::env(PROJECT_NAME)
        } else {
            puts "ERROR: CBFLOW_PROJECT_NAME not set — cannot load project config"
            return
        }
        lappend config_files "$flow_root/config/project/$project_name/$::env(PROJECT_CONFIG_VERSION)/phoenix_config.tcl"

        # Technology configuration (use default if not specified)
        if {[info exists ::env(CBFLOW_TECH_NODE)] && $::env(CBFLOW_TECH_NODE) ne ""} {
            set tech_node $::env(CBFLOW_TECH_NODE)
        } elseif {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne ""} {
            set tech_node $::env(TECH_NAME)
        } else {
            puts "ERROR: TECH_NAME not set — cannot load tech config"
            return
        }
        lappend config_files "$flow_root/config/tech/$tech_node/$::env(TECH_CONFIG_VERSION)/tech_config.tcl"

        set loaded_count 0
        foreach config_file $config_files {
            if {[file exists $config_file]} {
                if {[catch {source $config_file} error]} {
                    CBFLOW_WARNING "Failed to load config $config_file: $error" "CONFIG"
                } else {
                    CBFLOW_DEBUG "Loaded configuration: $config_file" "CONFIG"
                    incr loaded_count
                }
            } else {
                CBFLOW_DEBUG "Configuration file not found: $config_file" "CONFIG"
            }
        }

        if {$loaded_count > 0} {
            CBFLOW_SUCCESS "Loaded $loaded_count configuration files" "CONFIG"
            return 1
        } else {
            CBFLOW_WARNING "No configuration files loaded" "CONFIG"
            return 0
        }
    }

    #===========================================================================
    # MAIN INITIALIZATION PROCEDURE
    #===========================================================================

    proc initialize_utilities {} {
        # Main initialization procedure
        CBFLOW_HEADER "CBFlow Utilities Library v$::CBFlow::Utilities::UTILS_VERSION"

        # Step 1: Validate environment
        if {![validate_environment]} {
            CBFLOW_WARNING "Environment validation issues detected" "INIT"
        }

        # Step 2: Load hierarchical configuration
        load_hierarchical_configuration

        # Step 3: Display initialization message
        set logo_name [get_logo_name]
        CBFLOW_SUCCESS "$logo_name Complete Utilities v$::CBFlow::Utilities::UTILS_VERSION loaded" "INIT"
        CBFLOW_INFO "Flow log level: info" "INIT"

        return 1
    }
}
# Main namespace should close here
}

#===============================================================================
# GLOBAL BACKWARD COMPATIBILITY
#===============================================================================

# Export legacy procedures to global namespace for backward compatibility
namespace eval :: {
    # Import utility procedures
    namespace import ::CBFlow::Utilities::handle_error
    namespace import ::CBFlow::Utilities::handle_warning
    namespace import ::CBFlow::Utilities::handle_info
    namespace import ::CBFlow::Utilities::print_message
    namespace import ::CBFlow::Utilities::get_logo_name
    namespace import ::CBFlow::Utilities::get_early_logo_name
    namespace import ::CBFlow::Utilities::get_early_company_info
    namespace import ::CBFlow::Utilities::print_header
    namespace import ::CBFlow::Utilities::print_separator
    namespace import ::CBFlow::Utilities::show_progress
    namespace import ::CBFlow::Utilities::generate_large_ascii_char
    namespace import ::CBFlow::Utilities::generate_text_logo
}

# Declare global arrays for hierarchical variables (backward compatibility)
global pnr synth project tech flow runtime tools output

#===============================================================================
# AUTO-INITIALIZATION
#===============================================================================

# Initialize utilities when sourced
if {![info exists ::cbflow_utils_loaded]} {
    set ::cbflow_utils_loaded true

    # Provide simple legacy functions globally
    proc ::handle_warning {message} {
        puts "⚠ \[CBFlow_WARNING\] $message"
    }
    proc ::handle_error {message {exit_code 1}} {
        puts "✗ \[CBFlow_ERROR\] $message"
        if {$exit_code != 0} {
            exit $exit_code
        }
    }
    proc ::handle_info {message} {
        puts "ℹ \[CBFlow_INFO\] $message"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW PROCEDURE MANAGEMENT SYSTEM (Golden Legacy Implementation)
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize flow procedure registry
namespace eval ::flow {
    variable procs
    variable steps {}
    variable current_step 0
    variable debug_mode 0
    variable log_level "info"  # Options: debug, info, warning, error

    # Customization hooks
    variable prepend
    variable append
    variable replace
}

proc flow_proc {name body} {
    # Register a flow procedure with the flow management system
    set ::flow::procs($name) $body
    # Track definition order for auto-execution via flow_exec_all
    if {$name ni $::flow::steps} {
        lappend ::flow::steps $name
    }
    handle_info "Flow procedure '$name' registered (step [lsearch $::flow::steps $name])"
}

proc flow_exec {name} {
    # Execute a specific flow procedure
    if {![info exists ::flow::procs($name)]} {
        handle_error "Flow procedure '$name' not found"
        return
    }

    set _test_mode [expr {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"}]

    if {$_test_mode} {
        handle_info "── flow_proc: $name ──"
    } else {
        handle_info "Executing flow procedure: $name"
    }

    # Execute prepend hooks if they exist
    if {[info exists ::flow::prepend($name)]} {
        eval $::flow::prepend($name)
    }

    # In test mode, install EDA command interceptor before execution
    if {$_test_mode} {
        _cbflow_test_mode_enable
    }

    # Execute the main procedure (errors propagate — missing vars crash immediately)
    eval $::flow::procs($name)

    # Restore after execution
    if {$_test_mode} {
        _cbflow_test_mode_disable
    }

    # Execute append hooks if they exist
    if {[info exists ::flow::append($name)]} {
        eval $::flow::append($name)
    }

    handle_info "Flow procedure '$name' completed"
}

proc flow_exec_all {} {
    # Execute all registered flow procedures in DEFINITION ORDER
    if {[llength $::flow::steps] == 0} {
        handle_warning "No flow steps registered"
        return
    }

    set _test_mode [expr {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"}]

    if {$_test_mode} {
        handle_info "═══════════════════════════════════════════════════════"
        handle_info "  CBflow TEST MODE — flow_proc dry run"
        handle_info "  All variables resolved, EDA commands printed (not executed)"
        handle_info "═══════════════════════════════════════════════════════"
    }

    handle_info "Executing all flow procedures ([llength $::flow::steps] steps)..."
    foreach name $::flow::steps {
        if {[info exists ::flow::procs($name)]} {
            flow_exec $name
        }
    }
    handle_info "All flow procedures completed"
}

# ── Test Mode: EDA Command Interceptor ────────────────────────────────────────
# In test_mode, command files run under tclsh (not genus/innovus/fc_shell).
# EDA-specific commands don't exist in tclsh and trigger TCL's 'unknown' proc.
# We override 'unknown' to print the command with fully-resolved arguments
# instead of erroring out. TCL builtins (file, puts, set, if, foreach, etc.)
# execute normally — only EDA commands are intercepted.

proc _cbflow_test_mode_enable {} {
    # Save original unknown handler if present
    if {[info commands unknown] ne "" && [info commands _cbflow_saved_unknown] eq ""} {
        rename unknown _cbflow_saved_unknown
    }

    # Override exit to prevent tclsh termination in test mode
    if {[info commands _cbflow_saved_exit] eq ""} {
        rename exit _cbflow_saved_exit
        proc exit {{code 0}} {
            puts "  TEST_CMD: exit $code (intercepted — continuing)"
        }
    }

    # Install EDA command interceptor
    proc unknown {cmd args} {
        # Format command with fully-resolved argument values
        set _parts [list $cmd]
        foreach _a $args { lappend _parts $_a }
        puts "  TEST_CMD: [join $_parts { }]"

        # Return sensible defaults for query commands so conditionals work
        switch -glob -- $cmd {
            "get_db"              { return "test_value" }
            "get_object_name"     { return "test_design" }
            "sizeof_collection"   { return 0 }
            "current_design"      { return "test_design" }
            "current_mode"        { return "func" }
            "current_block"       { return "" }
            "all_modes"           { return "" }
            "all_clocks"          { return "" }
            "get_cells"           { return "" }
            "get_scenarios"       { return "" }
            "get_lib_cells"       { return "" }
            "get_ports"           { return "" }
            "get_pins"            { return "" }
            "get_site_rows"       { return "" }
            "get_object_name"     { return "" }
            "foreach_in_collection" {
                # foreach_in_collection var collection body — skip body
                return ""
            }
            "redirect" {
                # redirect -file <path> { body } — execute body (which will also be intercepted)
                set _body [lindex $args end]
                if {$_body ne ""} {
                    catch { uplevel 1 $_body }
                }
                return ""
            }
            default               { return "" }
        }
    }
}

proc _cbflow_test_mode_disable {} {
    # Remove interceptor and restore original unknown
    if {[info commands unknown] ne ""} {
        rename unknown ""
    }
    if {[info commands _cbflow_saved_unknown] ne ""} {
        rename _cbflow_saved_unknown unknown
    }
    # Restore exit
    if {[info commands _cbflow_saved_exit] ne ""} {
        rename exit ""
        rename _cbflow_saved_exit exit
    }
}

proc flow_set_log_level {level} {
    # Set logging level
    set ::flow::log_level $level
    handle_info "Flow log level set to: $level"
}

proc flow_list {} {
    # List all registered flow procedures
    set proc_list [array names ::flow::procs]
    if {[llength $proc_list] == 0} {
        puts "No flow procedures registered"
    } else {
        puts "Registered flow procedures:"
        foreach name [lsort $proc_list] {
            puts "  - $name"
        }
    }
}

proc flow_info {name} {
    # Get information about a specific flow procedure
    if {![info exists ::flow::procs($name)]} {
        handle_error "Flow procedure '$name' not found"
        return
    }

    puts "Flow procedure: $name"
    puts "Body: $::flow::procs($name)"

    if {[info exists ::flow::prepend($name)]} {
        puts "Prepend hook: $::flow::prepend($name)"
    }

    if {[info exists ::flow::append($name)]} {
        puts "Append hook: $::flow::append($name)"
    }
}

proc flow_add_prepend {name code} {
    # Add prepend code to a flow procedure
    if {[info exists ::flow::prepend($name)]} {
        append ::flow::prepend($name) "\n$code"
    } else {
        set ::flow::prepend($name) $code
    }
    handle_info "Added prepend hook to flow procedure '$name'"
}

proc flow_add_append {name code} {
    # Add append code to a flow procedure
    if {[info exists ::flow::append($name)]} {
        append ::flow::append($name) "\n$code"
    } else {
        set ::flow::append($name) $code
    }
    handle_info "Added append hook to flow procedure '$name'"
}

proc flow_replace {name new_body} {
    # Replace a flow procedure completely
    set ::flow::procs($name) $new_body
    handle_info "Flow procedure '$name' replaced"
}

proc flow_reset {} {
    # Reset all flow state (procs, steps, hooks)
    array unset ::flow::procs
    array unset ::flow::prepend
    array unset ::flow::append
    set ::flow::steps {}
    set ::flow::current_step 0
    handle_info "Flow state reset"
}

proc flow_reset_hooks {name} {
    # Reset hooks for a flow procedure
    if {[info exists ::flow::prepend($name)]} {
        unset ::flow::prepend($name)
    }
    if {[info exists ::flow::append($name)]} {
        unset ::flow::append($name)
    }
    handle_info "Hooks reset for flow procedure '$name'"
}

# Now add helper procedures to support the flow_proc_prepend syntax we've been using
proc flow_proc_prepend {name body} {
    # Helper procedure to support the prepend syntax used in setup files
    flow_add_prepend $name $body
}

proc flow_proc_append {name body} {
    # Helper procedure to support the append syntax used in setup files
    flow_add_append $name $body
}

proc flow_proc_replace {name body} {
    # Helper procedure to support the replace syntax used in setup files
    flow_replace $name $body
}

# ── File Validation ────────────────────────────────────────────────────────────

proc validate_file_naming {file_path file_type} {
    global FILE_VALIDATION_RULES
    set ext [file extension $file_path]
    set base [file rootname [file tail $file_path]]
    if {![info exists FILE_VALIDATION_RULES($file_type)]} {
        return [list false "Unknown file type: $file_type"]
    }
    if {[lsearch -exact $FILE_VALIDATION_RULES($file_type) $ext] == -1} {
        return [list false "Invalid extension '$ext' for $file_type. Expected: [join $FILE_VALIDATION_RULES($file_type) {, }]"]
    }
    if {![regexp {^[a-zA-Z][a-zA-Z0-9_]*$} $base]} {
        return [list false "Invalid name '$base'. Must start with letter, contain only [a-zA-Z0-9_]"]
    }
    return [list true "Valid"]
}

# ── MMMC Utilities ────────────────────────────────────────────────────────────

proc is_mmmc_stage {stage_name} {
    global flow
    return [expr {[lsearch $flow(mmmc,enabled_stages) $stage_name] != -1}]
}

proc load_mmmc_config {} {
    global flow FLOW_DIR
    if {!$flow(mmmc,enabled)} { return false }
    set mmmc_path "$FLOW_DIR/config/mmmc_config.tcl"
    if {[file exists $mmmc_path]} {
        source $mmmc_path
        return true
    }
    puts "ERROR: MMMC config not found: $mmmc_path"
    exit 1
}

# ── Runtime Directory Setup ────────────────────────────────────────────────────
# Called by command files: setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
# Sets DIRS() array + backward-compat vars (WORK_DIR, REPORTS_DIR, etc.)

# ── VT Flavor Selection — dont_use excluded VT cells ─────────────────────
# Called in every optimization stage (init_design through pro).
# Reads project(vt_flavors) for allowed VTs.
# Cells matching excluded VT patterns get set_lib_cell_purpose -exclude.
# Existing dont_use and dont_touch settings are preserved.
proc apply_vt_dont_use {} {
    if {![info exists ::project(vt_flavors)]} { return }
    if {![info exists ::tech(vt_variants_available)]} { return }

    set _use_vts $::project(vt_flavors)
    set _excluded 0

    # Detect tool: FC uses set_lib_cell_purpose, Innovus uses setDontUse
    set _is_innovus [expr {[info commands setDontUse] ne ""}]

    foreach _vt $::tech(vt_variants_available) {
        if {[lsearch -exact $_use_vts $_vt] < 0} {
            if {[info exists ::tech(vt_pattern,$_vt)]} {
                set _pattern $::tech(vt_pattern,$_vt)
                if {$_is_innovus} {
                    # Innovus: setDontUse <pattern> true
                    catch { setDontUse $_pattern true }
                    puts "INFO: VT dont_use (Innovus): $_vt ($_pattern)"
                    incr _excluded
                } else {
                    # FC: set_lib_cell_purpose -exclude optimization
                    set _cells [get_lib_cells $_pattern -quiet]
                    if {$_cells ne "" && [sizeof_collection $_cells] > 0} {
                        set_lib_cell_purpose -exclude optimization $_cells
                        set _count [sizeof_collection $_cells]
                        puts "INFO: VT dont_use: $_vt ($_pattern) — $_count cells excluded"
                        incr _excluded $_count
                    }
                }
            }
        }
    }

    if {$_excluded > 0} {
        puts "INFO: VT selection: using {$_use_vts}, excluded $_excluded cells/patterns"
    }
}

# ── Dynamic config-array accessor for shared cmd files ─────────────────────
# Same-tool cmd files (synopsys/fc cts_fc.tcl etc.) are shared byte-identical
# across PNR and SYNTH_PNR. The active flow's config lives in a flow-specific
# array — pnr() for PNR, synth_pnr() for SYNTH_PNR. cfg_get does the dynamic
# resolution so the cmd file body stays flow-agnostic.
#
# Lookup: $<flow_array>(<key>) where <flow_array> = string tolower $::flow_type.
# Returns $default if key absent or empty.
proc cfg_get {key {default ""}} {
    if {![info exists ::flow_type]} { return $default }
    upvar #0 [string tolower $::flow_type] arr
    if {[info exists arr($key)] && $arr($key) ne ""} { return $arr($key) }
    return $default
}

# Like cfg_get but returns the literal $default (no empty-string coercion).
# Use when "" is itself a meaningful value.
proc cfg_get_exact {key {default ""}} {
    if {![info exists ::flow_type]} { return $default }
    upvar #0 [string tolower $::flow_type] arr
    if {[info exists arr($key)]} { return $arr($key) }
    return $default
}

# Predicate: is $<flow_array>(<key>) set to a truthy value?
proc cfg_true {key} {
    if {![info exists ::flow_type]} { return 0 }
    upvar #0 [string tolower $::flow_type] arr
    if {![info exists arr($key)]} { return 0 }
    if {$arr($key) eq ""} { return 0 }
    return [string is true -strict $arr($key)]
}

# Stage cfg(<stage>,redhawk,*) into the ::REDHAWK_* globals that
# redhawk_fc.tcl reads. Per-stage knob falls back to common knob, then to
# the recipe's own default. Used by `redhawk_rail_analysis` flow_procs in
# cts_opt_fc.tcl / pro_fc.tcl / signoff_fc.tcl.
proc redhawk_stage_globals {stage} {
    set ::REDHAWK_STAGE              $stage
    set ::REDHAWK_GAD_FILE           [cfg_get $stage,redhawk,gad_file           [cfg_get common,redhawk,gad_file           ""]]
    set ::REDHAWK_TECH_FILE          [cfg_get $stage,redhawk,tech_file          [cfg_get common,redhawk,tech_file          ""]]
    set ::REDHAWK_POWER_NET          [cfg_get $stage,redhawk,power_net          [cfg_get common,redhawk,power_net          ""]]
    set ::REDHAWK_GROUND_NET         [cfg_get $stage,redhawk,ground_net         [cfg_get common,redhawk,ground_net         ""]]
    set ::REDHAWK_SCENARIO           [cfg_get $stage,redhawk,scenario           [cfg_get common,redhawk,scenario           ""]]
    set ::REDHAWK_IR_THRESHOLD       [cfg_get $stage,redhawk,ir_threshold       [cfg_get common,redhawk,ir_threshold       "0.05"]]
    set ::REDHAWK_SWITCHING_ACTIVITY [cfg_get $stage,redhawk,switching_activity [cfg_get common,redhawk,switching_activity ""]]
    set ::REDHAWK_STATIC             [cfg_get $stage,redhawk,static_ir          [cfg_get common,redhawk,static_ir          "true"]]
    set ::REDHAWK_DYNAMIC            [cfg_get $stage,redhawk,dynamic_ir         [cfg_get common,redhawk,dynamic_ir         "true"]]
    set ::REDHAWK_EM                 [cfg_get $stage,redhawk,em_analysis        [cfg_get common,redhawk,em_analysis        "false"]]
    set ::REDHAWK_FIX_VIOLATORS      [cfg_get $stage,redhawk,fix_violators      [cfg_get common,redhawk,fix_violators      "true"]]
    set ::REDHAWK_NUM_CPUS           [cfg_get $stage,redhawk,num_cpus           [cfg_get common,redhawk,num_cpus           "8"]]
    set ::REDHAWK_REPORTS_DIR        ""
}

# Predicate: did the user enable RedHawk for this stage? Per-stage flag OR
# the global common knob — either turns it on.
proc redhawk_enabled {stage} {
    if {[cfg_true $stage,redhawk_enable]} { return 1 }
    if {[cfg_true common,redhawk_enable]} { return 1 }
    return 0
}

# Stage cfg(<stage>,lowpower,*) into the ::LOWPOWER_* globals that
# lowpower_fc.tcl reads. Per-stage knob falls back to common, then to recipe
# defaults. Used by `insert_low_power_cells` flow_proc in place_fc.tcl.
proc lowpower_stage_globals {stage} {
    set ::LOWPOWER_STAGE                 $stage
    set ::LOWPOWER_ENABLE_PWR_SWITCH     [cfg_get $stage,lowpower,power_switches    [cfg_get common,lowpower,power_switches    "true"]]
    set ::LOWPOWER_ENABLE_ISOLATION      [cfg_get $stage,lowpower,isolation_cells   [cfg_get common,lowpower,isolation_cells   "true"]]
    set ::LOWPOWER_ENABLE_LEVEL_SHIFTER  [cfg_get $stage,lowpower,level_shifters    [cfg_get common,lowpower,level_shifters    "true"]]
    set ::LOWPOWER_ENABLE_AON_BUFFER     [cfg_get $stage,lowpower,always_on_buffers [cfg_get common,lowpower,always_on_buffers "true"]]
    set ::LOWPOWER_PWR_SWITCH_LIBCELL    [cfg_get $stage,lowpower,power_switch_lib_cells [cfg_get common,lowpower,power_switch_lib_cells ""]]
    set ::LOWPOWER_REPORTS_DIR           ""
}

# Predicate: did the user enable low-power insertion for this stage?
# Per-stage flag OR common knob → on.
proc lowpower_enabled {stage} {
    if {[cfg_true $stage,lowpower_enable]} { return 1 }
    if {[cfg_true common,lowpower_enable]} { return 1 }
    return 0
}

# ── Per-stage block-state (bypass-safe load_design) ───────────────────────
# Each FC PnR stage that calls `save_block -as <design>/<block>` writes a
# tiny Tcl-sourceable text file at
#   <run_dir>/.cbflow_block_state/<stage>.tcl
# containing the block name it just saved. The next stage's load_design
# walks back through its known upstream chain (most-recent first), reads
# the FIRST file that exists, and uses that block as the copy_block source.
#
# When a stage is bypassed, the engine deletes its per-stage file. When a
# stage is retraced/invalidated, same — the engine deletes its file. So the
# walk-back automatically lands on the most recent stage that's both (a)
# completed and (b) NOT bypassed. Zero FC invocations during bypass.
#
# Corner case this fixes vs. the single-file manifest: after a full run
# completes (signoff.tcl exists), bypassing cts+cts_opt and retracing from
# route would leave the single manifest pointing at "signoff" — load_design
# would try to copy the FULLY ROUTED block as input. Per-stage files plus
# engine cleanup eliminates the stale-pointer case.

proc cbflow_record_block_state {stage_name block_name {node_name ""}} {
    set _dir "$::env(CBFLOW_RUN_DIR)/.cbflow_block_state"
    file mkdir $_dir
    set _f "$_dir/${stage_name}.tcl"
    set _ts [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]
    set fh [open $_f w]
    puts $fh "# Auto-generated by CBflow — block saved by stage '$stage_name'."
    puts $fh "set ::CBFLOW_BLOCK_${stage_name}        \"$block_name\""
    puts $fh "set ::CBFLOW_BLOCK_${stage_name}_NODE   \"$node_name\""
    puts $fh "set ::CBFLOW_BLOCK_${stage_name}_TS     \"$_ts\""
    close $fh
}

# Walk back through ordered upstream_stages (most-recent first) and return
# the block name from the first per-stage file that exists. Falls back to
# $default if none found.
#
# Example for route_fc.tcl:
#   set _from [cbflow_resolve_head_block "clock_opt_opto" \
#                  {cts_opt cts place init_design}]
proc cbflow_resolve_head_block {default upstream_stages} {
    set _dir "$::env(CBFLOW_RUN_DIR)/.cbflow_block_state"
    foreach _s $upstream_stages {
        set _f "$_dir/${_s}.tcl"
        if {[file exists $_f]} {
            source $_f
            set _var "::CBFLOW_BLOCK_${_s}"
            if {[info exists $_var] && [set $_var] ne ""} {
                return [set $_var]
            }
        }
    }
    return $default
}

proc setup_dirs {run_dir flow_type node_name} {
    global DIRS
    set DIRS(run)         $run_dir
    set DIRS(work)        "$run_dir/work/$flow_type/$node_name"
    set DIRS(reports)     "$run_dir/work/$flow_type/$node_name/reports"
    set DIRS(outputs)     "$run_dir/outputs"
    set DIRS(logs)        "$run_dir/logs"
    set DIRS(setup)       "$run_dir/setup"
    set DIRS(rtl)         "$run_dir/work/$flow_type/rtl1/rtl"
    set DIRS(sdc)         "$run_dir/work/$flow_type/sdc1/sdc"
    set DIRS(upf)         "$run_dir/work/$flow_type/upf1/upf"
    set DIRS(netlist)     "$run_dir/work/$flow_type/netlist1/netlist"
    set DIRS(def)         "$run_dir/work/$flow_type/def1/def"
    set DIRS(gds)         "$run_dir/work/$flow_type/gds1/gds"
    set DIRS(spef)        "$run_dir/work/$flow_type/spef1/spef"
    set DIRS(library)     "$run_dir/work/$flow_type/library1/library"
    file mkdir $DIRS(reports)
    file mkdir $DIRS(outputs)
    # Backward compat — old variable names
    foreach {old new} {
        WORK_DIR work  REPORTS_DIR reports  OUTPUTS_DIR outputs
        RTL_DIR rtl  SDC_DIR sdc  UPF_DIR upf
        NETLIST_DIR netlist  DEF_DIR def  GDS_DIR gds
        SPEF_DIR spef  LIBRARY_DIR library
    } { uplevel 1 [list set $old $DIRS($new)] }
    uplevel 1 [list set INPUTS_DIR "$run_dir/work/$flow_type/rtl1"]
}

# Legacy completion message (debug only)
if {[info exists ::env(CBFLOW_DEBUG)] && $::env(CBFLOW_DEBUG) eq "1"} {
    puts "CBFlow utilities loaded successfully"
}