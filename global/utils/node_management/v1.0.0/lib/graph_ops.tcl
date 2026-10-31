#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Graph Operations
# Description: Dependency graph algorithms and validation
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::NodeManagement::Graph {
}

# ┌─ Stage Precedence ───────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::Graph::get_stage_precedence_order {flow_type} {
    # Build precedence order dynamically from config file stages
    set stages [::CBFlow::NodeManagement::get_base_flow_sequence $flow_type]
    if {[llength $stages] == 0} {
        return {}
    }

    set precedence {}
    set order 0
    foreach stage $stages {
        lappend precedence $stage [expr {$order * 10}]
        incr order
    }

    return $precedence
}

proc ::CBFlow::NodeManagement::Graph::get_stage_base_type {stage_name} {
    # Extract base stage type from stage name (e.g., "place1" -> "place")
    if {[regexp {^(.+?)(\d+)$} $stage_name -> base_name suffix]} {
        return $base_name
    }
    return $stage_name
}

# ┌─ Dependency Discovery ───────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::Graph::find_downstream_dependencies {target_node flow_type} {
    set flow_type_lower [string tolower $flow_type]
    set downstream_nodes {}

    # Use in-memory array if it exists; don't re-source file to avoid restoring deleted entries
    upvar #0 $flow_type_lower flow_array

    if {[array exists flow_array]} {
        foreach key [array names flow_array "stages,*,dependencies"] {
            if {[regexp {stages,([^,]+),dependencies} $key -> dependent_node]} {
                set dependencies $flow_array($key)

                # Flatten nested list formats
                set flattened_deps {}
                foreach dep_group $dependencies {
                    foreach dep_subgroup $dep_group {
                        foreach dep $dep_subgroup {
                            lappend flattened_deps $dep
                        }
                    }
                }

                if {[lsearch -exact $flattened_deps $target_node] >= 0} {
                    lappend downstream_nodes $dependent_node
                }
            }
        }
    }

    return [lsort $downstream_nodes]
}

proc ::CBFlow::NodeManagement::Graph::cascade_delete_nodes {nodes_to_delete flow_type} {
    set flow_type_lower [string tolower $flow_type]
    set deleted_nodes {}

    foreach node $nodes_to_delete {
        if {[lsearch -exact $deleted_nodes $node] >= 0} {
            continue
        }

        set downstream [find_downstream_dependencies $node $flow_type]

        upvar #0 $flow_type_lower flow_array
        if {[info exists flow_array(stages,$node,type)]} {
            unset flow_array(stages,$node,type)
            if {[info exists flow_array(stages,$node,dependencies)]} {
                unset flow_array(stages,$node,dependencies)
            }
            if {[info exists flow_array(stages,$node,branch_key)]} {
                unset flow_array(stages,$node,branch_key)
            }
            lappend deleted_nodes $node
            CBFLOW_INFO "✓ Deleted node: $node"
        }

        if {[llength $downstream] > 0} {
            set cascade_deleted [cascade_delete_nodes $downstream $flow_type]
            set deleted_nodes [concat $deleted_nodes $cascade_deleted]
        }
    }

    return $deleted_nodes
}

