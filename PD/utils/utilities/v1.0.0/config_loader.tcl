#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Centralized Config Loader
#
# Description: Loads flow types, stages, tool mappings, and flat mode config
#              from existing Tcl config files (flow_config.tcl + node_configs/).
#              Provides a single source of truth - eliminates hardcoded values
#              in consumer scripts.
#
# Usage: source utils/utilities/v1.0.0/config_loader.tcl
#        ::CBFlow::Config::get_flow_types
#        ::CBFlow::Config::get_flow_stages PNR
#        ::CBFlow::Config::get_tool_info PNR
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::Config {
    variable loaded_flows {}
    variable flow_config_loaded false
    variable config_root ""
    variable config_version ""
}

# ┌─ Internal: Resolve Config Paths ───────────────────────────────────────────┐

proc ::CBFlow::Config::_resolve_paths {} {
    variable config_root
    variable config_version

    if {$config_root ne ""} {
        return
    }

    # Determine config root
    if {[info exists ::env(CONFIG_ROOT)]} {
        set config_root $::env(CONFIG_ROOT)
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set config_root "$::env(FLOW_DIR)/config"
    } elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
        set config_root "$::env(CBFLOW_CORE_DIR)/config"
    } else {
        puts stderr "WARNING: Cannot resolve config root - CONFIG_ROOT, FLOW_DIR, or CBFLOW_CORE_DIR not set"
        return
    }

    # Determine config version
    if {[info exists ::env(FLOW_CONFIG_VERSION)]} {
        set config_version $::env(FLOW_CONFIG_VERSION)
    } else {
        set config_version "v1.0.1"
    }
}

# ┌─ Internal: Ensure flow_config.tcl Is Loaded ──────────────────────────────┐

