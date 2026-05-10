#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Auto Release Update Script (Refactored)
# Description: Auto-update release configuration by discovering versions
# Version: v1.0.0
# Namespace: ::CBFlow::Release::AutoUpdater
# Usage: tclsh auto_release_update_refactored.tcl [project_root] [release_version]
# ═══════════════════════════════════════════════════════════════════════════════

#===============================================================================
# PORTABLE PATH RESOLUTION
#===============================================================================
# Detect project root dynamically before initialization
set script_dir_init [file dirname [file normalize [info script]]]
set resolver_path_init [file join $script_dir_init "../../.." "utils" "utilities" "v2.0.0" "path_resolver.tcl"]

if {[file exists $resolver_path_init]} {
    source $resolver_path_init
    set DYNAMIC_PROJECT_ROOT [::PathResolver::get_project_root]
} else {
    # Fallback: Check environment variable
    if {[info exists ::env(CBFLOW_PROJECT_ROOT)]} {
        set DYNAMIC_PROJECT_ROOT $::env(CBFLOW_PROJECT_ROOT)
    } else {
        # Last resort: Try git command
        if {[catch {exec git rev-parse --show-toplevel} git_root] == 0} {
            set DYNAMIC_PROJECT_ROOT [file join [string trim $git_root] "CBFlow" "PD"]
        } else {
            # Absolute fallback: Calculate from script location
            set DYNAMIC_PROJECT_ROOT [file normalize [file join $script_dir_init "../../.."]]
        }
    }
}

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
namespace eval ::CBFlow::Release::AutoUpdater {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Default configuration (dynamically resolved, portable)
    variable DEFAULT_PROJECT_ROOT $::DYNAMIC_PROJECT_ROOT
    variable DEFAULT_RELEASE_VERSION "v1.0.1"

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

    # ┌─ Version Discovery Functions ─────────────────────────────────────────────┐

    proc discover_script_versions {project_root} {
        set script_versions [dict create]
        set scripts_root [file join $project_root "core" "scripts"]

        if {![file exists $scripts_root]} {
            handle_warning "Scripts directory not found: $scripts_root"
            return $script_versions
        }

        handle_debug "Discovering script versions in: $scripts_root"

        foreach script_dir [glob -nocomplain -type d "$scripts_root/*"] {
            set script_name [file tail $script_dir]

            # Skip common and workspace directories
            if {$script_name in {"common" "workspace"}} continue

            set versions [glob -nocomplain -type d "$script_dir/v*"]
            if {[llength $versions] > 0} {
                set version_list [lmap v $versions {file tail $v}]
                set latest_version [lindex [lsort -version $version_list] end]
                dict set script_versions $script_name $latest_version
                handle_debug "  📁 Script: $script_name -> $latest_version"
            }
        }

        return $script_versions
    }

    proc copy_release_config {project_root release_version} {
        # Copy existing release config as template
        set source_config [file join $project_root "core" "config" "flow_release" "v1.0.0" "flow_release_config.tcl"]
        set target_dir [file join $project_root "core" "config" "flow_release" $release_version]
        set target_config [file join $target_dir "flow_release_config.tcl"]

        if {![file exists $source_config]} {
            handle_error "Source release config not found: $source_config"
            return false
        }

        # Create target directory
        if {[catch {file mkdir $target_dir} error]} {
            handle_error "Failed to create target directory: $error"
            return false
        }

        # Copy the file
        if {[catch {file copy $source_config $target_config} error]} {
            handle_error "Failed to copy release config: $error"
            return false
        }

        handle_info "Created new release config at: $target_config"
        return $target_config
    }

    proc perform_auto_update {project_root release_version} {
        handle_info "Auto-updating release configuration $release_version..."

        # Copy release config template
        set target_config [copy_release_config $project_root $release_version]
        if {!$target_config} {
            return false
        }

        # Discover versions
        handle_info "Running auto-discovery and update..."
        set discovered_scripts [discover_script_versions $project_root]

        # Display results
        handle_info "Discovered versions:"
        if {[dict size $discovered_scripts] > 0} {
            handle_info "  📁 Scripts:"
            dict for {script version} $discovered_scripts {
                handle_info "    $script: $version"
            }
        } else {
            handle_warning "    No script versions discovered"
        }

        handle_info ""
        handle_info "Release $release_version ready!"
        handle_info "Config location: $target_config"

        return true
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Auto Release Update (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] \\[project_root\\] \\[release_version\\]"
        puts ""
        puts "Arguments:"
        variable DEFAULT_PROJECT_ROOT
        variable DEFAULT_RELEASE_VERSION
        puts "  project_root:    Project root directory (default: $DEFAULT_PROJECT_ROOT)"
        puts "  release_version: Target release version (default: $DEFAULT_RELEASE_VERSION)"
        puts ""
        puts "Description:"
        puts "  Auto-discovers versioned directories and creates new release configuration"
        puts ""
    }

    proc main {argc argv} {
        variable DEFAULT_PROJECT_ROOT
        variable DEFAULT_RELEASE_VERSION

        if {$argc > 0 && ([lindex $argv 0] in {"help" "--help" "-h"})} {
            show_help
            return 0
        }

        # Parse arguments
        set project_root $DEFAULT_PROJECT_ROOT
        set release_version $DEFAULT_RELEASE_VERSION

        if {$argc >= 1} {
            set project_root [lindex $argv 0]
        }

        if {$argc >= 2} {
            set release_version [lindex $argv 1]
        }

        # Validate project root
        if {![file exists $project_root]} {
            handle_error "Project root directory does not exist: $project_root"
            return 1
        }

        # Perform the auto-update
        if {[perform_auto_update $project_root $release_version]} {
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
    exit [::CBFlow::Release::AutoUpdater::main $argc $argv]
}