# ┌─ Dependency Validation ──────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::Graph::validate_dependency_direction {flow_type stage_type stage_name dependencies} {
    # Ensure global arrays are accessible
    ::CBFlow::Utilities::RunStatus::initialize_global_access $::env(CBFLOW_RUN_DIR)

    set flow_sequence [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $flow_type]
    set validation_errors {}

    # Get all valid nodes
    set valid_nodes [list {*}$flow_sequence]

    set flow_var [string tolower $flow_type]
    upvar #0 $flow_var flow_array
    if {[array exists flow_array]} {
        foreach key [array names flow_array "stages,*,type"] {
            if {[regexp {stages,([^,]+),type} $key -> node_name]} {
                lappend valid_nodes $node_name
            }
        }
    }

    # Check each dependency exists
    foreach dep_list $dependencies {
        foreach dep $dep_list {
            if {[lsearch -exact $valid_nodes $dep] == -1} {
                lappend validation_errors "Dependency '$dep' does not exist in $flow_type flow"
            }
        }
    }

    if {[llength $validation_errors] > 0} {
        CBFLOW_INFO "❌ Dependency validation failed for '$stage_name':"
        foreach error $validation_errors {
            CBFLOW_INFO "  ✗ $error"
        }
        CBFLOW_ERROR "Cannot add node '$stage_name' - invalid dependencies"
        return false
    }

    # Validate precedence order
    set precedence [get_stage_precedence_order $flow_type]
    if {[llength $precedence] == 0} {
        return true
    }

    array set precedence_map $precedence

    set current_base_type [get_stage_base_type $stage_name]
    if {![info exists precedence_map($current_base_type)]} {
        CBFLOW_WARNING "No precedence rule defined for stage type '$current_base_type'"
        return true
    }
    set current_precedence $precedence_map($current_base_type)

    set precedence_errors {}
    foreach dep_list $dependencies {
        foreach dep $dep_list {
            set dep_base_type [get_stage_base_type $dep]
            if {[info exists precedence_map($dep_base_type)]} {
                set dep_precedence $precedence_map($dep_base_type)
                if {$dep_precedence >= $current_precedence} {
                    lappend precedence_errors "Dependency '$dep' comes after or at same level as '$stage_name'"
                }
            }
        }
    }

    if {[llength $precedence_errors] > 0} {
        CBFLOW_INFO "❌ Dependency precedence validation failed for '$stage_name':"
        foreach error $precedence_errors {
            CBFLOW_INFO "  ✗ $error"
        }
        CBFLOW_ERROR "Cannot add node '$stage_name' due to invalid dependency precedence"
        return false
    }

    return true
}

proc ::CBFlow::NodeManagement::Graph::detect_circular_dependencies {flow_type stage_name dependencies} {
    set flow_var [string tolower $flow_type]
    upvar #0 $flow_var flow_array

    array set dep_graph {}

    # Add existing nodes
    foreach key [array names flow_array "stages,*,dependencies"] {
        if {[regexp {stages,([^,]+),dependencies} $key -> node]} {
            set dep_graph($node) $flow_array($key)
        }
    }

    # Add new node
    set dep_graph($stage_name) $dependencies

    # DFS cycle detection
    array set visited {}
    array set in_path {}

    proc dfs_check {node graph_ref visited_ref path_ref} {
        upvar $graph_ref graph
        upvar $visited_ref visited
        upvar $path_ref in_path

        if {[info exists in_path($node)]} {
            return $node
        }
        if {[info exists visited($node)]} {
            return ""
        }

        set visited($node) 1
        set in_path($node) 1

        if {[info exists graph($node)]} {
            foreach dep_list $graph($node) {
                foreach dep $dep_list {
                    set result [dfs_check $dep graph visited in_path]
                    if {$result ne ""} {
                        return $result
                    }
                }
            }
        }

        unset in_path($node)
        return ""
    }

    set cycle_node [dfs_check $stage_name dep_graph visited in_path]
    if {$cycle_node ne ""} {
        CBFLOW_ERROR "Circular dependency detected involving node '$cycle_node'"
        return false
    }

    return true
}

