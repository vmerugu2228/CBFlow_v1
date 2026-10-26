#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Restriction Management Script (Refactored)
# Description: Manage and validate restricted configuration variables
# Version: v1.0.0
# Namespace: ::CBFlow::NodeManagement::RestrictionManager
# Usage: tclsh manage_restrictions_refactored.tcl <command> [options]
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Script Initialization ──────────────────────────────────────────────────────┐
# Load common configuration loader first
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/../../common/config_loader.tcl"

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
namespace eval ::CBFlow::NodeManagement::RestrictionManager {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Restriction arrays - loaded from config
    variable RESTRICTED_VARIABLES
    variable RESTRICTED_CATEGORIES
    variable PROJECT_LEADS

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

    # ┌─ Restriction Loading Functions ───────────────────────────────────────────┐

    proc load_restrictions {} {
        variable RESTRICTED_VARIABLES
        variable RESTRICTED_CATEGORIES
        variable PROJECT_LEADS

        # Load from flow configuration - simplified version
        global flow

        # Initialize with common restrictions
        array set RESTRICTED_VARIABLES {
            "flow(design_name)" "critical - affects entire flow"
            "flow(type)" "critical - changes flow behavior"
            "project(name)" "critical - affects configuration paths"
            "tech(node)" "critical - affects technology configuration"
        }

        array set RESTRICTED_CATEGORIES {
            "critical" "Variables that affect flow integrity"
            "timing" "Variables that affect timing closure"
            "power" "Variables that affect power analysis"
        }

        array set PROJECT_LEADS {
            "default" "cbflow-admin@company.com"
        }

        handle_debug "Loaded restriction definitions"
        return true
    }

    # ┌─ Validation Functions ────────────────────────────────────────────────────┐

    proc list_restrictions {} {
        variable RESTRICTED_VARIABLES
        variable RESTRICTED_CATEGORIES

        handle_info "CBFlow Restricted Variables:"
        handle_info "══════════════════════════════"

        foreach category [array names RESTRICTED_CATEGORIES] {
            handle_info ""
            handle_info "Category: [string toupper $category]"
            handle_info "Description: $RESTRICTED_CATEGORIES($category)"
            handle_info "Variables:"

            foreach var [array names RESTRICTED_VARIABLES] {
                if {[string match "*$category*" $RESTRICTED_VARIABLES($var)]} {
                    handle_info "  - $var: $RESTRICTED_VARIABLES($var)"
                }
            }
        }

        return true
    }

    proc validate_restrictions {} {
        variable RESTRICTED_VARIABLES

        handle_info "Validating current configuration for restricted variables..."

        set violations_found false

        # Check current directory for user_config.tcl - use environment variable
        if {[info exists ::env(SETUP_DIR)]} {
            set user_config "$::env(SETUP_DIR)/user_config.tcl"
        } else {
            set user_config "$::env(CBFLOW_RUN_DIR)/setup/user_config.tcl"
            handle_warning "SETUP_DIR not found in environment, using calculated path: $user_config"
        }
        if {[file exists $user_config]} {
            handle_info "Checking: $user_config"

            set fd [open $user_config r]
            set content [read $fd]
            close $fd

            set line_num 0
            foreach line [split $content "\n"] {
                incr line_num
                set line [string trim $line]

                # Skip comments and empty lines
                if {$line eq "" || [string match "#*" $line]} continue

                # Check for restricted variable assignments
                foreach var [array names RESTRICTED_VARIABLES] {
                    if {[string match "*set*$var*" $line]} {
                        handle_warning "Line $line_num: Restricted variable '$var' found"
                        handle_warning "  Reason: $RESTRICTED_VARIABLES($var)"
                        handle_warning "  Line: $line"
                        set violations_found true
                    }
                }
            }
        }

        if {$violations_found} {
            handle_error "Restriction violations found - review required"
            return false
        } else {
            handle_info "No restriction violations found"
            return true
        }
    }

    proc check_file {filename} {
        variable RESTRICTED_VARIABLES

        if {![file exists $filename]} {
            handle_error "File not found: $filename"
            return false
        }

        handle_info "Checking file: $filename"

        set violations_found false
        set fd [open $filename r]
        set content [read $fd]
        close $fd

        set line_num 0
        foreach line [split $content "\n"] {
            incr line_num
            set line [string trim $line]

            # Skip comments and empty lines
            if {$line eq "" || [string match "#*" $line]} continue

            # Check for restricted variable assignments
            foreach var [array names RESTRICTED_VARIABLES] {
                if {[string match "*set*$var*" $line]} {
                    handle_warning "Line $line_num: Restricted variable '$var' found"
                    handle_warning "  Reason: $RESTRICTED_VARIABLES($var)"
                    handle_warning "  Line: $line"
                    set violations_found true
                }
            }
        }

        if {$violations_found} {
            handle_error "Restriction violations found in $filename"
            return false
        } else {
            handle_info "No restriction violations found in $filename"
            return true
        }
    }

    # ┌─ Bypass Management Functions ─────────────────────────────────────────────┐

