#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Configuration Validation Script (Refactored)
# Description: Validates user_config.tcl against predefined variables in flow configs
# Version: v1.0.0
# Namespace: ::CBFlow::Validation::ConfigValidator
# Usage: tclsh validate_config_refactored.tcl [user_config_file]
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
global project tech pnr synth signoff runtime tools output
global argc argv argv0

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Validation::ConfigValidator {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Validation tracking
    variable validation_errors {}
    variable validation_warnings {}
    variable undefined_variables {}
    variable valid_variable_count 0

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

    proc get_predefined_variables {} {
        # Define standard CBFlow configuration variables
        set predefined_vars [dict create]

        # Flow configuration variables
        dict set predefined_vars "flow(type)" "string"
        dict set predefined_vars "flow(design_name)" "string"
        dict set predefined_vars "flow(run_name)" "string"
        dict set predefined_vars "flow(log_level)" "string"
        dict set predefined_vars "flow(debug)" "boolean"

        # Project configuration variables
        dict set predefined_vars "project(phase)" "string"
        dict set predefined_vars "project(root)" "string"
        dict set predefined_vars "project(name)" "string"

        # Technology configuration variables
        dict set predefined_vars "tech(node)" "string"
        dict set predefined_vars "tech(vendor)" "string"
        dict set predefined_vars "tech(lib_path)" "string"
        dict set predefined_vars "tech(lef_files)" "list"
        dict set predefined_vars "tech(lib_files)" "list"

        # Tool configuration variables
        dict set predefined_vars "tools(synthesis)" "string"
        dict set predefined_vars "tools(pnr)" "string"
        dict set predefined_vars "tools(signoff)" "string"

        # Synthesis configuration variables
        dict set predefined_vars "synth(clock_period)" "number"
        dict set predefined_vars "synth(clock_name)" "string"
        dict set predefined_vars "synth(reset_name)" "string"
        dict set predefined_vars "synth(top_module)" "string"

        # PNR configuration variables
        dict set predefined_vars "pnr(utilization)" "number"
        dict set predefined_vars "pnr(core_width)" "number"
        dict set predefined_vars "pnr(core_height)" "number"
        dict set predefined_vars "pnr(power_rings)" "boolean"

        # Runtime configuration variables
        dict set predefined_vars "runtime(parallel_jobs)" "number"
        dict set predefined_vars "runtime(memory_limit)" "string"
        dict set predefined_vars "runtime(timeout)" "number"

        return $predefined_vars
    }

    proc validate_variable_type {var_name value expected_type} {
        switch -- $expected_type {
            "string" {
                # Any value is valid as string
                return true
            }
            "number" {
                # Check if value is numeric
                if {[string is double $value]} {
                    return true
                } else {
                    return false
                }
            }
            "boolean" {
                # Check if value is boolean
                if {$value in {true false 1 0 yes no on off}} {
                    return true
                } else {
                    return false
                }
            }
            "list" {
                # Check if value can be interpreted as a list
                if {[catch {llength $value}]} {
                    return false
                } else {
                    return true
                }
            }
            default {
                return true
            }
        }
    }

    proc add_validation_error {message} {
        variable validation_errors
        lappend validation_errors $message
        handle_error $message
    }

    proc add_validation_warning {message} {
        variable validation_warnings
        lappend validation_warnings $message
        handle_warning $message
    }

    proc validate_config_syntax {config_file} {
        handle_info "Validating configuration file syntax: $config_file"

        if {![file exists $config_file]} {
            add_validation_error "Configuration file not found: $config_file"
            return false
        }

        if {![file readable $config_file]} {
            add_validation_error "Configuration file not readable: $config_file"
            return false
        }

        # Test syntax by attempting to source it in a safe namespace
        if {[catch {
            namespace eval ::ConfigSyntaxTest {
                source $config_file
            }
            namespace delete ::ConfigSyntaxTest
        } error]} {
            add_validation_error "Configuration file syntax error: $error"
            return false
        }

        handle_info "✓ Configuration file syntax validation passed"
        return true
    }

    proc validate_config_variables {config_file} {
        variable valid_variable_count
        variable undefined_variables

        handle_info "Validating configuration variables: $config_file"

        # Get predefined variables
        set predefined_vars [get_predefined_variables]

        # Source the config file in a validation namespace
        namespace eval ::ConfigValidation {}

        if {[catch {
            namespace eval ::ConfigValidation {
                source $config_file
            }
        } error]} {
            add_validation_error "Failed to load configuration: $error"
            namespace delete ::ConfigValidation
            return false
        }

        # Check all defined variables
        set config_vars [info vars ::ConfigValidation::*]

        foreach config_var $config_vars {
            # Remove namespace prefix
            set var_name [string map {"::ConfigValidation::" ""} $config_var]

            # Skip internal TCL variables
            if {[string match "tcl*" $var_name] || [string match "auto*" $var_name]} {
                continue
            }

            set var_value [set $config_var]

            # Check if variable is predefined
            if {[dict exists $predefined_vars $var_name]} {
                set expected_type [dict get $predefined_vars $var_name]

                if {[validate_variable_type $var_name $var_value $expected_type]} {
                    handle_debug "✓ Valid variable: $var_name = $var_value (type: $expected_type)"
                    incr valid_variable_count
                } else {
                    add_validation_error "Invalid type for $var_name: expected $expected_type, got '$var_value'"
                }
            } else {
                lappend undefined_variables $var_name
                add_validation_warning "Undefined variable (not in predefined list): $var_name = $var_value"
            }
        }

        namespace delete ::ConfigValidation

        handle_info "Configuration variable validation completed"
        return true
    }

    proc validate_required_variables {} {
        # Check for essential variables
        set required_vars {"flow(type)" "flow(design_name)" "flow(run_name)"}
        set missing_required {}

        # Check if required variables exist in the global namespace
        foreach var $required_vars {
            if {![info exists $var]} {
                lappend missing_required $var
            }
        }

        if {[llength $missing_required] > 0} {
            add_validation_error "Missing required variables: [join $missing_required {, }]"
            return false
        }

        # Validate flow type
        global flow
        if {[info exists flow(type)]} {
            set valid_flows {SYNTH PNR FP LEC EMIR ECO CLP POPT FCFP}
            if {$flow(type) ni $valid_flows} {
                add_validation_error "Invalid flow type: $flow(type). Must be one of: [join $valid_flows {, }]"
                return false
            }
        }

        handle_info "✓ Required variable validation passed"
        return true
    }

    proc generate_validation_report {} {
        variable validation_errors
        variable validation_warnings
        variable undefined_variables
        variable valid_variable_count

        handle_info ""
        handle_info "═══════════════════════════════════════════════════════════════"
        handle_info "  Configuration Validation Report"
        handle_info "═══════════════════════════════════════════════════════════════"

        handle_info "✅ Valid variables: $valid_variable_count"

        if {[llength $validation_warnings] > 0} {
            handle_info "⚠️  Warnings: [llength $validation_warnings]"
            foreach warning $validation_warnings {
                handle_info "   $warning"
            }
        }

        if {[llength $validation_errors] > 0} {
            handle_info "❌ Errors: [llength $validation_errors]"
            foreach error $validation_errors {
                handle_info "   $error"
            }
        }

        if {[llength $undefined_variables] > 0} {
            handle_info ""
            handle_info "Undefined variables (not in predefined list):"
            foreach var $undefined_variables {
                handle_info "  - $var"
            }
        }

        handle_info ""

        if {[llength $validation_errors] == 0} {
            handle_info "🎉 Configuration validation PASSED"
            return true
        } else {
            handle_info "💥 Configuration validation FAILED"
            return false
        }
    }

    proc perform_full_validation {config_file} {
        variable validation_errors
        variable validation_warnings
        variable undefined_variables
        variable valid_variable_count

        # Reset validation state
        set validation_errors {}
        set validation_warnings {}
        set undefined_variables {}
        set valid_variable_count 0

        handle_info "Starting comprehensive configuration validation..."
        handle_info "Configuration file: $config_file"

        # Step 1: Validate syntax
        if {![validate_config_syntax $config_file]} {
            generate_validation_report
            return false
        }

        # Step 2: Source the configuration globally for required validation
        if {[catch {source $config_file} error]} {
            add_validation_error "Failed to source configuration globally: $error"
            generate_validation_report
            return false
        }

        # Step 3: Validate required variables
        if {![validate_required_variables]} {
            generate_validation_report
            return false
        }

        # Step 4: Validate variable types and definitions
        if {![validate_config_variables $config_file]} {
            generate_validation_report
            return false
        }

        # Step 5: Generate final report
        return [generate_validation_report]
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Configuration Validation (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] \\[user_config_file\\]"
        puts ""
        puts "Arguments:"
        puts "  user_config_file: User configuration file to validate (default: user_config.tcl)"
        puts ""
        puts "Description:"
        puts "  Validates user configuration against predefined CBFlow variables"
        puts "  Checks syntax, required variables, and variable types"
        puts ""
        puts "Validation checks:"
        puts "  • Configuration file syntax"
        puts "  • Required variables presence"
        puts "  • Variable type validation"
        puts "  • Flow type validation"
        puts ""
        puts "Examples:"
        puts "  tclsh validate_config_refactored.tcl"
        puts "  tclsh validate_config_refactored.tcl my_config.tcl"
        puts ""
    }

    proc main {argc argv} {
        # Ensure global arrays are accessible
        if {![initialize_global_access]} {
            return 1
        }

        if {$argc > 0 && ([lindex $argv 0] in {"help" "--help" "-h"})} {
            show_help
            return 0
        }

        # Determine config file to validate
        set config_file "user_config.tcl"
        if {$argc >= 1} {
            set config_file [lindex $argv 0]
        }

        # Perform validation
        if {[perform_full_validation $config_file]} {
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
    exit [::CBFlow::Validation::ConfigValidator::main $argc $argv]
}