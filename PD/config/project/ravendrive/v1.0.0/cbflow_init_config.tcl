# Project Initialization Configuration - Ravendrive SoC v1.0.0
# CBFlow initialization configuration for the Ravendrive project

#===============================================================================
# ESSENTIAL INITIALIZATION ARRAYS
#===============================================================================

# 1. Project information
array set project {
    name "ravendrive"
    version "v1.0.0"
    description "Ravendrive SoC - High Performance Application Processor"
    design_top "ravendrive_soc"
}

# 2. Technology information
array set technology {
    vendor "gf"
    node "7nm"
    version "v1.0.0"
    process "7FF"
}

# 3. Flow settings
array set flow_settings {
    default_flow "SYNTH"
}
catch { set flow_settings(release_version) $::env(CBFLOW_RELEASE_VERSION) }
catch { set flow_settings(config_version) $::env(FLOW_CONFIG_VERSION) }

# 4. Component versions — resolved from release (not hardcoded)
array set versions {}
foreach {env_key ver_key} {
    FLOW_CONFIG_VERSION flow_config
    UTILITIES_VERSION utilities
    NODE_MANAGEMENT_VERSION node_management
    GENERATION_VERSION generation
    VALIDATION_VERSION validation
    PROJECT_VERSION project_config
    TECHNOLOGY_VERSION technology_config
} {
    if {[info exists ::env($env_key)]} {
        set versions($ver_key) $::env($env_key)
    } else {
        set versions($ver_key) [expr {[info exists ::env(CBFLOW_RELEASE_VERSION)] ? $::env(CBFLOW_RELEASE_VERSION) : "v1.0.0"}]
    }
}

# 5. Environment settings
array set environment {
    shell "/bin/bash"
    tcl_shell "/usr/bin/tclsh"
    log_level "INFO"
}

#===============================================================================
# PORTABLE PATH RESOLUTION
#===============================================================================

# CBFlow root directory — FLOW_DIR must be set (by cbflow CLI / .cshrc / .bashrc)
if {[info exists ::env(FLOW_DIR)]} {
    set cbflow_root_resolved $::env(FLOW_DIR)
} elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
    set cbflow_root_resolved $::env(CBFLOW_CORE_DIR)
} else {
    puts "ERROR: FLOW_DIR or CBFLOW_CORE_DIR not set. Source your cbflow environment first."
    puts "  Add to .cshrc: setenv CBFLOW_HOME /path/to/CBflow/PD"
    puts "  Or .bashrc:    export CBFLOW_HOME=/path/to/CBflow/PD"
}

array set cbflow {
    root $cbflow_root_resolved
}

#===============================================================================
# LOAD INITIALIZATION UTILITIES
#===============================================================================

# Source initialization utilities (version from release, not hardcoded)
set _utils_ver [expr {[info exists ::env(UTILITIES_VERSION)] ? $::env(UTILITIES_VERSION) : $versions(utilities)}]
if {[info exists cbflow(root)] && [file exists "$cbflow(root)/utils/utilities/$_utils_ver/utils.tcl"]} {
    source "$cbflow(root)/utils/utilities/$_utils_ver/utils.tcl"
}

#===============================================================================
# LOAD CONFIRMATION
#===============================================================================

catch { puts "INFO: CBFlow init config loaded: $project(name)" }

#===============================================================================
# CBFLOW INITIALIZATION LOGIC
#===============================================================================

