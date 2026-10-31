#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Configuration Generation Script (Refactored)
# Description: Validates and generates consolidated configuration files
# Version: v1.0.0
# Namespace: ::CBFlow::Generation::ConfigGenerator
# Usage: tclsh generate_config_refactored.tcl [validate|template|help] [run_dir] [config_file]
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Script Initialization ──────────────────────────────────────────────────────┐
# Load error handling utilities using version-based paths
set script_dir [file dirname [file normalize [info script]]]

# Calculate paths based on known script structure
set flow_root [file dirname [file dirname [file dirname $script_dir]]]
set utilities_version "v1.0.0"
set error_utils_path "$flow_root/utils/utilities/$utilities_version/error_utils.tcl"

if {[file exists $error_utils_path]} {
    source $error_utils_path
} else {
    puts stderr "ERROR: Cannot find error_utils.tcl at $error_utils_path"
    exit 1
}

# Set up environment variables if not already set
if {![info exists ::env(FLOW_DIR)]} {
    set ::env(FLOW_DIR) $flow_root
}
if {![info exists ::env(UTILITIES_VERSION)]} {
    set ::env(UTILITIES_VERSION) $utilities_version
}

# ┌─ Global Scope Setup ─────────────────────────────────────────────────────────┐
# Ensure all required global variables are available AFTER initialization
global flow STAGE_TYPES DEPENDENCY_STAGES NODE_TYPE_DESCRIPTIONS
global project tech pnr synth signoff runtime tools output
global argc argv argv0

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Generation::ConfigGenerator {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # ┌─ Import Global Arrays ────────────────────────────────────────────────────┐
    # Ensure all global configuration arrays are available in this namespace
    proc initialize_global_access {} {
        global flow STAGE_TYPES DEPENDENCY_STAGES NODE_TYPE_DESCRIPTIONS
        global project tech pnr synth signoff runtime tools output

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
    # Use standardized error handling functions
    proc handle_error {message} {
        CBFLOW_ERROR $message
        return 0
    }

    proc handle_warning {message} {
        CBFLOW_WARNING $message
        return 1
    }

    proc handle_info {message} {
        CBFLOW_INFO $message
        return 1
    }

    proc handle_debug {message} {
        CBFLOW_DEBUG $message
        return 1
    }

    # ┌─ Configuration Validation Functions ──────────────────────────────────────┐

    proc validate_config_file {config_file} {
        handle_info "Validating configuration file: $config_file"

        if {![file exists $config_file]} {
            handle_error "Configuration file not found: $config_file"
            return false
        }

        if {![file readable $config_file]} {
            handle_error "Configuration file not readable: $config_file"
            return false
        }

        # Test syntax by attempting to source it in a safe namespace
        if {[catch {
            namespace eval ::ConfigTest [list source $config_file]
            namespace delete ::ConfigTest
        } error]} {
            handle_error "Configuration file syntax error: $error"
            return false
        }

        handle_info "✓ Configuration file validation passed"
        return true
    }

    proc get_available_config_variables {} {
        # Return dictionary of available configuration variables
        set vars [dict create]

        # Flow configuration variables
        dict set vars "flow(type)" "Flow type (SYNTH, PNR, FP, etc.)"
        dict set vars "flow(design_name)" "Design name"
        dict set vars "flow(run_name)" "Run identifier"
        dict set vars "flow(log_level)" "Logging level (debug, info, warning, error)"

        # Project configuration variables
        dict set vars "project(phase)" "Project phase (P0, P1, P2, etc.)"
        dict set vars "project(root)" "Project root directory"
        dict set vars "project(name)" "Project name"

        # Technology configuration variables
        dict set vars "tech(node)" "Technology node (16nm, 7nm, etc.)"
        dict set vars "tech(vendor)" "Technology vendor"
        dict set vars "tech(lib_path)" "Technology library path"

        # Tool configuration variables
        dict set vars "tools(synthesis)" "Synthesis tool name"
        dict set vars "tools(pnr)" "Place and route tool name"
        dict set vars "tools(signoff)" "Signoff tool name"

        return $vars
    }

    proc validate_user_config {config_file} {
        handle_info "Performing detailed validation of user configuration..."

        # Source the config file to check variables
        if {[catch {source $config_file} error]} {
            handle_error "Failed to source config file: $error"
            return false
        }

        set validation_passed true
        set available_vars [get_available_config_variables]

        # Check for required variables
        set required_vars {"flow(type)" "flow(design_name)" "flow(run_name)"}
        foreach var $required_vars {
            if {![info exists $var]} {
                handle_error "Required variable missing: $var"
                set validation_passed false
            }
        }

        # Validate flow type
        if {[info exists flow(type)]} {
            set valid_flows {SYNTH PNR FP LEC EMIR ECO CLP POPT FCFP}
            if {$flow(type) ni $valid_flows} {
                handle_error "Invalid flow type: $flow(type). Must be one of: [join $valid_flows {, }]"
                set validation_passed false
            }
        }

        if {$validation_passed} {
            handle_info "✓ User configuration validation passed"
        } else {
            handle_error "✗ User configuration validation failed"
        }

        return $validation_passed
    }

    # ┌─ Template Generation Functions ───────────────────────────────────────────┐

    proc generate_config_template {} {
        set lines {}

        lappend lines "#!/usr/bin/env tclsh"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# CBFlow User Configuration Template"
        lappend lines "# Generated: [clock format [clock seconds]]"
        lappend lines "# Description: Template showing all available configuration variables"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        # Get available variables
        set available_vars [get_available_config_variables]

        # Group variables by category
        set categories [dict create]
        dict for {var desc} $available_vars {
            if {[string match "flow(*" $var]} {
                dict lappend categories "Flow Configuration" [list $var $desc]
            } elseif {[string match "project(*" $var]} {
                dict lappend categories "Project Configuration" [list $var $desc]
            } elseif {[string match "tech(*" $var]} {
                dict lappend categories "Technology Configuration" [list $var $desc]
            } elseif {[string match "tools(*" $var]} {
                dict lappend categories "Tool Configuration" [list $var $desc]
            } else {
                dict lappend categories "Other Configuration" [list $var $desc]
            }
        }

        # Generate template content
        dict for {category var_list} $categories {
            lappend lines "# ┌─ $category ──────────────────────────────────────────────────────┐"
            lappend lines ""

            foreach var_info $var_list {
                lassign $var_info var desc
                lappend lines "# $desc"
                lappend lines "set $var \"CHANGE_ME\""
                lappend lines ""
            }
        }

        # Add example values
        lappend lines "# ┌─ Example Configuration ──────────────────────────────────────────────────────┐"
        lappend lines ""
        lappend lines "# Example for SYNTH flow:"
        lappend lines "# set flow(type) \"SYNTH\""
        lappend lines "# set flow(design_name) \"my_design\""
        lappend lines "# set flow(run_name) \"test_001\""
        lappend lines "# set project(phase) \"P0\""
        lappend lines ""

        return [join $lines "\n"]
    }

    # ┌─ Consolidated Config Generation Functions ────────────────────────────────┐

    proc generate_consolidated_config {run_dir config_file} {
        handle_info "Generating consolidated configuration for run: $run_dir"

        # Validate inputs
        if {![file isdirectory $run_dir]} {
            handle_error "Run directory not found: $run_dir"
            return false
        }

        if {![validate_config_file $config_file]} {
            return false
        }

        # Perform detailed validation
        if {![validate_user_config $config_file]} {
            return false
        }

        # Create consolidated config
        set lines {}

        lappend lines "#!/usr/bin/env tclsh"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# CBFlow Consolidated Configuration"
        lappend lines "# Generated: [clock format [clock seconds]]"
        lappend lines "# Run Directory: $run_dir"
        lappend lines "# Source Config: $config_file"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        # Include original user config
        lappend lines "# ┌─ User Configuration ─────────────────────────────────────────────────────────┐"
        lappend lines "# Source: $config_file"
        lappend lines ""

        # Read and include user config content
        if {[catch {
            set fp [open $config_file r]
            set user_content [read $fp]
            close $fp

            foreach line [split $user_content "\n"] {
                lappend lines $line
            }
        }]} {
            handle_error "Failed to read user config file"
            return false
        }

        lappend lines ""
        lappend lines "# ┌─ Runtime Environment ────────────────────────────────────────────────────────┐"
        lappend lines ""
        lappend lines "set runtime(run_dir) \"$run_dir\""
        lappend lines "set runtime(config_generated) \"[clock format [clock seconds]]\""
        lappend lines "set runtime(config_source) \"$config_file\""
        lappend lines ""

        # Write consolidated config
        set output_file [file join $run_dir "consolidated_config.tcl"]
        if {[catch {
            set fp [open $output_file w]
            puts $fp [join $lines "\n"]
            close $fp
        }]} {
            handle_error "Failed to write consolidated config file"
            return false
        }

        handle_info "✓ Consolidated configuration generated: $output_file"
        return true
    }

    # ┌─ Command Functions ───────────────────────────────────────────────────────┐

    proc cmd_template {} {
        handle_info "Generating configuration template..."

        set template_content [generate_config_template]
        set output_file "user_config_template.tcl"

        if {[catch {
            set fp [open $output_file w]
            puts $fp $template_content
            close $fp
        }]} {
            handle_error "Failed to write template file"
            return false
        }

        handle_info "✓ Configuration template generated: $output_file"
        handle_info ""
        handle_info "Next steps:"
        handle_info "1. Copy $output_file to user_config.tcl"
        handle_info "2. Edit user_config.tcl with your specific values"
        handle_info "3. Use 'generate_config_refactored.tcl validate user_config.tcl' to validate"

        return true
    }

    proc cmd_validate {config_file} {
        if {$config_file eq ""} {
            handle_error "Configuration file not specified"
            return false
        }

        return [validate_user_config $config_file]
    }

    proc cmd_generate {run_dir config_file} {
        if {$run_dir eq "" || $config_file eq ""} {
            handle_error "Both run directory and config file must be specified"
            return false
        }

        return [generate_consolidated_config $run_dir $config_file]
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        variable version
        puts "CBFlow Configuration Generation (Refactored v$version)"
        puts "Usage: tclsh \[info script\] <command> \[arguments...\]"
        puts ""
        puts "Commands:"
        puts "  template                     Generate user_config.tcl template"
        puts "  validate <config_file>       Validate configuration file"
        puts "  generate <run_dir> <config>  Generate consolidated configuration"
        puts "  help                         Show this help message"
        puts ""
        puts "Examples:"
        puts "  tclsh generate_config_refactored.tcl template"
        puts "  tclsh generate_config_refactored.tcl validate user_config.tcl"
        puts "  tclsh generate_config_refactored.tcl generate ./run_dir user_config.tcl"
        puts ""
        puts "Description:"
        puts "  Validates and generates consolidated configuration files for CBFlow runs"
        puts ""
    }

    proc main {argc argv} {
        # Ensure global arrays are accessible
        if {![initialize_global_access]} {
            return 1
        }

        if {$argc == 0} {
            show_help
            return 1
        }

        set command [lindex $argv 0]

        switch -- $command {
            "template" {
                if {[cmd_template]} {
                    return 0
                } else {
                    return 1
                }
            }
            "validate" {
                set config_file [lindex $argv 1]
                if {[cmd_validate $config_file]} {
                    return 0
                } else {
                    return 1
                }
            }
            "generate" {
                set run_dir [lindex $argv 1]
                set config_file [lindex $argv 2]
                if {[cmd_generate $run_dir $config_file]} {
                    return 0
                } else {
                    return 1
                }
            }
            "help" - "--help" - "-h" {
                show_help
                return 0
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
    exit [::CBFlow::Generation::ConfigGenerator::main $argc $argv]
}