# CBFlow Scripts Component Registry
# Tracks all versioned script components and their current states

# Script Registry
array set SCRIPT_REGISTRY {
    node_management {
        description "Node and flow management scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "node_management"
        main_scripts {manage_node.tcl manage_restrictions.tcl}
    }
    validation {
        description "Validation and verification scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "validation"
        main_scripts {validate_config.tcl validate_run.tcl validate_floorplan.tcl validate_netlist.tcl validate_sdc.tcl}
    }
    generation {
        description "Generation and templating scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "generation"
        main_scripts {generate_config.tcl generate_setup.tcl generate_inputs.tcl gen_run_makefile.tcl}
    }
    utilities {
        description "Core utility functions and helpers"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "utilities"
        main_scripts {utils.tcl display_utils.tcl start_run.tcl run_status.tcl list_runs.tcl}
    }
    release {
        description "Release management and packaging scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "release"
        main_scripts {release_data.tcl release_database.tcl}
    }
    version {
        description "Version management scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "version"
        main_scripts {}
    }
    makefile_commands {
        description "Makefile command implementation scripts"
        current_version "v1.0.0"
        available_versions {v1.0.0}
        workspace_active true
        base_path "makefile_commands"
        main_scripts {create_version.sh commit_version.sh release_flow.sh set_version.sh add_directory.sh create_workspace.sh promote_version.sh list_workspace.sh help_detail.sh release_info.sh}
    }
}

# Script Dependencies
array set SCRIPT_DEPENDENCIES {
    node_management {utilities}
    validation {utilities}
    generation {utilities validation}
    utilities {}
    release {utilities validation}
    version {}
    makefile_commands {version utilities}
}

# Version Management Functions for Scripts
proc get_script_current_version {component} {
    global SCRIPT_REGISTRY
    if {[info exists SCRIPT_REGISTRY($component)]} {
        return [dict get $SCRIPT_REGISTRY($component) current_version]
    }
    return ""
}

proc get_script_path {component {version "current"}} {
    global SCRIPT_REGISTRY
    if {[info exists SCRIPT_REGISTRY($component)]} {
        set base_path [dict get $SCRIPT_REGISTRY($component) base_path]
        return "$base_path/$version"
    }
    return ""
}

proc list_available_script_components {} {
    global SCRIPT_REGISTRY
    return [array names SCRIPT_REGISTRY]
}

proc get_main_scripts {component} {
    global SCRIPT_REGISTRY
    if {[info exists SCRIPT_REGISTRY($component)]} {
        return [dict get $SCRIPT_REGISTRY($component) main_scripts]
    }
    return {}
}

proc validate_script_dependencies {component} {
    global SCRIPT_DEPENDENCIES SCRIPT_REGISTRY

    if {![info exists SCRIPT_DEPENDENCIES($component)]} {
        return false
    }

    set deps $SCRIPT_DEPENDENCIES($component)
    foreach dep $deps {
        if {![info exists SCRIPT_REGISTRY($dep)]} {
            puts "ERROR: Missing script dependency $dep for component $component"
            return false
        }
    }
    return true
}

puts "CBFlow Script Registry loaded - [llength [array names SCRIPT_REGISTRY]] script components registered"