# ┌─ Graph Display ──────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::Graph::show_graph {} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]

    CBFLOW_INFO "Node Dependency Graph for $current_flow_type Flow:"
    CBFLOW_INFO "=================================================="

    # Load runtime config to get custom nodes
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type

    array set all_nodes {}
    array set node_deps {}

    # Get base flow sequence
    set flow_sequence [::CBFlow::NodeManagement::get_base_flow_sequence $current_flow_type]
    foreach stage $flow_sequence {
        set all_nodes($stage) "base"
    }

    # Build dependencies
    set prev_stage ""
    foreach stage $flow_sequence {
        if {$prev_stage ne ""} {
            set node_deps($stage) [list $prev_stage]
        } else {
            set node_deps($stage) {}
        }
        set prev_stage $stage
    }

    # Add custom nodes
    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array
    if {[array exists flow_array]} {
        foreach key [array names flow_array "stages,*,type"] {
            if {[regexp {stages,([^,]+),type} $key -> node_name]} {
                set all_nodes($node_name) "custom"
                if {[info exists flow_array(stages,$node_name,dependencies)]} {
                    set node_deps($node_name) $flow_array(stages,$node_name,dependencies)
                } else {
                    set node_deps($node_name) {}
                }
            }
        }
    }

    # Display tree
    CBFLOW_INFO ""
    CBFLOW_INFO "Dependency Tree:"
    CBFLOW_INFO "───────────────"

    # Find root nodes
    set root_nodes {}
    foreach node [array names all_nodes] {
        if {![info exists node_deps($node)] || [llength $node_deps($node)] == 0} {
            lappend root_nodes $node
        }
    }

    if {[llength $root_nodes] == 0} {
        CBFLOW_WARNING "No root nodes found"
        set root_nodes [lindex [array names all_nodes] 0]
    }

    # Display tree recursively
    proc display_tree {node deps_array nodes_array level visited_array} {
        upvar $deps_array deps_map
        upvar $nodes_array nodes_map
        upvar $visited_array visited

        if {[info exists visited($node)]} {
            return
        }
        set visited($node) 1

        set indent ""
        for {set i 0} {$i < $level} {incr i} {
            append indent "  "
        }

        set type_indicator ""
        if {[info exists nodes_map($node)] && $nodes_map($node) eq "custom"} {
            set type_indicator " \[CUSTOM\]"
        }

        CBFLOW_INFO "${indent}├─ $node$type_indicator"

        # Find children
        set children {}
        foreach child_node [array names deps_map] {
            if {[lsearch -exact $deps_map($child_node) $node] >= 0} {
                lappend children $child_node
            }
        }

        foreach child [lsort $children] {
            display_tree $child deps_map nodes_map [expr $level + 1] visited
        }
    }

    array set visited {}
    foreach root [lsort $root_nodes] {
        display_tree $root node_deps all_nodes 0 visited
        CBFLOW_INFO ""
    }

    # Show dependency details
    CBFLOW_INFO "Dependency Details:"
    CBFLOW_INFO "──────────────────"
    foreach node [lsort [array names all_nodes]] {
        set deps_list {}
        if {[info exists node_deps($node)]} {
            set deps_list $node_deps($node)
        }

        set type_str ""
        if {$all_nodes($node) eq "custom"} {
            set type_str " \[CUSTOM\]"
        }

        if {[llength $deps_list] == 0} {
            CBFLOW_INFO "  $node$type_str ← (no dependencies)"
        } else {
            CBFLOW_INFO "  $node$type_str ← [join $deps_list {, }]"
        }
    }

    return 0
}

proc ::CBFlow::NodeManagement::Graph::validate {} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    CBFLOW_INFO "Validating node configuration for $current_flow_type..."

    set flow_sequence [::CBFlow::NodeManagement::get_base_flow_sequence $current_flow_type]

    if {[llength $flow_sequence] == 0} {
        CBFLOW_ERROR "No valid flow sequence found for $current_flow_type"
        return 1
    }

    CBFLOW_INFO "✓ Base flow sequence valid: [llength $flow_sequence] stages"

    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array
    set custom_count 0
    if {[array exists flow_array]} {
        foreach key [array names flow_array "stages,*,type"] {
            incr custom_count
        }
    }

    if {$custom_count > 0} {
        CBFLOW_INFO "✓ Found $custom_count custom nodes"
    } else {
        CBFLOW_INFO "✓ No custom nodes (using standard flow)"
    }

    CBFLOW_INFO "✓ Node configuration validation passed"
    return 0
}
