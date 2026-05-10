#!/usr/bin/env tclsh
# CBFlow Release Configuration Auto-Update Script
# Automatically discovers all versioned directories and updates release configuration

# Usage: tclsh update_release_config.tcl [project_root] [release_version]

#===============================================================================
# PORTABLE PATH RESOLUTION
#===============================================================================
# Source path resolver for portable path detection
set script_dir_for_resolver [file dirname [file normalize [info script]]]
# Navigate from utils/release/v1.0.0 -> core (3 levels up)
set resolver_path [file join $script_dir_for_resolver "../../.." "utils" "utilities" "v2.0.0" "path_resolver.tcl"]

if {[file exists $resolver_path]} {
    source $resolver_path
    set DEFAULT_PROJECT_ROOT [::PathResolver::get_project_root]
} else {
    # Fallback: Check environment variable
    if {[info exists ::env(CBFLOW_PROJECT_ROOT)]} {
        set DEFAULT_PROJECT_ROOT $::env(CBFLOW_PROJECT_ROOT)
    } else {
        # Last resort: Try git command
        if {[catch {exec git rev-parse --show-toplevel} git_root] == 0} {
            set DEFAULT_PROJECT_ROOT [file join [string trim $git_root] "CBFlow" "PD"]
        } else {
            # Absolute fallback: Calculate from script location
            set DEFAULT_PROJECT_ROOT [file normalize [file join $script_dir_for_resolver "../../.."]]
        }
    }
}

#===============================================================================
# CONFIGURATION
#===============================================================================

# Default values
set DEFAULT_RELEASE_VERSION "v1.0.0"

# Parse command line arguments
if {$argc >= 1} {
    set project_root [lindex $argv 0]
} else {
    set project_root $DEFAULT_PROJECT_ROOT
}

if {$argc >= 2} {
    set release_version [lindex $argv 1]
} else {
    set release_version $DEFAULT_RELEASE_VERSION
}

#===============================================================================
# VERSION DISCOVERY FUNCTIONS
#===============================================================================

proc discover_all_versions {project_root} {
    set discovered [dict create]
    set core_root [file join $project_root "core"]

    puts "🔍 Discovering all versioned directories in $core_root..."

    # Discover script versions
    set scripts_root [file join $core_root "scripts"]
    if {[file exists $scripts_root]} {
        set script_versions [dict create]
        foreach script_dir [glob -nocomplain -type d "$scripts_root/*"] {
            set script_name [file tail $script_dir]
            set versions [glob -nocomplain -type d "$script_dir/v*"]
            if {[llength $versions] > 0} {
                set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                dict set script_versions $script_name $latest_version
                puts "  📁 Script: $script_name -> $latest_version"
            }
        }
        dict set discovered script_versions $script_versions
    }

    # Discover config versions
    set config_root [file join $core_root "config"]
    if {[file exists $config_root]} {
        set config_versions [dict create]

        # Flow configs (flow, version, flow_release)
        foreach config_name {flow version flow_release} {
            set config_dir [file join $config_root $config_name]
            if {[file exists $config_dir]} {
                set versions [glob -nocomplain -type d "$config_dir/v*"]
                if {[llength $versions] > 0} {
                    set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                    dict set config_versions $config_name $latest_version
                    puts "  📁 Config: $config_name -> $latest_version"
                }
            }
        }
        dict set discovered config_versions $config_versions

        # Project configs
        set project_versions [dict create]
        set project_dir [file join $config_root "project"]
        if {[file exists $project_dir]} {
            foreach proj [glob -nocomplain -type d "$project_dir/*"] {
                set proj_name [file tail $proj]
                set versions [glob -nocomplain -type d "$proj/v*"]
                if {[llength $versions] > 0} {
                    set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                    dict set project_versions $proj_name $latest_version
                    puts "  📁 Project: $proj_name -> $latest_version"
                }
            }
        }
        dict set discovered project_versions $project_versions

        # Technology configs
        set technology_versions [dict create]
        set tech_dir [file join $config_root "technology"]
        if {[file exists $tech_dir]} {
            foreach tech [glob -nocomplain -type d "$tech_dir/*"] {
                set tech_name [file tail $tech]
                set versions [glob -nocomplain -type d "$tech/v*"]
                if {[llength $versions] > 0} {
                    set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                    dict set technology_versions $tech_name $latest_version
                    puts "  📁 Technology: $tech_name -> $latest_version"
                }
            }
        }
        dict set discovered technology_versions $technology_versions

        # EDA configs
        set eda_versions [dict create]
        set eda_dir [file join $config_root "eda"]
        if {[file exists $eda_dir]} {
            foreach flow [glob -nocomplain -type d "$eda_dir/*"] {
                set flow_name [file tail $flow]
                foreach vendor [glob -nocomplain -type d "$flow/*"] {
                    set vendor_name [file tail $vendor]
                    foreach tool [glob -nocomplain -type d "$vendor/*"] {
                        set tool_name [file tail $tool]
                        set versions [glob -nocomplain -type d "$tool/v*"]
                        if {[llength $versions] > 0} {
                            set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                            set eda_key "${flow_name}_${vendor_name}_${tool_name}"
                            dict set eda_versions $eda_key $latest_version
                            puts "  📁 EDA Config: $eda_key -> $latest_version"
                        }
                    }
                }
            }
        }
        dict set discovered eda_versions $eda_versions
    }

    # Discover command versions
    set cmds_root [file join $core_root "cmds"]
    if {[file exists $cmds_root]} {
        set command_versions [dict create]
        foreach flow [glob -nocomplain -type d "$cmds_root/*"] {
            set flow_name [file tail $flow]
            foreach vendor [glob -nocomplain -type d "$flow/*"] {
                set vendor_name [file tail $vendor]
                foreach tool [glob -nocomplain -type d "$vendor/*"] {
                    set tool_name [file tail $tool]
                    set versions [glob -nocomplain -type d "$tool/v*"]
                    if {[llength $versions] > 0} {
                        set latest_version [lindex [lsort [lmap v $versions {file tail $v}]] end]
                        set cmd_key "${flow_name}_${vendor_name}_${tool_name}"
                        dict set command_versions $cmd_key $latest_version
                        puts "  📁 Command: $cmd_key -> $latest_version"
                    }
                }
            }
        }
        dict set discovered command_versions $command_versions
    }

    return $discovered
}

