#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Node Operations
# Description: Add, delete, and list node operations
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::NodeManagement::NodeOps {
}

# ┌─ Add Node ───────────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::NodeOps::add_stage_internal {stage_type stage_name dependencies} {
    global flow

    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    # Load existing runtime config
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type

    # Ensure flow arrays exist
    ::CBFlow::NodeManagement::ensure_flow_arrays

    # Check for duplicates
    upvar #0 $flow_var flow_array
    if {[info exists flow_array(stages,$stage_name,type)]} {
        set existing_type $flow_array(stages,$stage_name,type)
        set existing_deps $flow_array(stages,$stage_name,dependencies)

        if {$existing_type eq $stage_type && $existing_deps eq $dependencies} {
            CBFLOW_WARNING "Node '$stage_name' already exists with identical configuration"
            return "duplicate"
        } else {
            CBFLOW_INFO "Node '$stage_name' already exists with different configuration"
            CBFLOW_ERROR "Cannot add duplicate node with different configuration"
            return false
        }
    }

    # Validate dependencies
    if {![::CBFlow::NodeManagement::Graph::validate_dependency_direction $current_flow_type $stage_type $stage_name $dependencies]} {
        return false
    }

    # Check for circular dependencies
    if {![::CBFlow::NodeManagement::Graph::detect_circular_dependencies $current_flow_type $stage_name $dependencies]} {
        return false
    }

    # Add the node
    set flow_array(stages,$stage_name,type) $stage_type
    set flow_array(stages,$stage_name,dependencies) $dependencies

    CBFLOW_INFO "✓ Added node '$stage_name' of type '$stage_type'"
    CBFLOW_INFO "  Dependencies: [join $dependencies {, }]"

    return true
}

# ┌─ Remove Node ────────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::NodeOps::remove_stage {stage_name} {
    global flow

    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    # Load existing runtime config
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type

    ::CBFlow::NodeManagement::ensure_flow_arrays

    # Check if base stage
    set base_stages [::CBFlow::NodeManagement::get_base_flow_sequence $current_flow_type]
    if {[lsearch -exact $base_stages $stage_name] >= 0} {
        CBFLOW_ERROR "Cannot delete base flow stage '$stage_name'"
        return false
    }

    # Check if exists
    upvar #0 $flow_var flow_array
    if {![info exists flow_array(stages,$stage_name,type)]} {
        CBFLOW_ERROR "Custom stage '$stage_name' does not exist"
        set custom_nodes [::CBFlow::NodeManagement::FlowConfig::get_custom_deletable_nodes $current_flow_type]
        if {[llength $custom_nodes] > 0} {
            CBFLOW_INFO "Available custom nodes: [join $custom_nodes {, }]"
        }
        return false
    }

    # Check downstream dependencies
    set downstream_deps [::CBFlow::NodeManagement::Graph::find_downstream_dependencies $stage_name $current_flow_type]

    if {[llength $downstream_deps] > 0} {
        CBFLOW_WARNING "⚠️  Deleting '$stage_name' will orphan dependent nodes"
    }

    # Delete the node
    unset flow_array(stages,$stage_name,type)
    if {[info exists flow_array(stages,$stage_name,dependencies)]} {
        unset flow_array(stages,$stage_name,dependencies)
    }

    CBFLOW_INFO "✓ Removed stage '$stage_name'"

    # Save config
    ::CBFlow::NodeManagement::save_flow_config

    # Regenerate Makefile to remove deleted node targets
    CBFLOW_INFO "Regenerating Makefile..."
    ::CBFlow::NodeManagement::BranchOps::regenerate_makefile

    return true
}

