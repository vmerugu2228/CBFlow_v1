#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Flow Configuration
# Description: Flow type detection and configuration loading
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::NodeManagement::FlowConfig {
}

# ┌─ Flow Type Detection ────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::FlowConfig::get_current_flow_type {} {
    global flow

    set flow_type ""

    # Method 1: Check CBFLOW_FLOW_TYPE environment variable (primary method)
    if {[info exists ::env(CBFLOW_FLOW_TYPE)] && $::env(CBFLOW_FLOW_TYPE) ne ""} {
        set flow_type $::env(CBFLOW_FLOW_TYPE)
        CBFLOW_DEBUG "Flow type from CBFLOW_FLOW_TYPE env: $flow_type"
        return $flow_type
    }

    # Method 2: Check user config file
    if {[info exists ::env(CBFLOW_RUN_DIR)]} {
        set user_config "$::env(CBFLOW_RUN_DIR)/setup/user_config.tcl"
        if {[file exists $user_config]} {
            set fd [open $user_config r]
            set content [read $fd]
            close $fd

            if {[regexp {set\s+flow\(type\)\s+"([^"]+)"} $content -> detected_type]} {
                set flow_type $detected_type
                CBFLOW_DEBUG "Flow type detected from user config: $flow_type"
                return $flow_type
            }
        }
    }

    # Method 3: Check flow array if loaded
    if {[info exists flow(type)]} {
        set flow_type $flow(type)
        CBFLOW_DEBUG "Flow type from flow array: $flow_type"
        return $flow_type
    }

    # Method 4: Error if no flow type available
    puts stderr "ERROR: Flow type not found in environment or configuration"
    exit 1
}

# ┌─ Flow Sequence Loading ──────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::FlowConfig::get_base_flow_sequence {flow_type} {
    # Load flow sequence from config files - no hardcoding

    if {![info exists ::env(CONFIG_ROOT)] || ![info exists ::env(FLOW_CONFIG_VERSION)]} {
        CBFLOW_ERROR "CONFIG_ROOT or FLOW_CONFIG_VERSION not set in environment"
        return {}
    }

    set config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/${flow_type}_config.tcl"

    if {![file exists $config_file]} {
        CBFLOW_ERROR "Config file not found: $config_file"
        return {}
    }

    # Source the config file at global scope so arrays are created globally
    if {[catch {uplevel #0 source $config_file} error]} {
        CBFLOW_ERROR "Failed to load config file: $error"
        return {}
    }

    # Access the flow-specific global array using upvar (avoids "already exists" error)
    set flow_var [string tolower $flow_type]
    upvar #0 $flow_var flow_array
    if {[array exists flow_array] && [info exists flow_array(stages)]} {
        return $flow_array(stages)
    }

    CBFLOW_ERROR "No stages found in $flow_type config"
    return {}
}

# ┌─ Flow Array Management ──────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::FlowConfig::ensure_flow_arrays {} {
    global flow

    if {[info exists flow(type)]} {
        set flow_type [string tolower $flow(type)]
        upvar #0 $flow_type flow_array
        if {![array exists flow_array]} {
            array set flow_array {}
        }
    }
}

proc ::CBFlow::NodeManagement::FlowConfig::get_flow_array_name {flow_type} {
    return [string tolower $flow_type]
}

# ┌─ Custom Node Queries ────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::FlowConfig::get_custom_deletable_nodes {flow_type} {
    set flow_type_lower [string tolower $flow_type]
    set deletable_nodes {}

    if {[info exists ::env(CBFLOW_RUN_DIR)]} {
        set runtime_config "$::env(CBFLOW_RUN_DIR)/setup/runtime_flow_config.tcl"
        if {[file exists $runtime_config]} {
            if {[catch {uplevel #0 source $runtime_config} error] == 0} {
                upvar #0 $flow_type_lower flow_array
                if {[array exists flow_array]} {
                    foreach key [array names flow_array "stages,*,type"] {
                        if {[regexp {stages,([^,]+),type} $key -> stage_name]} {
                            lappend deletable_nodes $stage_name
                        }
                    }
                }
            }
        }
    }

    return [lsort $deletable_nodes]
}

# ┌─ Convenience Aliases ────────────────────────────────────────────────────────┐

# Create shorthand procs in parent namespace
proc ::CBFlow::NodeManagement::get_current_flow_type {} {
    return [::CBFlow::NodeManagement::FlowConfig::get_current_flow_type]
}

proc ::CBFlow::NodeManagement::get_base_flow_sequence {flow_type} {
    return [::CBFlow::NodeManagement::FlowConfig::get_base_flow_sequence $flow_type]
}

proc ::CBFlow::NodeManagement::ensure_flow_arrays {} {
    return [::CBFlow::NodeManagement::FlowConfig::ensure_flow_arrays]
}