#===============================================================================
# RELEASE CONFIG GENERATION
#===============================================================================

proc generate_release_config {discovered release_version} {
    set timestamp [clock format [clock seconds]]

    set config "# Flow Release Configuration $release_version\n"
    append config "# Auto-generated on $timestamp\n"
    append config "# Defines all component versions for this flow release\n"
    append config "# All config scripts, projects, and technology versions included in this release\n\n"

    append config "#===============================================================================\n"
    append config "# FLOW RELEASE INFORMATION\n"
    append config "#===============================================================================\n\n"

    append config "# Release metadata\n"
    append config "array set release_info \\{\n"
    append config "    version \"$release_version\"\n"
    append config "    name \"Flow Management System Release $release_version\"\n"
    append config "    description \"Auto-generated release with complete version discovery\"\n"
    append config "    release_date \"[clock format [clock seconds] -format %Y-%m-%d]\"\n"
    append config "    status \"stable\"\n"
    append config "    compatibility \"v1.x\"\n"
    append config "}\n\n"

    # Generate config versions
    append config "#===============================================================================\n"
    append config "# CONFIG VERSIONS - All configuration script versions for this release\n"
    append config "#===============================================================================\n\n"
    append config "# Flow configuration versions\n"
    append config "array set config_versions \\{\n"
    if {[dict exists $discovered config_versions]} {
        dict for {config version} [dict get $discovered config_versions] {
            append config "    $config \"$version\"\n"
        }
    }
    append config "\\}\n\n"

    # Generate project versions
    append config "#===============================================================================\n"
    append config "# PROJECT VERSIONS - Supported project configurations in this release\n"
    append config "#===============================================================================\n\n"
    append config "# Project configuration versions\n"
    append config "array set project_versions {\n"
    if {[dict exists $discovered project_versions]} {
        dict for {project version} [dict get $discovered project_versions] {
            append config "    $project \"$version\"\n"
        }
    }
    append config "}\n\n"

    # Generate technology versions
    append config "#===============================================================================\n"
    append config "# TECHNOLOGY VERSIONS - Technology node configurations in this release\n"
    append config "#===============================================================================\n\n"
    append config "# Technology configuration versions\n"
    append config "array set technology_versions {\n"
    if {[dict exists $discovered technology_versions]} {
        dict for {tech version} [dict get $discovered technology_versions] {
            append config "    $tech \"$version\"\n"
        }
    }
    append config "}\n\n"

    # Generate script versions
    append config "#===============================================================================\n"
    append config "# SCRIPT VERSIONS - Flow utility script versions\n"
    append config "#===============================================================================\n\n"
    append config "# Script versions included in this release\n"
    append config "array set script_versions {\n"
    if {[dict exists $discovered script_versions]} {
        dict for {script version} [dict get $discovered script_versions] {
            append config "    $script \"$version\"\n"
        }
    }
    append config "}\n\n"

    # Generate EDA versions
    append config "#===============================================================================\n"
    append config "# EDA TOOL VERSIONS - EDA tool configurations in this release\n"
    append config "#===============================================================================\n\n"
    append config "# EDA tool configuration versions\n"
    append config "array set eda_versions {\n"
    if {[dict exists $discovered eda_versions]} {
        dict for {eda version} [dict get $discovered eda_versions] {
            append config "    $eda \"$version\"\n"
        }
    }
    append config "}\n\n"

    # Generate command versions
    append config "#===============================================================================\n"
    append config "# COMMAND VERSIONS - Flow command script versions\n"
    append config "#===============================================================================\n\n"
    append config "# Command script versions by flow type\n"
    append config "array set command_versions {\n"
    if {[dict exists $discovered command_versions]} {
        dict for {cmd version} [dict get $discovered command_versions] {
            append config "    $cmd \"$version\"\n"
        }
    }
    append config "}\n\n"

    # Add tool versions (static for now)
    append config "#===============================================================================\n"
    append config "# TOOL VERSIONS - External tool compatibility\n"
    append config "#===============================================================================\n\n"
    append config "# External tool versions validated for this release\n"
    append config "array set tool_versions {\n"
    append config "    tcl_version \"8.6\"\n"
    append config "    make_version \"4.0\"\n"
    append config "    git_version \"2.0\"\n"
    append config "    shell_version \"bash-5.0\"\n"
    append config "}\n\n"

    # Add utility functions (basic set)
    append config "#===============================================================================\n"
    append config "# RELEASE UTILITY FUNCTIONS\n"
    append config "#===============================================================================\n\n"

    append config "# Get release information\n"
    append config "proc get_release_info {key} {\n"
    append config "    global release_info\n"
    append config "    if {\[info exists release_info(\$key)\]} {\n"
    append config "        return \$release_info(\$key)\n"
    append config "    }\n"
    append config "    return \"\"\n"
    append config "}\n\n"

    append config "# Auto-generated release configuration\n"
    append config "puts \"✅ Auto-generated Flow Release Config loaded: \[get_release_info version\]\"\n"
    append config "puts \"   Auto-discovered and configured all versioned directories\"\n"

    return $config
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

puts "🚀 CBFlow Release Configuration Auto-Update"
puts "==========================================="
puts ""
puts "Project Root: $project_root"
puts "Release Version: $release_version"
puts ""

# Discover all versions
set discovered [discover_all_versions $project_root]

# Generate new release config
puts ""
puts "📝 Generating release configuration..."
set config_content [generate_release_config $discovered $release_version]

# Write to new release config file
set release_config_dir [file join $project_root "core" "config" "flow_release" $release_version]
file mkdir $release_config_dir

set output_file [file join $release_config_dir "flow_release_config.tcl"]

# Create backup if file exists
if {[file exists $output_file]} {
    set backup_file "${output_file}.backup.[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
    file copy $output_file $backup_file
    puts "📁 Backup created: $backup_file"
}

# Write new config
set fp [open $output_file w]
puts $fp $config_content
close $fp

puts "✅ Release configuration written to: $output_file"
puts ""
puts "🔧 To use this new release configuration:"
puts "   1. Update environment variables to point to release $release_version"
puts "   2. Re-run 'make init' to regenerate environment with new versions"
puts ""

# Validate the new config by sourcing it
puts "🧪 Validating generated configuration..."
if {[catch {source $output_file} err]} {
    puts "❌ Validation failed: $err"
    exit 1
} else {
    puts "✅ Configuration validation successful"
}

puts ""
puts "🎉 Release configuration update completed successfully!"