# Only execute initialization if this script is run directly
if {[info exists argv0] && [file tail $argv0] eq [file tail [info script]]} {

    puts ""
    puts "🔧 Executing CBFlow initialization..."

    # Get the directory where this script is located
    set script_dir [file dirname [file normalize [info script]]]

    # Get CBFlow root directory from environment
    set cbflow_root_auto $::env(FLOW_DIR)

    # Validate or override cbflow(root) with auto-detected path
    if {$cbflow(root) ne $cbflow_root_auto} {
        puts "⚠️  Config cbflow(root): $cbflow(root)"
        puts "⚠️  Auto-detected root: $cbflow_root_auto"
        puts "🔧 Using auto-detected CBFlow root for path resolution"
        set cbflow(root) $cbflow_root_auto
    }

    #===========================================================================
    # LOAD CBFLOW CONFIGURATIONS
    #===========================================================================

    puts "📋 Loading CBFlow configurations..."

    # Load logo display utilities
    set logo_script_path "$cbflow(root)/utils/utilities/current/logo_display.tcl"
    if {[file exists $logo_script_path]} {
        source $logo_script_path
    }

    # Load flow config for logo information
    set flow_config_path "$cbflow(root)/config/flow/current/flow_config.tcl"
    if {[file exists $flow_config_path]} {
        source $flow_config_path
    }

    # Load logo config
    set logo_config_path "$cbflow(root)/config/flow/current/logo_config.tcl"
    if {[file exists $logo_config_path]} {
        source $logo_config_path
    }

    #===========================================================================
    # GENERATE DERIVED PATHS
    #===========================================================================

    puts "🔧 Generating derived paths..."

    # Working directories (use current working directory for .env files)
    set current_dir $::env(CBFLOW_RUN_DIR)
    set derived_paths(workarea) $current_dir

    # Check if we're in preview mode (for make init diff preview)
    if {[info exists ::env(CBFLOW_PREVIEW_MODE)] && [info exists ::env(CBFLOW_PREVIEW_DIR)]} {
        set derived_paths(cbflow_env) "$::env(CBFLOW_PREVIEW_DIR)/.cbflow.env"
        puts "🔍 Preview mode: generating config for comparison"
    } else {
        set derived_paths(cbflow_env) "$current_dir/.cbflow.env"
    }
    set derived_paths(scripts) "$cbflow(root)/scripts"

    # Configuration paths
    set derived_paths(flow_config) "$cbflow(root)/config/flow/$flow_settings(config_version)"
    set derived_paths(project_config) "$cbflow(root)/config/project/$project(name)/$project(version)"
    set derived_paths(tech_config) "$cbflow(root)/config/technology/$technology(vendor)_$technology(node)/$technology(version)"

    # Script paths
    set derived_paths(utilities) "$cbflow(root)/utils/utilities/$flow_settings(config_version)"
    set derived_paths(generation) "$cbflow(root)/utils/generation/$flow_settings(config_version)"
    set derived_paths(validation) "$cbflow(root)/utils/validation/$flow_settings(config_version)"

    puts "✅ Derived paths generated"

    #===========================================================================
    # DISPLAY INITIALIZATION HEADER
    #===========================================================================

    # Display initialization header with project context
    if {[info procs display_init_header] ne ""} {
        display_init_header $project(name) "$technology(vendor)_$technology(node)" $flow_settings(release_version)
    }

    #===========================================================================
    # WORKAREA VALIDATION
    #===========================================================================

    puts "🔧 Using current directory as workarea..."
    puts "✅ Workarea: $derived_paths(workarea)"

    #===========================================================================
    # GENERATE .cbflow.env FILE
    #===========================================================================

    puts "🔧 Generating environment files..."

    # Generate shell environment file (.cbflow.env)
    if {[catch {
        generate_shell_env $derived_paths(workarea) $derived_paths(cbflow_env)
    } error]} {
        puts "❌ Failed to generate shell environment file: $error"
        exit 1
    }
    puts "✅ Generated .cbflow.env file: $derived_paths(cbflow_env)"

    # Generate native TCL environment file (.cbflow.tcl)
    set cbflow_tcl_file "$current_dir/.cbflow.tcl"
    if {[catch {
        generate_tcl_env $derived_paths(workarea) $cbflow_tcl_file
    } error]} {
        puts "❌ Failed to generate TCL environment file: $error"
        exit 1
    }
    puts "✅ Generated .cbflow.tcl file: $cbflow_tcl_file"

    #===========================================================================
    # DISPLAY SUMMARY
    #===========================================================================

    puts ""
    puts "═══════════════════════════════════════════════════════════════"
    puts "CBFlow Initialization Complete"
    puts "═══════════════════════════════════════════════════════════════"
    puts ""
    puts "📋 Configuration Summary:"
    puts "   Project: $project(name) $project(version)"
    puts "   Technology: $technology(vendor) $technology(node) $technology(process)"
    puts "   Flow Release: $flow_settings(release_version)"
    puts "   CBFlow Root: $cbflow(root)"
    puts ""
    puts "📁 Generated Files:"
    puts "   Workarea: $derived_paths(workarea)"
    puts "   Shell Environment: $derived_paths(cbflow_env)"
    puts "   TCL Environment: $cbflow_tcl_file"
    puts ""
    puts "🔧 To use the environment:"
    puts "   source $derived_paths(cbflow_env)      # For shell scripts"
    puts "   source $cbflow_tcl_file               # For TCL scripts (recommended)"
    puts "   # For Makefiles: source .cbflow.env variables as needed"
    puts ""
    puts "✅ CBFlow initialization completed successfully!"

}