# ┌─ List Nodes ─────────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::NodeOps::list_current_nodes {} {
    global flow

    ::CBFlow::Utilities::RunStatus::initialize_global_access $::env(CBFLOW_RUN_DIR)

    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    # Load runtime config to get custom nodes
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type

    CBFLOW_INFO "Current flow nodes for $current_flow_type:"
    CBFLOW_INFO "==========================================="

    set flow_sequence [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $current_flow_type]

    upvar #0 $flow_var flow_array
    set has_custom_nodes false

    if {[array exists flow_array]} {
        foreach key [lsort [array names flow_array "stages,*,type"]] {
            if {[regexp {stages,([^,]+),type} $key -> node_name]} {
                set has_custom_nodes true
                break
            }
        }
    }

    if {$has_custom_nodes} {
        CBFLOW_INFO ""
        CBFLOW_INFO "Custom nodes:"
        foreach key [lsort [array names flow_array "stages,*,type"]] {
            if {[regexp {stages,([^,]+),type} $key -> node_name]} {
                set node_type $flow_array($key)
                set deps ""
                if {[info exists flow_array(stages,$node_name,dependencies)]} {
                    set deps $flow_array(stages,$node_name,dependencies)
                }
                CBFLOW_INFO "  $node_name \[$node_type\] → depends on: [join $deps {, }]"
            }
        }
        CBFLOW_INFO ""

        set run_type "node"
        if {[info exists flow(run_type)]} {
            set run_type $flow(run_type)
        }
        if {$run_type eq "flat"} {
            CBFLOW_INFO "Flow nodes (flat mode):"
        } else {
            CBFLOW_INFO "Base flow nodes:"
        }
    }

    if {[llength $flow_sequence] > 0} {
        foreach stage $flow_sequence {
            set stage_deps ""
            set stage_index [lsearch -exact $flow_sequence $stage]
            if {$stage_index > 0} {
                set prev_stage [lindex $flow_sequence [expr $stage_index - 1]]
                set stage_deps $prev_stage
            }

            if {$stage_deps eq ""} {
                CBFLOW_INFO "  $stage \[base\] → (no dependencies)"
            } else {
                CBFLOW_INFO "  $stage \[base\] → depends on: $stage_deps"
            }
        }
    } else {
        CBFLOW_INFO "No nodes found for flow type: $current_flow_type"
    }

    return true
}

# ┌─ Delete Branch ──────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::NodeOps::delete_branch {start_node} {
    global flow

    ::CBFlow::Utilities::RunStatus::initialize_global_access $::env(CBFLOW_RUN_DIR)
    set run_type "node"
    if {[info exists flow(run_type)]} {
        set run_type $flow(run_type)
    }

    if {$run_type eq "flat"} {
        CBFLOW_WARNING "delete_branch in flat mode: limited to custom data nodes only"
    }

    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type
    ::CBFlow::NodeManagement::ensure_flow_arrays

    upvar #0 $flow_var flow_array
    if {![info exists flow_array(stages,$start_node,type)]} {
        CBFLOW_ERROR "Start node '$start_node' does not exist"
        return false
    }

    set branch_nodes [list $start_node]
    set downstream [::CBFlow::NodeManagement::Graph::find_downstream_dependencies $start_node $current_flow_type]
    set branch_nodes [concat $branch_nodes $downstream]

    if {[llength $branch_nodes] == 1} {
        CBFLOW_INFO "🌿 Deleting single node: $start_node"
    } else {
        CBFLOW_INFO "🌿 Deleting entire branch: [join $branch_nodes { → }]"
    }

    set deleted_nodes [::CBFlow::NodeManagement::Graph::cascade_delete_nodes $branch_nodes $current_flow_type]

    if {[llength $deleted_nodes] > 0} {
        CBFLOW_INFO "✓ Deleted branch with [llength $deleted_nodes] nodes"
        ::CBFlow::NodeManagement::save_flow_config

        # Regenerate Makefile to remove deleted node targets
        CBFLOW_INFO "Regenerating Makefile..."
        ::CBFlow::NodeManagement::BranchOps::regenerate_makefile

        return true
    } else {
        CBFLOW_ERROR "Failed to delete branch"
        return false
    }
}
