#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Branch Operations
# Description: Create, delete, and list branch operations
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::NodeManagement::BranchOps {
}

# ┌─ Makefile Regeneration ────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::BranchOps::regenerate_makefile {} {
    # Regenerate Makefile to include new/modified nodes

    if {![info exists ::env(FLOW_DIR)]} {
        CBFLOW_WARNING "FLOW_DIR not set, cannot regenerate Makefile"
        return false
    }

    set generation_version "v1.0.0"
    if {[info exists ::env(GENERATION_VERSION)]} {
        set generation_version $::env(GENERATION_VERSION)
    }

    set gen_script "$::env(FLOW_DIR)/utils/generation/$generation_version/gen_run_makefile.tcl"

    if {![file exists $gen_script]} {
        CBFLOW_WARNING "Makefile generator not found: $gen_script"
        return false
    }

    # Run the generator as a subprocess to ensure fresh state
    if {[catch {exec tclsh $gen_script} result]} {
        CBFLOW_ERROR "Failed to regenerate Makefile: $result"
        return false
    }

    CBFLOW_INFO "✓ Makefile regenerated successfully"
    return true
}

# ┌─ Suffix Management ─────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::BranchOps::find_next_available_suffix {base_stage} {
    # Find the next available numeric suffix for branch nodes
    # Checks both base flow stages and custom nodes for the highest existing suffix

    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    set max_suffix 0

    # Check base flow stages (e.g., inputs1, place1, cts1)
    set base_flow [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $current_flow_type]
    foreach node $base_flow {
        if {[regexp {^[a-zA-Z_]+([0-9]+)$} $node -> node_suffix]} {
            set suffix_num [scan $node_suffix %d]
            if {$suffix_num > $max_suffix} {
                set max_suffix $suffix_num
            }
        }
    }

    # Also check custom nodes in runtime config
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type
    upvar #0 $flow_var flow_array

    if {[array exists flow_array]} {
        foreach key [array names flow_array "stages,*,type"] {
            if {[regexp {stages,([a-zA-Z_]+)([0-9]+),type} $key -> node_base node_suffix]} {
                set suffix_num [scan $node_suffix %d]
                if {$suffix_num > $max_suffix} {
                    set max_suffix $suffix_num
                }
            }
        }
    }

    # Return next available suffix
    return [expr {$max_suffix + 1}]
}

# ┌─ Branch Key Management ──────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::BranchOps::generate_unique_branch_key {branch_type} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array

    set timestamp [clock seconds]
    set random_part [expr {int(rand() * 9999)}]
    set unique_id [format "%08x_%04d" $timestamp $random_part]
    set branch_key "${branch_type}_${unique_id}"

    if {[array exists flow_array]} {
        set attempts 0
        while {[info exists flow_array(branch_keys,$branch_key,name)] && $attempts < 100} {
            set random_part [expr {int(rand() * 9999)}]
            set unique_id [format "%08x_%04d" $timestamp $random_part]
            set branch_key "${branch_type}_${unique_id}"
            incr attempts
        }
    }

    CBFLOW_INFO "Generated unique branch key: $branch_key"
    return $branch_key
}

proc ::CBFlow::NodeManagement::BranchOps::create_branch_metadata {branch_key branch_name {description ""}} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array

    set flow_array(branch_keys,$branch_key,name) $branch_name
    set flow_array(branch_keys,$branch_key,created_by) [exec whoami]
    set flow_array(branch_keys,$branch_key,created_date) [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]

    if {$description ne ""} {
        set flow_array(branch_keys,$branch_key,description) $description
    }

    CBFLOW_INFO "Created branch metadata for: $branch_key"
    return true
}

proc ::CBFlow::NodeManagement::BranchOps::assign_node_to_branch {node_name branch_key} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array

    if {[info exists flow_array(stages,$node_name,type)]} {
        set flow_array(stages,$node_name,branch_key) $branch_key
        CBFLOW_INFO "Assigned node '$node_name' to branch '$branch_key'"
        return true
    } else {
        CBFLOW_ERROR "Node '$node_name' does not exist"
        return false
    }
}

proc ::CBFlow::NodeManagement::BranchOps::list_branch_keys {} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]

    # Load runtime config to get branch data
    ::CBFlow::NodeManagement::Persistence::load_runtime_config_for_flow $current_flow_type

    upvar #0 $flow_var flow_array

    set branch_keys {}
    if {[array exists flow_array]} {
        foreach key [array names flow_array "branch_keys,*,name"] {
            if {[regexp {branch_keys,([^,]+),name} $key -> branch_key]} {
                lappend branch_keys $branch_key
            }
        }
    }

    return [lsort $branch_keys]
}