    proc enable_bypass {reason requester email {approval ""}} {
        # Create bypass configuration
        if {[info exists ::env(SETUP_DIR)]} {
            set bypass_config "$::env(SETUP_DIR)/.bypass_restrictions"
        } else {
            set bypass_config "$::env(CBFLOW_RUN_DIR)/setup/.bypass_restrictions"
            handle_warning "SETUP_DIR not found in environment, using calculated path: $bypass_config"
        }

        handle_info "Creating restriction bypass..."
        handle_info "  Reason: $reason"
        handle_info "  Requester: $requester <$email>"
        if {$approval ne ""} {
            handle_info "  Approval: $approval"
        }

        set fd [open $bypass_config w]
        puts $fd "# CBFlow Restriction Bypass Configuration"
        puts $fd "# Generated: [clock format [clock seconds]]"
        puts $fd ""
        puts $fd "set bypass(enabled) true"
        puts $fd "set bypass(reason) \"$reason\""
        puts $fd "set bypass(requester) \"$requester\""
        puts $fd "set bypass(email) \"$email\""
        puts $fd "set bypass(timestamp) \"[clock format [clock seconds]]\""
        if {$approval ne ""} {
            puts $fd "set bypass(approval) \"$approval\""
        }
        close $fd

        handle_info "Bypass configuration created: $bypass_config"
        handle_warning "Restriction bypass is now ENABLED"

        return true
    }

    proc clear_bypass {} {
        if {[info exists ::env(SETUP_DIR)]} {
            set bypass_config "$::env(SETUP_DIR)/.bypass_restrictions"
        } else {
            set bypass_config "$::env(CBFLOW_RUN_DIR)/setup/.bypass_restrictions"
            handle_warning "SETUP_DIR not found in environment, using calculated path: $bypass_config"
        }

        if {[file exists $bypass_config]} {
            file delete $bypass_config
            handle_info "Restriction bypass cleared"
        } else {
            handle_info "No bypass configuration found"
        }

        return true
    }

    proc show_bypass_status {} {
        if {[info exists ::env(SETUP_DIR)]} {
            set bypass_config "$::env(SETUP_DIR)/.bypass_restrictions"
        } else {
            set bypass_config "$::env(CBFLOW_RUN_DIR)/setup/.bypass_restrictions"
            handle_warning "SETUP_DIR not found in environment, using calculated path: $bypass_config"
        }

        if {![file exists $bypass_config]} {
            handle_info "Restriction bypass: DISABLED"
            return true
        }

        handle_info "Restriction bypass: ENABLED"
        handle_info "Configuration: $bypass_config"

        # Load and display bypass information
        if {[catch {source $bypass_config}]} {
            handle_error "Failed to load bypass configuration"
            return false
        }

        global bypass
        if {[info exists bypass]} {
            handle_info "Details:"
            foreach key [array names bypass] {
                handle_info "  $key: $bypass($key)"
            }
        }

        return true
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Restriction Management (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] <command> \\[options\\]"
        puts ""
        puts "Commands:"
        puts "  list                          - List all restricted variables"
        puts "  status                        - Show current restriction status"
        puts "  validate                      - Validate current configuration for violations"
        puts "  check_file <filename>         - Check specific file for restrictions"
        puts "  bypass -reason <reason> -requester <name> -email <email>"
        puts "                                - Enable bypass with notification"
        puts "  clear_bypass                  - Clear bypass settings"
        puts "  help                          - Show this help"
        puts ""
        puts "Examples:"
        puts "  tclsh [info script] list"
        puts "  tclsh [info script] validate"
        puts "  tclsh [info script] bypass -reason \"Emergency fix\" -requester \"John Doe\" -email \"john@company.com\""
        puts ""
    }

    proc main {argc argv} {
        # Ensure global arrays are accessible
        if {![initialize_global_access]} {
            return 1
        }

        # Load restriction definitions
        if {![load_restrictions]} {
            handle_error "Failed to load restriction definitions"
            return 1
        }

        if {$argc == 0} {
            show_help
            return 1
        }

        set command [lindex $argv 0]

        switch -- $command {
            "help" - "--help" - "-h" {
                show_help
                return 0
            }
            "list" {
                if {[list_restrictions]} {
                    return 0
                } else {
                    return 1
                }
            }
            "status" {
                if {[show_bypass_status]} {
                    return 0
                } else {
                    return 1
                }
            }
            "validate" {
                if {[validate_restrictions]} {
                    return 0
                } else {
                    return 1
                }
            }
            "check_file" {
                if {$argc < 2} {
                    handle_error "check_file requires filename argument"
                    return 1
                }
                set filename [lindex $argv 1]
                if {[check_file $filename]} {
                    return 0
                } else {
                    return 1
                }
            }
            "bypass" {
                # Parse bypass arguments
                set reason ""
                set requester ""
                set email ""
                set approval ""

                for {set i 1} {$i < $argc} {incr i} {
                    set arg [lindex $argv $i]
                    switch -- $arg {
                        "-reason" {
                            incr i
                            if {$i < $argc} {
                                set reason [lindex $argv $i]
                            }
                        }
                        "-requester" {
                            incr i
                            if {$i < $argc} {
                                set requester [lindex $argv $i]
                            }
                        }
                        "-email" {
                            incr i
                            if {$i < $argc} {
                                set email [lindex $argv $i]
                            }
                        }
                        "-approval" {
                            incr i
                            if {$i < $argc} {
                                set approval [lindex $argv $i]
                            }
                        }
                    }
                }

                # Validate required arguments
                if {$reason eq "" || $requester eq "" || $email eq ""} {
                    handle_error "bypass requires -reason, -requester, and -email arguments"
                    return 1
                }

                if {[enable_bypass $reason $requester $email $approval]} {
                    return 0
                } else {
                    return 1
                }
            }
            "clear_bypass" {
                if {[clear_bypass]} {
                    return 0
                } else {
                    return 1
                }
            }
            default {
                handle_error "Unknown command: $command"
                show_help
                return 1
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

# Only run main if this script is executed directly (not sourced)
if {[info script] eq $argv0} {
    exit [::CBFlow::NodeManagement::RestrictionManager::main $argc $argv]
}