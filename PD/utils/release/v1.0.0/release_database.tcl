#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Database Release Script (Refactored)
# Description: Release database to project repository
# Version: v1.0.0
# Namespace: ::CBFlow::Release::DatabaseReleaser
# Usage: tclsh release_database_refactored.tcl <flow_type> <run_dir>
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
namespace eval ::CBFlow::Release::DatabaseReleaser {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Release configuration
    variable DELIVERABLES {
        "results/database"
        "results/netlist"
        "results/def"
        "results/gds"
        "results/spef"
        "reports"
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

    # ┌─ Release Functions ───────────────────────────────────────────────────────┐

    proc validate_run_directory {run_dir} {
        if {![file exists $run_dir]} {
            handle_error "Run directory does not exist: $run_dir"
            return false
        }

        # Check for configuration file
        set config_files [list \
            "$run_dir/setup/user_config.tcl" \
            "$run_dir/.config.tcl" \
        ]

        foreach config_file $config_files {
            if {[file exists $config_file]} {
                handle_debug "Found configuration file: $config_file"
                return true
            }
        }

        handle_error "No configuration file found in $run_dir"
        return false
    }

    proc copy_deliverables {run_dir release_dir} {
        variable DELIVERABLES

        set copied_count 0
        set missing_count 0

        foreach deliverable $DELIVERABLES {
            set source_path "$run_dir/$deliverable"

            if {[file exists $source_path]} {
                set target_path "$release_dir/$deliverable"

                # Create parent directory if needed
                set parent_dir [file dirname $target_path]
                if {![file exists $parent_dir]} {
                    file mkdir $parent_dir
                }

                # Copy file or directory
                if {[catch {file copy -force $source_path $target_path} error]} {
                    handle_error "Failed to copy $deliverable: $error"
                    return false
                } else {
                    handle_info "Released: $deliverable"
                    incr copied_count
                }
            } else {
                handle_warning "Deliverable not found: $deliverable"
                incr missing_count
            }
        }

        handle_info "Release summary: $copied_count files copied, $missing_count missing"
        return true
    }

    proc create_release_manifest {flow_type run_dir release_dir} {
        variable DELIVERABLES

        set manifest_file "$release_dir/release_manifest.txt"

        if {[catch {open $manifest_file "w"} fp]} {
            handle_error "Failed to create release manifest: $manifest_file"
            return false
        }

        puts $fp "CBFlow Database Release Manifest"
        puts $fp "================================="
        puts $fp "Flow Type: $flow_type"
        puts $fp "Run Directory: $run_dir"
        puts $fp "Release Date: [clock format [clock seconds]]"
        puts $fp "Release Directory: $release_dir"
        puts $fp ""
        puts $fp "Released Files:"

        # List all released files
        foreach deliverable $DELIVERABLES {
            set target_path "$release_dir/$deliverable"
            if {[file exists $target_path]} {
                puts $fp "  ✓ $deliverable"

                # Add file size information for files
                if {[file isfile $target_path]} {
                    set size [file size $target_path]
                    puts $fp "    Size: $size bytes"
                } elseif {[file isdirectory $target_path]} {
                    # Count files in directory
                    set file_count [llength [glob -nocomplain "$target_path/*"]]
                    puts $fp "    Files: $file_count items"
                }
            } else {
                puts $fp "  ✗ $deliverable (missing)"
            }
        }

        puts $fp ""
        puts $fp "Generated by: CBFlow Database Releaser v[set [namespace current]::version]"

        close $fp

        handle_info "Release manifest created: $manifest_file"
        return true
    }

    proc perform_release {flow_type run_dir} {
        handle_info "Starting database release for $flow_type from $run_dir"

        # Validate inputs
        if {![validate_run_directory $run_dir]} {
            return false
        }

        # Create release directory structure
        set release_dir "$run_dir/release"
        if {![file exists $release_dir]} {
            if {[catch {file mkdir $release_dir} error]} {
                handle_error "Failed to create release directory: $error"
                return false
            }
        }

        handle_info "Release directory: $release_dir"

        # Copy deliverables
        if {![copy_deliverables $run_dir $release_dir]} {
            handle_error "Failed to copy deliverables"
            return false
        }

        # Create release manifest
        if {![create_release_manifest $flow_type $run_dir $release_dir]} {
            handle_error "Failed to create release manifest"
            return false
        }

        handle_info "Database release completed successfully"
        handle_info "Release location: $release_dir"

        return true
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Database Release (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] <flow_type> <run_dir>"
        puts ""
        puts "Arguments:"
        puts "  flow_type: Flow type (SYNTH, PNR, etc.)"
        puts "  run_dir:   Run directory containing deliverables"
        puts ""
        puts "Description:"
        puts "  Releases database and key deliverables to project repository"
        puts ""
        puts "Released deliverables:"
        variable DELIVERABLES
        foreach deliverable $DELIVERABLES {
            puts "  - $deliverable"
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

        if {$argc < 2} {
            handle_error "Invalid number of arguments"
            show_help
            return 1
        }

        set flow_type [lindex $argv 0]
        set run_dir [lindex $argv 1]

        # Validate flow type
        if {$flow_type ni $valid_flows} {
            handle_error "Invalid flow_type '$flow_type'. Must be one of: [join $valid_flows {, }]"
            return 1
        }

        # Perform the release
        if {[perform_release $flow_type $run_dir]} {
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
    exit [::CBFlow::Release::DatabaseReleaser::main $argc $argv]
}