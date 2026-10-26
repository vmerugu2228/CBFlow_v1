#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Initialization Utilities (Refactored)
# Description: Contains all initialization-related procedures for CBFlow
# Version: v1.0.0
# Namespace: ::CBFlow::Utilities::InitUtils
# Usage: source init_utils_refactored.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Utilities::InitUtils {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable version "v1.0.0"
    variable debug_mode false

    # ┌─ Flow Release Configuration Functions ────────────────────────────────────┐

    proc load_flow_release_config {project_root release_version} {
        set release_config_path [file join $project_root "config" "flow_release" $release_version "flow_release_config.tcl"]

        if {[file exists $release_config_path]} {
            if {[catch {source $release_config_path} error]} {
                puts "❌ ERROR: Failed to load flow release config: $error"
                return false
            }
            puts "✅ Loaded flow release config: $release_version"
            return true
        } else {
            puts "⚠️  WARNING: Flow release config not found: $release_config_path"
            puts "         Using default version settings"
            return false
        }
    }

    proc get_available_releases {project_root} {
        set release_dir [file join $project_root "config" "flow_release"]

        if {![file exists $release_dir]} {
            return {}
        }

        set releases {}
        foreach dir [glob -nocomplain -type d "$release_dir/v*"] {
            lappend releases [file tail $dir]
        }

        return [lsort -version $releases]
    }

    proc get_latest_release {project_root} {
        set releases [get_available_releases $project_root]

        if {[llength $releases] > 0} {
            return [lindex $releases end]
        } else {
            return "v1.0.0"
        }
    }

    # ┌─ Path Generation Functions ───────────────────────────────────────────────┐

    proc get_project_root {workarea_path} {
        return [file dirname $workarea_path]
    }

    proc get_flow_directory {project_root} {
        return [file join $project_root "core"]
    }

    proc get_config_directory {project_root} {
        return [file join $project_root "core" "config"]
    }

    proc get_scripts_directory {project_root} {
        # SCRIPTS_ROOT points to utils directory (legacy name kept for compatibility)
        return [file join $project_root "core" "utils"]
    }

    proc generate_flow_paths {workarea_path {release_version ""}} {
        global project technology flow_settings

        set project_root [get_project_root $workarea_path]

        # Use latest release if not specified
        if {$release_version eq ""} {
            set release_version [get_latest_release $project_root]
        }

        # Generate core paths
        set paths [dict create]
        dict set paths "project_root" $project_root
        dict set paths "workarea" $workarea_path
        dict set paths "flow_dir" [get_flow_directory $project_root]
        dict set paths "config_dir" [get_config_directory $project_root]
        dict set paths "scripts_dir" [get_scripts_directory $project_root]

        # Generate versioned paths
        dict set paths "flow_config" [file join [dict get $paths "config_dir"] "flow" $release_version]
        dict set paths "project_config" [file join [dict get $paths "config_dir"] "project" $release_version]
        dict set paths "tech_config" [file join [dict get $paths "config_dir"] "technology" $release_version]

        # Generate script paths
        dict set paths "node_scripts" [file join [dict get $paths "scripts_dir"] "node_management" $release_version]
        dict set paths "utils_scripts" [file join [dict get $paths "scripts_dir"] "utilities" $release_version]
        dict set paths "generation_scripts" [file join [dict get $paths "scripts_dir"] "generation" $release_version]
        dict set paths "validation_scripts" [file join [dict get $paths "scripts_dir"] "validation" $release_version]

        return $paths
    }

    # ┌─ Environment Setup Functions ─────────────────────────────────────────────┐

    proc setup_environment_variables {paths} {
        global env

        # Set core environment variables
        set env(CBFLOW_PROJECT_ROOT) [dict get $paths "project_root"]
        set env(CBFLOW_FLOW_DIR) [dict get $paths "flow_dir"]
        set env(CBFLOW_CONFIG_DIR) [dict get $paths "config_dir"]
        set env(CBFLOW_SCRIPTS_DIR) [dict get $paths "scripts_dir"]

        # Set versioned paths
        set env(CBFLOW_FLOW_CONFIG_DIR) [dict get $paths "flow_config"]
        set env(CBFLOW_PROJECT_CONFIG_DIR) [dict get $paths "project_config"]
        set env(CBFLOW_TECH_CONFIG_DIR) [dict get $paths "tech_config"]

        # Set script paths
        set env(CBFLOW_NODE_SCRIPTS) [dict get $paths "node_scripts"]
        set env(CBFLOW_UTILS_SCRIPTS) [dict get $paths "utils_scripts"]
        set env(CBFLOW_GEN_SCRIPTS) [dict get $paths "generation_scripts"]
        set env(CBFLOW_VAL_SCRIPTS) [dict get $paths "validation_scripts"]

        puts "✅ Environment variables configured"
        return true
    }

    proc validate_paths {paths} {
        set validation_errors {}

        # Check critical paths
        set critical_paths {"project_root" "flow_dir" "config_dir" "scripts_dir"}

        foreach path_key $critical_paths {
            if {![dict exists $paths $path_key]} {
                lappend validation_errors "Missing path configuration: $path_key"
                continue
            }

            set path_value [dict get $paths $path_key]
            if {![file exists $path_value]} {
                lappend validation_errors "Path does not exist: $path_key = $path_value"
            } elseif {![file isdirectory $path_value]} {
                lappend validation_errors "Path is not a directory: $path_key = $path_value"
            }
        }

        if {[llength $validation_errors] > 0} {
            puts "❌ Path validation failed:"
            foreach error $validation_errors {
                puts "   $error"
            }
            return false
        }

        puts "✅ Path validation passed"
        return true
    }

    # ┌─ Configuration Loading Functions ─────────────────────────────────────────┐

    proc load_base_configuration {paths} {
        # Load core flow configuration
        set flow_config [file join [dict get $paths "flow_config"] "flow_config.tcl"]

        if {[file exists $flow_config]} {
            if {[catch {source $flow_config} error]} {
                puts "❌ ERROR: Failed to load flow config: $error"
                return false
            }
            puts "✅ Loaded flow configuration"
        } else {
            puts "⚠️  WARNING: Flow config not found: $flow_config"
        }

        return true
    }

    proc load_project_configuration {paths project_name} {
        set project_config [file join [dict get $paths "project_config"] "$project_name" "project_config.tcl"]

        if {[file exists $project_config]} {
            if {[catch {source $project_config} error]} {
                puts "❌ ERROR: Failed to load project config: $error"
                return false
            }
            puts "✅ Loaded project configuration: $project_name"
        } else {
            puts "⚠️  WARNING: Project config not found: $project_config"
        }

        return true
    }

    proc load_technology_configuration {paths tech_name} {
        set tech_config [file join [dict get $paths "tech_config"] "$tech_name" "tech_config.tcl"]

        if {[file exists $tech_config]} {
            if {[catch {source $tech_config} error]} {
                puts "❌ ERROR: Failed to load technology config: $error"
                return false
            }
            puts "✅ Loaded technology configuration: $tech_name"
        } else {
            puts "⚠️  WARNING: Technology config not found: $tech_config"
        }

        return true
    }

    # ┌─ Flow Initialization Functions ───────────────────────────────────────────┐

    proc initialize_cbflow {workarea_path {options {}}} {
        puts "🚀 Initializing CBFlow..."

        # Parse options
        set release_version ""
        set project_name ""
        set tech_name ""
        set quiet false

        if {[dict exists $options "release_version"]} {
            set release_version [dict get $options "release_version"]
        }
        if {[dict exists $options "project_name"]} {
            set project_name [dict get $options "project_name"]
        }
        if {[dict exists $options "tech_name"]} {
            set tech_name [dict get $options "tech_name"]
        }
        if {[dict exists $options "quiet"]} {
            set quiet [dict get $options "quiet"]
        }

        # Generate paths
        set paths [generate_flow_paths $workarea_path $release_version]

        # Validate paths
        if {![validate_paths $paths]} {
            return false
        }

        # Setup environment
        if {![setup_environment_variables $paths]} {
            return false
        }

        # Load configurations
        if {![load_base_configuration $paths]} {
            return false
        }

        if {$project_name ne ""} {
            load_project_configuration $paths $project_name
        }

        if {$tech_name ne ""} {
            load_technology_configuration $paths $tech_name
        }

        if {!$quiet} {
            puts "🎉 CBFlow initialization completed successfully"
        }

        return true
    }

    proc get_cbflow_info {} {
        # Return information about current CBFlow setup
        global env

        set info [dict create]

        if {[info exists env(CBFLOW_PROJECT_ROOT)]} {
            dict set info "project_root" $env(CBFLOW_PROJECT_ROOT)
            dict set info "flow_dir" $env(CBFLOW_FLOW_DIR)
            dict set info "initialized" true
        } else {
            dict set info "initialized" false
        }

        dict set info "version" $version

        return $info
    }

    # ┌─ Utility Functions ───────────────────────────────────────────────────────┐

    proc get_available_projects {project_root} {
        set project_config_dir [file join $project_root "core" "config" "project" "v1.0.0"]

        if {![file exists $project_config_dir]} {
            return {}
        }

        set projects {}
        foreach dir [glob -nocomplain -type d "$project_config_dir/*"] {
            lappend projects [file tail $dir]
        }

        return [lsort $projects]
    }

    proc get_available_technologies {project_root} {
        set tech_config_dir [file join $project_root "core" "config" "technology" "v1.0.0"]

        if {![file exists $tech_config_dir]} {
            return {}
        }

        set technologies {}
        foreach dir [glob -nocomplain -type d "$tech_config_dir/*"] {
            lappend technologies [file tail $dir]
        }

        return [lsort $technologies]
    }

    # ┌─ TCL Configuration Path Generation ────────────────────────────────────────┐

    proc generate_tcl_config_paths {paths} {
        set tcl_paths [dict create \
            flow_config_tcl [file join [dict get $paths flow_config] "flow_config.tcl"] \
            project_config_tcl [file join [dict get $paths project_config] "project_config.tcl"] \
            tech_config_tcl [file join [dict get $paths tech_config] "tech_config.tcl"] \
            directory_config_tcl [file join [dict get $paths flow_config] "dir_config.tcl"] \
            error_utils_tcl [file join [dict get $paths utils_scripts] "error_utils.tcl"] \
            utils_tcl [file join [dict get $paths utils_scripts] "utils.tcl"] \
            logo_config_tcl [file join [dict get $paths flow_config] "logo_config.tcl"] \
        ]

        return $tcl_paths
    }

    # ┌─ Environment File Generation Functions ────────────────────────────────────┐

    # Generate shell environment file (.cbflow.env)
    proc generate_shell_env {workarea_path output_file} {
        global project technology flow_settings environment versions

        set paths [generate_flow_paths $workarea_path]

        set fp [open $output_file w]
        puts $fp "# CBFlow Environment Configuration"
        puts $fp "# Generated on [clock format [clock seconds]]"
        puts $fp "# Project: $project(name) $project(version)"
        puts $fp "# Technology: $technology(vendor) $technology(node)"
        puts $fp ""

        puts $fp "# Core Configuration Paths"
        puts $fp "export CONFIG_ROOT=\"[dict get $paths config_dir]\""
        puts $fp "export SCRIPTS_ROOT=\"[dict get $paths scripts_dir]\""
        puts $fp "export PROJECT_ROOT=\"[dict get $paths project_root]\""
        puts $fp "export FLOW_DIR=\"[dict get $paths flow_dir]\""
        puts $fp ""

        puts $fp "# Project Configuration"
        puts $fp "export PROJECT_NAME=\"$project(name)\""
        puts $fp "export PROJECT_VERSION=\"$project(version)\""
        puts $fp ""

        puts $fp "# Technology Configuration"
        puts $fp "export TECHNOLOGY_VENDOR=\"$technology(vendor)\""
        puts $fp "export TECHNOLOGY_NODE=\"$technology(node)\""
        puts $fp "export TECHNOLOGY_VERSION=\"$technology(version)\""
        puts $fp ""

        puts $fp "# Individual Component Versions"
        puts $fp "export FLOW_CONFIG_VERSION=\"$versions(flow_config)\""
        puts $fp "export UTILITIES_VERSION=\"$versions(utilities)\""
        puts $fp "export NODE_MANAGEMENT_VERSION=\"$versions(node_management)\""
        puts $fp "export GENERATION_VERSION=\"$versions(generation)\""
        puts $fp "export VALIDATION_VERSION=\"$versions(validation)\""
        puts $fp "export PROJECT_CONFIG_VERSION=\"$versions(project_config)\""
        puts $fp "export TECHNOLOGY_CONFIG_VERSION=\"$versions(technology_config)\""

        close $fp
    }

    # Generate native TCL environment file (.cbflow.tcl)
    proc generate_tcl_env {workarea_path output_file} {
        global project technology flow_settings environment versions

        set paths [generate_flow_paths $workarea_path]

        set fp [open $output_file w]
        puts $fp "#!/usr/bin/env tclsh"
        puts $fp "# CBFlow Native TCL Environment"
        puts $fp "# Generated on [clock format [clock seconds]]"
        puts $fp "# Project: $project(name) $project(version)"
        puts $fp "# Technology: $technology(vendor) $technology(node)"
        puts $fp ""

        puts $fp "# Core Configuration Paths"
        puts $fp "set ::env(CONFIG_ROOT) \"[dict get $paths config_dir]\""
        puts $fp "set ::env(SCRIPTS_ROOT) \"[dict get $paths scripts_dir]\""
        puts $fp "set ::env(PROJECT_ROOT) \"[dict get $paths project_root]\""
        puts $fp "set ::env(FLOW_DIR) \"[dict get $paths flow_dir]\""
        puts $fp ""

        puts $fp "# Project Configuration"
        puts $fp "set ::env(PROJECT_NAME) \"$project(name)\""
        puts $fp "set ::env(PROJECT_VERSION) \"$project(version)\""
        puts $fp ""

        puts $fp "# Technology Configuration"
        puts $fp "set ::env(TECHNOLOGY_VENDOR) \"$technology(vendor)\""
        puts $fp "set ::env(TECHNOLOGY_NODE) \"$technology(node)\""
        puts $fp "set ::env(TECHNOLOGY_VERSION) \"$technology(version)\""
        puts $fp ""

        puts $fp "# Individual Component Versions"
        puts $fp "set ::env(FLOW_CONFIG_VERSION) \"$versions(flow_config)\""
        puts $fp "set ::env(UTILITIES_VERSION) \"$versions(utilities)\""
        puts $fp "set ::env(NODE_MANAGEMENT_VERSION) \"$versions(node_management)\""
        puts $fp "set ::env(GENERATION_VERSION) \"$versions(generation)\""
        puts $fp "set ::env(VALIDATION_VERSION) \"$versions(validation)\""
        puts $fp "set ::env(PROJECT_CONFIG_VERSION) \"$versions(project_config)\""
        puts $fp "set ::env(TECHNOLOGY_CONFIG_VERSION) \"$versions(technology_config)\""

        close $fp
    }

    # ┌─ Export Functions ────────────────────────────────────────────────────────┐
    # Export key functions to global namespace for backwards compatibility

    proc export_to_global {} {
        # Export main initialization function
        proc ::cbflow_init {workarea_path {options {}}} {
            return [::CBFlow::Utilities::InitUtils::initialize_cbflow $workarea_path $options]
        }

        proc ::cbflow_info {} {
            return [::CBFlow::Utilities::InitUtils::get_cbflow_info]
        }

        proc ::generate_flow_paths {workarea_path {release_version ""}} {
            return [::CBFlow::Utilities::InitUtils::generate_flow_paths $workarea_path $release_version]
        }

        proc ::load_flow_release_config {project_root release_version} {
            return [::CBFlow::Utilities::InitUtils::load_flow_release_config $project_root $release_version]
        }

        proc ::generate_shell_env {workarea_path output_file} {
            return [::CBFlow::Utilities::InitUtils::generate_shell_env $workarea_path $output_file]
        }

        proc ::generate_tcl_config_paths {paths} {
            return [::CBFlow::Utilities::InitUtils::generate_tcl_config_paths $paths]
        }

        proc ::generate_tcl_env {workarea_path output_file} {
            return [::CBFlow::Utilities::InitUtils::generate_tcl_env $workarea_path $output_file]
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-Export to Global Namespace
# ═══════════════════════════════════════════════════════════════════════════════

# Automatically export functions when this file is sourced
::CBFlow::Utilities::InitUtils::export_to_global