proc ::CBFlow::Config::_ensure_flow_config {} {
    variable flow_config_loaded
    variable config_root
    variable config_version

    if {$flow_config_loaded} {
        return 1
    }

    _resolve_paths
    if {$config_root eq ""} {
        return 0
    }

    set config_file "$config_root/flow/$config_version/flow_config.tcl"
    if {![file exists $config_file]} {
        puts stderr "WARNING: flow_config.tcl not found at: $config_file"
        return 0
    }

    # Source at global scope if not already loaded
    if {![info exists ::flow(types)]} {
        if {[catch {uplevel #0 source $config_file} err]} {
            puts stderr "WARNING: Failed to source flow_config.tcl: $err"
            return 0
        }
    }

    set flow_config_loaded true
    return 1
}

# ┌─ Internal: Ensure a Node Config Is Loaded ────────────────────────────────┐

proc ::CBFlow::Config::_ensure_node_config {flow_type} {
    variable loaded_flows
    variable config_root
    variable config_version

    if {[lsearch -exact $loaded_flows $flow_type] >= 0} {
        return 1
    }

    _resolve_paths
    if {$config_root eq ""} {
        return 0
    }

    set config_file "$config_root/flow/$config_version/node_configs/${flow_type}_config.tcl"
    if {![file exists $config_file]} {
        puts stderr "WARNING: Node config not found: $config_file"
        return 0
    }

    # Source at global scope
    if {[catch {uplevel #0 source $config_file} err]} {
        puts stderr "WARNING: Failed to source ${flow_type}_config.tcl: $err"
        return 0
    }

    lappend loaded_flows $flow_type
    return 1
}

# ┌─ Internal: Access a Flow-Specific Array ──────────────────────────────────┐

proc ::CBFlow::Config::_get_flow_array_value {flow_type key} {
    set array_name [string tolower $flow_type]
    upvar #0 $array_name flow_arr
    if {[array exists flow_arr] && [info exists flow_arr($key)]} {
        return $flow_arr($key)
    }
    return ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Flow Types ──────────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_flow_types {} {
    _ensure_flow_config
    if {[info exists ::flow(types)]} {
        return $::flow(types)
    }
    return {SYNTH FP PNR LEC EMIR ECO CLP POPT FCFP}
}

proc ::CBFlow::Config::get_flow_description {flow_type} {
    _ensure_flow_config
    if {[info exists ::flow_descriptions($flow_type)]} {
        return $::flow_descriptions($flow_type)
    }
    return $flow_type
}

# ┌─ Flow Stages ─────────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_flow_stages {flow_type} {
    if {![_ensure_node_config $flow_type]} {
        return {}
    }
    set stages [_get_flow_array_value $flow_type "stages"]
    return $stages
}

# ┌─ Subnodes ────────────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_subnodes {flow_type stage} {
    if {![_ensure_node_config $flow_type]} {
        return {}
    }
    return [_get_flow_array_value $flow_type "subnodes,$stage"]
}

# ┌─ Tool Info ───────────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_tool_vendor {flow_type} {
    if {![_ensure_node_config $flow_type]} {
        return ""
    }
    return [_get_flow_array_value $flow_type "tool,vendor"]
}

proc ::CBFlow::Config::get_tool_name {flow_type} {
    if {![_ensure_node_config $flow_type]} {
        return ""
    }
    return [_get_flow_array_value $flow_type "tool,name"]
}

proc ::CBFlow::Config::get_tool_version {flow_type} {
    if {![_ensure_node_config $flow_type]} {
        return ""
    }
    return [_get_flow_array_value $flow_type "tool,version"]
}

proc ::CBFlow::Config::get_supported_tools {flow_type} {
    if {![_ensure_node_config $flow_type]} {
        return {}
    }
    return [_get_flow_array_value $flow_type "supported_tools"]
}

proc ::CBFlow::Config::get_tool_path {flow_type} {
    set vendor [get_tool_vendor $flow_type]
    set tool [get_tool_name $flow_type]
    if {$vendor ne "" && $tool ne ""} {
        return "$vendor/$tool"
    }
    return ""
}

proc ::CBFlow::Config::get_tool_path_with_version {flow_type {version_var ""}} {
    set vendor [get_tool_vendor $flow_type]
    set tool [get_tool_name $flow_type]
    if {$vendor eq "" || $tool eq ""} {
        return "generic/tool/\$(TOOL_VERSION)"
    }
    # Build a version variable name from tool name (e.g., INNOVUS_VERSION)
    if {$version_var eq ""} {
        set version_var "\$([string toupper $tool]_VERSION)"
    }
    return "$vendor/$tool/$version_var"
}

# ┌─ Phases and Milestones ───────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_phases {} {
    _ensure_flow_config
    if {[info exists ::flow(phases)]} {
        return $::flow(phases)
    }
    return {P0 P1 P2 P3}
}

proc ::CBFlow::Config::get_phase_description {phase} {
    _ensure_flow_config
    if {[info exists ::phase_descriptions($phase)]} {
        return $::phase_descriptions($phase)
    }
    return $phase
}

proc ::CBFlow::Config::get_exit_milestones {} {
    _ensure_flow_config
    if {[info exists ::flow(exit_milestones)]} {
        return $::flow(exit_milestones)
    }
    return {}
}

# ┌─ Flat Mode ───────────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::get_flat_merged_node_name {flow_type} {
    _ensure_flow_config
    if {[info exists ::flat_merged_node_names($flow_type)]} {
        return $::flat_merged_node_names($flow_type)
    }
    return "${flow_type}_merged"
}

proc ::CBFlow::Config::get_execution_nodes {flow_type} {
    _ensure_flow_config
    if {[info exists ::flat_execution_nodes($flow_type)]} {
        return $::flat_execution_nodes($flow_type)
    }
    return {}
}

proc ::CBFlow::Config::get_data_nodes {flow_type} {
    _ensure_flow_config
    if {[info exists ::flat_data_nodes($flow_type)]} {
        return $::flat_data_nodes($flow_type)
    }
    return {}
}

# ┌─ Subnode Working Directories ──────────────────────────────────────────────┐

proc ::CBFlow::Config::get_subnode_work_dir {flow_type stage subnode} {
    if {![_ensure_node_config $flow_type]} {
        return "work/$stage/$subnode"
    }
    set dir [_get_flow_array_value $flow_type "subnode_work_dirs,$stage,$subnode"]
    if {$dir ne ""} {
        return $dir
    }
    return "work/$stage/$subnode"
}

# ┌─ Cache Management ────────────────────────────────────────────────────────┐

proc ::CBFlow::Config::reset {} {
    variable loaded_flows
    variable flow_config_loaded
    variable config_root
    variable config_version

    set loaded_flows {}
    set flow_config_loaded false
    set config_root ""
    set config_version ""
}