proc ::CBFlow::NodeManagement::BranchOps::get_branch_metadata {branch_key} {
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array

    array set metadata {}
    if {[array exists flow_array]} {
        foreach key [array names flow_array "branch_keys,$branch_key,*"] {
            if {[regexp "branch_keys,$branch_key,(\[^,\]+)" $key -> attribute]} {
                set metadata($attribute) $flow_array($key)
            }
        }
    }

    return [array get metadata]
}

# ┌─ Create Branch ──────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::BranchOps::create_branch {start_node {dependency_node ""} {branch_key ""} {branch_name ""}} {
    global flow

    ::CBFlow::Utilities::RunStatus::initialize_global_access $::env(CBFLOW_RUN_DIR)
    set run_type "node"
    if {[info exists flow(run_type)]} {
        set run_type $flow(run_type)
    }

    if {$run_type eq "flat"} {
        CBFLOW_ERROR "create_branch is not allowed in flat mode"
        return false
    }

    # Generate branch key if not provided
    if {$branch_key eq ""} {
        if {[regexp {^([a-zA-Z_]+)} $start_node -> base_type]} {
            set branch_type $base_type
        } else {
            set branch_type "custom"
        }
        set branch_key [generate_unique_branch_key $branch_type]

        if {$branch_name eq ""} {
            set branch_name "Branch from $start_node"
        }
    }

    CBFLOW_INFO "Creating branch with key: $branch_key"
    if {$branch_name ne ""} {
        CBFLOW_INFO "Branch name: $branch_name"
        create_branch_metadata $branch_key $branch_name
    }

    # Extract suffix from start node
    set suffix ""
    set base_name ""
    if {[regexp {^([a-zA-Z_]+)([0-9]+)$} $start_node -> base_name suffix]} {
        CBFLOW_INFO "Detected base name: $base_name, suffix: $suffix"
    } else {
        set base_name $start_node
        # Find next available suffix by checking existing nodes
        set suffix [find_next_available_suffix $base_name]
        CBFLOW_INFO "Using auto-generated suffix: $suffix"
    }

    # Validate base node type (flow_sequence may contain suffixed names like place1)
    set current_flow_type [::CBFlow::NodeManagement::get_current_flow_type]
    set flow_sequence [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $current_flow_type]
    # Strip numeric suffixes from flow_sequence for comparison with base_name
    set base_sequence {}
    foreach node $flow_sequence {
        regsub {[0-9]+$} $node "" stripped
        lappend base_sequence $stripped
    }
    if {[lsearch -exact $base_sequence $base_name] == -1 && [lsearch -exact $flow_sequence $base_name] == -1} {
        CBFLOW_ERROR "Invalid node type: $base_name for flow $current_flow_type"
        return false
    }

    set flow_var [string tolower $current_flow_type]
    upvar #0 $flow_var flow_array

    # Use existing start node as branch point (don't re-create base stages)
    # The start node (e.g., place1) is where the branch forks from - it stays as a base node
    if {![info exists flow_array(stages,$start_node,type)]} {
        # If the start node doesn't exist at all, check if it's a base stage
        # that just isn't tracked in the runtime config
        set is_base_stage [expr {[lsearch -exact $flow_sequence $start_node] != -1}]
        if {$is_base_stage} {
            CBFLOW_INFO "Using existing base stage '$start_node' as branch point"
        } else {
            CBFLOW_INFO "Start node '$start_node' does not exist, creating it first..."

            set start_dependencies {}
            if {$dependency_node ne ""} {
                set start_dependencies [list $dependency_node]
            } else {
                set base_flow [::CBFlow::NodeManagement::get_base_flow_sequence $current_flow_type]
                set start_index_dep [lsearch -exact $base_flow $base_name]
                if {$start_index_dep == -1} {
                    # Try with suffix
                    set start_index_dep [lsearch -exact $base_flow $start_node]
                }
                if {$start_index_dep > 0} {
                    set default_dep [lindex $base_flow [expr $start_index_dep - 1]]
                    set start_dependencies [list $default_dep]
                    CBFLOW_INFO "Using default dependency: $default_dep"
                }
            }

            set result [::CBFlow::NodeManagement::NodeOps::add_stage_internal $base_name $start_node $start_dependencies]
            if {$result eq "false" || $result == 0} {
                CBFLOW_ERROR "Failed to create start node '$start_node'"
                return false
            }
            assign_node_to_branch $start_node $branch_key
            CBFLOW_INFO "✓ Created start node: $start_node"
        }
    } else {
        CBFLOW_INFO "✓ Using existing node '$start_node' as branch point"
    }

    # Get remaining stages
    # For base stages, the type is the base_name; for custom stages, read from flow_array
    if {[info exists flow_array(stages,$start_node,type)]} {
        set start_type $flow_array(stages,$start_node,type)
    } else {
        set start_type $base_name
    }
    set flow_seq [::CBFlow::NodeManagement::get_base_flow_sequence $current_flow_type]
    # Try exact match first, then match ignoring numeric suffixes
    set start_index [lsearch -exact $flow_seq $start_type]
    if {$start_index == -1} {
        # flow_seq may have suffixed names (place1) while start_type is unsuffixed (place)
        set idx 0
        foreach node $flow_seq {
            regsub {[0-9]+$} $node "" stripped
            if {$stripped eq $start_type} {
                set start_index $idx
                break
            }
            incr idx
        }
    }

    if {$start_index == -1} {
        CBFLOW_ERROR "Start node type '$start_type' is not in the standard sequence"
        return false
    }

    set remaining_stages [lrange $flow_seq [expr $start_index + 1] end]

    if {[llength $remaining_stages] == 0} {
        CBFLOW_WARNING "Start node is at the end of the sequence"
        return true
    }

    CBFLOW_INFO "Creating branch starting from: $start_node"

    # Find the next available branch suffix (e.g., if place1 exists, use 2 for branch nodes)
    set branch_suffix [find_next_available_suffix $base_name]

    # Strip existing suffixes from remaining stages to get clean base names
    set remaining_base_stages {}
    foreach stage $remaining_stages {
        regsub {[0-9]+$} $stage "" stripped
        lappend remaining_base_stages $stripped
    }

    CBFLOW_INFO "Will create nodes for: [join $remaining_base_stages {, }]"

    # Create nodes
    set created_nodes {}
    set last_dependency $start_node

    foreach stage_base $remaining_base_stages {
        set new_node_name "${stage_base}${branch_suffix}"

        if {[info exists flow_array(stages,$new_node_name,type)]} {
            CBFLOW_WARNING "Node '$new_node_name' already exists, skipping"
            set last_dependency $new_node_name
            continue
        }

        set dependencies [list $last_dependency]
        CBFLOW_INFO "Creating node: $new_node_name (type: $stage_base, depends on: $last_dependency)"

        set result [::CBFlow::NodeManagement::NodeOps::add_stage_internal $stage_base $new_node_name $dependencies]
        if {$result eq "false" || $result == 0} {
            CBFLOW_ERROR "Failed to create node '$new_node_name'"
            return false
        }

        assign_node_to_branch $new_node_name $branch_key

        lappend created_nodes $new_node_name
        set last_dependency $new_node_name

        CBFLOW_INFO "✓ Created node: $new_node_name"
    }

    # Always save config to persist branch metadata, even if no new nodes were created
    ::CBFlow::NodeManagement::save_flow_config

    if {[llength $created_nodes] > 0} {
        CBFLOW_INFO ""
        CBFLOW_INFO "✓ Successfully created branch with [llength $created_nodes] nodes:"
        foreach node $created_nodes {
            set node_type $flow_array(stages,$node,type)
            set deps $flow_array(stages,$node,dependencies)
            CBFLOW_INFO "  $node \[$node_type\] → depends on: [join $deps {, }]"
        }

        CBFLOW_INFO ""
        CBFLOW_INFO "✓ Branch creation completed"
        CBFLOW_INFO "  Start node: $start_node"
        CBFLOW_INFO "  New nodes: [join $created_nodes { → }]"

        # Regenerate Makefile to include new branch nodes
        CBFLOW_INFO ""
        CBFLOW_INFO "Regenerating Makefile to include new branch targets..."
        regenerate_makefile
    } else {
        CBFLOW_INFO ""
        CBFLOW_INFO "✓ Branch '$branch_name' created (all nodes already exist)"
        CBFLOW_INFO "  Branch key: $branch_key"
    }

    return true
}

# ┌─ List Branches ──────────────────────────────────────────────────────────────┐

proc ::CBFlow::NodeManagement::BranchOps::show_branches {} {
    set branch_keys [list_branch_keys]

    if {[llength $branch_keys] == 0} {
        CBFLOW_INFO "No branches found"
        return 0
    }

    CBFLOW_INFO "Available branches:"
    CBFLOW_INFO "=================="
    foreach branch_key $branch_keys {
        array set metadata [get_branch_metadata $branch_key]
        if {[info exists metadata(name)]} {
            set name $metadata(name)
        } else {
            set name "Unnamed branch"
        }
        if {[info exists metadata(created_date)]} {
            set date $metadata(created_date)
        } else {
            set date "Unknown date"
        }
        CBFLOW_INFO "  $branch_key: $name (created: $date)"
        array unset metadata
    }

    return 0
}
