#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Run Status Script (Refactored)
# Description: Shows detailed status of CBFlow runs with stage flow and dependency validation
# Version: v1.0.0
# Namespace: ::CBFlow::Utilities::RunStatus
# Usage: tclsh run_status_refactored.tcl [options] [run_directory]
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ TCL-First Environment Loading ──────────────────────────────────────────────┐
# TCL-First Environment Loading - Clean and Simple Approach
proc load_tcl_environment {{search_dir "."}} {
    # Look for TCL environment files in priority order
    set env_files [list "$search_dir/.run.cbflow.tcl" "$search_dir/.cbflow.tcl" "$search_dir/../.cbflow.tcl"]

    foreach env_file $env_files {
        if {[file exists $env_file]} {
            if {[catch {source $env_file} error]} {
                puts stderr "ERROR: Failed to source TCL environment file: $error"
                return false
            }
            return true
        }
    }
    return false
}

# Source utils.tcl for logging functions
set script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(UTILS_TCL)] && [file exists $::env(UTILS_TCL)]} {
    source $::env(UTILS_TCL)
} elseif {[file exists "$script_dir/utils.tcl"]} {
    source "$script_dir/utils.tcl"
} else {
    # Define basic logging functions if not available
    proc handle_info {message} { puts "INFO: $message" }
    proc handle_warning {message} { puts "WARNING: $message" }
    proc handle_error {message} { puts stderr "ERROR: $message" }
    proc handle_debug {message} {
        if {[info exists ::env(CBFLOW_DEBUG)] && $::env(CBFLOW_DEBUG) eq "1"} {
            puts "DEBUG: $message"
        }
    }
}

global argc argv argv0

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Utilities::RunStatus {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # Display options
    variable show_details false
    variable show_logs false
    variable watch_mode false

    # Status icons
    variable STATUS_ICONS
    array set STATUS_ICONS {
        "Ready"       "⏳"
        "Running"     "🔄"
        "Complete"    "✅"
        "Error"       "❌"
        "In Progress" "🔨"
        "Unknown"     "❓"
        "Not Started" "⚪"
    }

    # ┌─ Import Global Arrays ────────────────────────────────────────────────────┐
    # Ensure all global configuration arrays are available in this namespace
    proc initialize_global_access {{run_dir ""}} {
        # Load flow configuration and user config to get flat mode settings
        global flow

        # Load flow configuration for flat mode arrays if available
        if {[info exists ::env(FLOW_DIR)]} {
            set flow_config_file "$::env(FLOW_DIR)/config/flow/v1.0.0/flow_config.tcl"
            if {[file exists $flow_config_file]} {
                if {[catch {source $flow_config_file} error]} {
                    # Silently continue if flow config can't be loaded
                } else {
                    # Flow config loaded successfully
                }
            }
        }

        # Try to load consolidated configuration from the run directory
        set config_paths [list]
        if {$run_dir ne ""} {
            lappend config_paths "$run_dir/consolidated_config.tcl"
            lappend config_paths "$run_dir/setup/user_config.tcl"
            lappend config_paths "$run_dir/setup/runtime_flow_config.tcl"
        }
        lappend config_paths "consolidated_config.tcl"
        lappend config_paths "setup/user_config.tcl"
        lappend config_paths "setup/runtime_flow_config.tcl"

        foreach config_file $config_paths {
            if {[file exists $config_file]} {
                if {[catch {source $config_file} error]} {
                    # Silently continue if config can't be loaded
                } else {
                    # Config loaded successfully - continue loading other configs too
                }
            }
        }

        return true
    }

    # ┌─ Common Functions ────────────────────────────────────────────────────────┐
    # Use full namespace paths for clarity
    proc handle_error {message} {
        puts stderr "ERROR: $message"
        return false
    }

    proc handle_warning {message} {
        puts stderr "WARNING: $message"
    }

    proc handle_info {message} {
        puts "INFO: $message"
    }

    proc handle_debug {message} {
        if {[info exists ::env(CBFLOW_DEBUG)] && $::env(CBFLOW_DEBUG) eq "1"} {
            puts "DEBUG: $message"
        }
    }

    # ┌─ Status Analysis Functions ───────────────────────────────────────────────┐

    proc get_status_icon {status} {
        variable STATUS_ICONS
        if {[info exists STATUS_ICONS($status)]} {
            return $STATUS_ICONS($status)
        } else {
            return $STATUS_ICONS(Unknown)
        }
    }

    proc detect_run_status {run_dir} {
        # Check for various status indicators
        set status "Not Started"

        # Check .run.status file
        if {[file exists "$run_dir/.run.status"]} {
            if {[catch {
                set fp [open "$run_dir/.run.status" r]
                set content [string trim [read $fp]]
                close $fp

                if {[string match "*ERROR*" $content]} {
                    set status "Error"
                } elseif {[string match "*COMPLETE*" $content]} {
                    set status "Complete"
                } elseif {[string match "*RUNNING*" $content]} {
                    set status "Running"
                } else {
                    set status "In Progress"
                }
            }]} {
                set status "Unknown"
            }
        } elseif {[file exists "$run_dir/logs"]} {
            # Check log files if no status file
            set log_files [glob -nocomplain "$run_dir/logs/*.log"]
            if {[llength $log_files] > 0} {
                set status "In Progress"
            }
        }

        return $status
    }

    proc get_node_status {run_dir node_name {flow_type ""}} {
        # Read status from .run.status file
        set status_file "$run_dir/.run.status"
        if {[file exists $status_file]} {
            if {[catch {open $status_file r} fh]} {
                return "Not Started"
            }

            set status_content [read $fh]
            close $fh

            # Check for stage completion or error in status file
            set lines [split $status_content "\n"]
            set stage_complete false
            set stage_error false
            set subnode_complete 0
            set subnode_error 0

            foreach line $lines {
                # Check for exact stage match
                if {[string match "*${node_name} COMPLETE*" $line]} {
                    set stage_complete true
                }
                if {[string match "*${node_name} ERROR*" $line]} {
                    set stage_error true
                }

                # Check for subnode matches (e.g., place_setup, place_run, etc.)
                if {[string match "*${node_name}_* COMPLETE*" $line]} {
                    incr subnode_complete
                }
                if {[string match "*${node_name}_* ERROR*" $line]} {
                    incr subnode_error
                }
            }

            # Get expected total subnodes if flow_type is provided
            set expected_subnodes {}
            if {$flow_type ne ""} {
                set expected_subnodes [get_expected_subnodes $node_name $flow_type]
            }
            set expected_total [llength $expected_subnodes]

            # Determine status based on findings
            if {$stage_error} {
                return "Error"
            } elseif {$stage_complete} {
                return "Complete"
            } elseif {$subnode_error > 0} {
                return "Error"
            } elseif {$subnode_complete > 0} {
                # Use expected total if available, otherwise fall back to old logic
                if {$expected_total > 0} {
                    if {$subnode_complete < $expected_total} {
                        return "In Progress"
                    } else {
                        return "Complete"
                    }
                } else {
                    # Old logic: assume complete if all found subnodes are complete
                    return "Complete"
                }
            }
        }

        # Fall back to checking work directories if no status file
        set node_work_dirs [glob -nocomplain "$run_dir/work/*/*/$node_name"]
        if {[llength $node_work_dirs] == 0} {
            return "Not Started"
        }

        # Check the most recent node directory
        set node_dir [lindex [lsort -decreasing $node_work_dirs] 0]

        # Check for completion markers
        if {[file exists "$node_dir/complete"]} {
            return "Complete"
        }

        # Check for error markers
        if {[file exists "$node_dir/error"] || [file exists "$node_dir/failed"]} {
            return "Error"
        }

        # Check for running markers
        if {[file exists "$node_dir/running"] || [file exists "$node_dir/lock"]} {
            return "Running"
        }

        # Check for any activity (logs, results)
        if {[llength [glob -nocomplain "$node_dir/logs/*"]] > 0} {
            return "In Progress"
        }

        return "Ready"
    }

    proc analyze_run_directory {run_dir} {
        # Parse run directory name to extract flow info
        set dir_name [file tail $run_dir]

        set phase "UNKNOWN"
        set flow_type "UNKNOWN"
        set run_name "UNKNOWN"

        # Pattern: P0_run_SYNTH_simple_test_001
        if {[regexp {([^_]+)_run_([^_]+)_(.+)$} $dir_name -> extracted_phase extracted_flow extracted_name]} {
            set phase $extracted_phase
            set flow_type $extracted_flow
            set run_name $extracted_name
        }

        return [list $phase $flow_type $run_name]
    }

    proc get_base_flow_nodes {flow_type} {
        # Return base flow stages - check for flat mode first

        # Check if we're in flat mode by looking for run_type configuration
        set run_type "node"  ; # default
        if {[info exists ::flow(run_type)]} {
            set run_type $::flow(run_type)
        }

        # If flat mode, return the flat mode step list
        if {$run_type eq "flat"} {
            return [get_flat_mode_nodes $flow_type]
        }

        # Load stages dynamically from configuration files
        return [load_flow_stages_from_config $flow_type]
    }

    proc load_flow_stages_from_config {flow_type} {
        # Dynamically load stages from already loaded configuration
        set flow_type_lower [string tolower $flow_type]

        # Check if the flow-specific array already exists (should be loaded by CBFlow environment)
        global ${flow_type_lower}
        if {[info exists ${flow_type_lower}(stages)]} {
            set flow_array_name ${flow_type_lower}
            return [set ${flow_array_name}(stages)]
        }

        # If not loaded yet, try to load from environment variables (no hardcoding)
        if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
            set config_path "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/${flow_type}_config.tcl"

            if {[file exists $config_path]} {
                if {[catch {source $config_path} error] == 0} {
                    # Check if the flow-specific array exists and has stages
                    if {[info exists ${flow_type_lower}(stages)]} {
                        set flow_array_name ${flow_type_lower}
                        return [set ${flow_array_name}(stages)]
                    }
                }
            }
        }

        # Final fallback: return generic stages
        handle_warning "Could not load stages for flow type $flow_type from configuration, using generic fallback"
        return {inputs processing outputs}
    }

    proc get_flat_mode_nodes {flow_type} {
        # Return flat mode node list: data_nodes + merged_execution_node + data_nodes
        global flat_data_sequence flat_merged_nodes

        set flow_key [string toupper $flow_type]
        set data_nodes {}
        set merged_node_name ""

        if {[info exists ::flat_data_sequence($flow_key)]} {
            set data_nodes $::flat_data_sequence($flow_key)
        } else {
            # Fallback: Use expected flat mode structure for FP
            if {$flow_key eq "FP"} {
                set data_nodes {inputs export_data release_data}
            }
        }
        if {[info exists ::flat_merged_nodes($flow_key)]} {
            set merged_node_name $::flat_merged_nodes($flow_key)
        } else {
            # Fallback: Use expected merged node name for FP
            if {$flow_key eq "FP"} {
                set merged_node_name "floorplan_merged"
            } else {
                set merged_node_name "${flow_key}_merged"
            }
        }

        # Build flat mode step list
        set flat_step_list {}

        # Add initial data nodes (e.g., inputs)
        foreach node $data_nodes {
            if {$node eq "inputs"} {
                lappend flat_step_list $node
            }
        }

        # Add the merged execution node
        if {$merged_node_name ne ""} {
            lappend flat_step_list $merged_node_name
        }

        # Add final data nodes (e.g., export_data, release_data)
        foreach node $data_nodes {
            if {$node ne "inputs"} {
                lappend flat_step_list $node
            }
        }

        return $flat_step_list
    }

    proc get_expected_subnodes {stage_name flow_type} {
        # Return the expected subnodes for each stage based on flow type and stage
        # Reads from config files - no hardcoded node definitions

        set flow_type_lower [string tolower $flow_type]
        set flow_type_upper [string toupper $flow_type]

        # Extract base stage type from stage name (e.g., "place1" -> "place")
        set base_stage $stage_name
        if {[regexp {^(.+?)(\d+)$} $stage_name -> base suffix]} {
            set base_stage $base
        }

        # Try to get subnodes from the flow's config array
        # Check if the flow array exists and has subnodes defined
        if {[info exists ::${flow_type_lower}] && [array exists ::${flow_type_lower}]} {
            upvar #0 $flow_type_lower flow_config

            # First try exact stage name
            if {[info exists flow_config(subnodes,$stage_name)]} {
                return $flow_config(subnodes,$stage_name)
            }

            # Then try base stage type
            if {[info exists flow_config(subnodes,$base_stage)]} {
                return $flow_config(subnodes,$base_stage)
            }
        }

        # Fallback: Load the config file if not already loaded
        set config_file ""
        if {[info exists ::env(FLOW_DIR)]} {
            set config_file "$::env(FLOW_DIR)/config/flow/v1.0.0/node_configs/${flow_type_upper}_config.tcl"
        } elseif {[info exists ::env(CONFIG_ROOT)]} {
            set config_file "$::env(CONFIG_ROOT)/flow/v1.0.0/node_configs/${flow_type_upper}_config.tcl"
        }

        if {$config_file ne "" && [file exists $config_file]} {
            # Source the config file to load the array
            if {[catch {uplevel #0 source $config_file} err]} {
                # Config load failed, return default subnodes
                return {setup run validate finish}
            }

            # Try again after loading
            if {[info exists ::${flow_type_lower}] && [array exists ::${flow_type_lower}]} {
                upvar #0 $flow_type_lower flow_config

                if {[info exists flow_config(subnodes,$stage_name)]} {
                    return $flow_config(subnodes,$stage_name)
                }

                if {[info exists flow_config(subnodes,$base_stage)]} {
                    return $flow_config(subnodes,$base_stage)
                }
            }
        }

        # Default fallback for unknown stages
        return {setup run validate finish}
    }

    proc get_custom_nodes {flow_type {run_dir ""}} {
        set flow_type_lower [string tolower $flow_type]
        set custom_nodes {}

        # Get base flow stages for validation
        set base_stages [get_base_flow_nodes $flow_type]

        # Load runtime configuration for custom nodes if it exists
        if {$run_dir ne ""} {
            set runtime_config "$run_dir/setup/runtime_flow_config.tcl"
        } else {
            set runtime_config "setup/runtime_flow_config.tcl"
        }

        if {[file exists $runtime_config]} {
            # Source the runtime config in global scope to ensure arrays are created globally
            if {[catch {uplevel #0 source $runtime_config} error] == 0} {
                # Access the flow-specific array (e.g., pnr array for PNR flow)
                upvar #0 $flow_type_lower flow_array
                if {[array exists flow_array]} {
                    foreach key [array names flow_array "stages,*,type"] {
                        if {[regexp {stages,([^,]+),type} $key -> stage_name]} {
                            # Validate that this is a legitimate custom node (variant of a base stage)
                            if {[is_valid_custom_node $stage_name $base_stages]} {
                                lappend custom_nodes $stage_name
                            }
                        }
                    }
                }
            }
        }

        return $custom_nodes
    }

    proc is_valid_custom_node {node_name base_stages} {
        # Accept any node that's not a base stage
        # If it's defined in runtime config with type and dependencies, it's valid
        if {[lsearch -exact $base_stages $node_name] >= 0} {
            return false  # This is a base stage, not custom
        }

        # All other nodes are considered valid custom nodes
        # The fact that they exist in the runtime config means they're intentionally defined
        return true
    }

    # ┌─ Branch Analysis Functions ───────────────────────────────────────────────┐

    proc get_external_upcones {branch custom_nodes flow_type {run_dir ""}} {
        # Find external dependencies (upcones) for this branch
        # These are dependencies that come from outside the branch
        set immediate_external_deps {}

        foreach node $branch {
            set dependencies [get_node_dependencies $node $flow_type $run_dir]
            foreach dep $dependencies {
                # If dependency is not in this branch and not already found
                if {[lsearch -exact $branch $dep] < 0 && [lsearch -exact $immediate_external_deps $dep] < 0} {
                    lappend immediate_external_deps $dep
                }
            }
        }

        # For each external dependency, trace back to get the complete upcone chain with status
        set complete_upcones {}
        foreach ext_dep $immediate_external_deps {
            set complete_chain_with_status [trace_complete_upcone_with_status $ext_dep $flow_type $run_dir]
            lappend complete_upcones $complete_chain_with_status
        }

        return $complete_upcones
    }

    proc trace_complete_upcone {start_node flow_type {run_dir ""}} {
        # Trace the complete dependency chain back to the root
        set visited {}
        set chain {}
        set current_node $start_node

        while {$current_node ne "" && [lsearch -exact $visited $current_node] < 0} {
            lappend visited $current_node
            lappend chain $current_node

            # Get dependencies of current node (custom nodes)
            set dependencies [get_node_dependencies $current_node $flow_type $run_dir]

            if {[llength $dependencies] == 0} {
                # Check if this is a base flow node and get its dependencies
                set base_deps [get_base_node_dependencies $current_node $flow_type]
                if {[llength $base_deps] > 0} {
                    set current_node [lindex $base_deps 0]
                } else {
                    # No dependencies, we've reached the root
                    break
                }
            } elseif {[llength $dependencies] == 1} {
                # Single dependency, continue tracing
                set current_node [lindex $dependencies 0]
            } else {
                # Multiple dependencies - take the first one
                set current_node [lindex $dependencies 0]
            }
        }

        # Reverse the chain so it goes from root to branch entry point
        return [lreverse $chain]
    }

    proc trace_complete_upcone_with_status {start_node flow_type {run_dir ""}} {
        # Trace the complete dependency chain with status information
        set visited {}
        set chain_with_status {}
        set current_node $start_node

        while {$current_node ne "" && [lsearch -exact $visited $current_node] < 0} {
            lappend visited $current_node

            # Get status for current node
            set node_status [get_node_status $run_dir $current_node $flow_type]
            set status_icon [get_status_icon $node_status]

            # Create formatted entry with status
            lappend chain_with_status "$status_icon $current_node ($node_status)"

            # Get dependencies of current node (custom nodes)
            set dependencies [get_node_dependencies $current_node $flow_type $run_dir]

            if {[llength $dependencies] == 0} {
                # Check if this is a base flow node and get its dependencies
                set base_deps [get_base_node_dependencies $current_node $flow_type]
                if {[llength $base_deps] > 0} {
                    set current_node [lindex $base_deps 0]
                } else {
                    # No dependencies, we've reached the root
                    break
                }
            } elseif {[llength $dependencies] == 1} {
                # Single dependency, continue tracing
                set current_node [lindex $dependencies 0]
            } else {
                # Multiple dependencies - take the first one
                set current_node [lindex $dependencies 0]
            }
        }

        # Reverse the chain so it goes from root to branch entry point
        return [lreverse $chain_with_status]
    }

    proc get_base_node_dependencies {node_name flow_type} {
        # Get dependencies for base flow nodes
        set flow_sequence [get_base_flow_nodes $flow_type]
        set node_index [lsearch -exact $flow_sequence $node_name]

        if {$node_index > 0} {
            # Return the previous node in the sequence
            return [list [lindex $flow_sequence [expr $node_index - 1]]]
        } else {
            # This is the root node or not found
            return {}
        }
    }

    proc get_node_dependencies {node_name flow_type {run_dir ""}} {
        set flow_type_lower [string tolower $flow_type]
        set dependencies {}

        # Load runtime configuration
        if {$run_dir ne ""} {
            set runtime_config "$run_dir/setup/runtime_flow_config.tcl"
        } else {
            set runtime_config "setup/runtime_flow_config.tcl"
        }

        if {[file exists $runtime_config]} {
            if {[catch {uplevel #0 source $runtime_config} error] == 0} {
                upvar #0 $flow_type_lower flow_array
                if {[array exists flow_array]} {
                    if {[info exists flow_array(stages,$node_name,dependencies)]} {
                        set raw_deps $flow_array(stages,$node_name,dependencies)
                        # Handle nested dependency format correctly
                        if {[llength $raw_deps] == 1 && [llength [lindex $raw_deps 0]] == 1} {
                            # Handle {{dep}} or {{{dep}}} format
                            set inner_deps [lindex $raw_deps 0]
                            if {[llength $inner_deps] == 1 && [llength [lindex $inner_deps 0]] == 1} {
                                # {{{dep}}} format
                                set dependencies [lindex [lindex $inner_deps 0] 0]
                            } else {
                                # {{dep}} format
                                set dependencies [lindex $inner_deps 0]
                            }
                        } else {
                            # Handle simple format like "dep1" or multiple deps
                            set dependencies $raw_deps
                        }
                    }
                }
            }
        }

        return $dependencies
    }

    proc build_dependency_graph {custom_nodes flow_type {run_dir ""}} {
        # Build a dependency graph for custom nodes
        array set dep_graph {}

        foreach node $custom_nodes {
            set dependencies [get_node_dependencies $node $flow_type $run_dir]
            set dep_graph($node) $dependencies
        }

        return [array get dep_graph]
    }

    proc identify_branch_chains {custom_nodes flow_type {run_dir ""}} {
        # Group custom nodes by their branch keys instead of dependency chains
        set flow_type_lower [string tolower $flow_type]

        # Load runtime configuration to get branch keys
        if {$run_dir ne ""} {
            set runtime_config "$run_dir/setup/runtime_flow_config.tcl"
        } else {
            set runtime_config "setup/runtime_flow_config.tcl"
        }

        array set branch_groups {}
        array set branch_metadata {}
        array set nodes_without_keys {}

        if {[file exists $runtime_config]} {
            if {[catch {uplevel #0 source $runtime_config} error] == 0} {
                upvar #0 $flow_type_lower flow_array
                if {[array exists flow_array]} {
                    # Group nodes by branch_key
                    foreach node $custom_nodes {
                        if {[info exists flow_array(stages,$node,branch_key)]} {
                            set branch_key $flow_array(stages,$node,branch_key)
                            lappend branch_groups($branch_key) $node
                        } else {
                            # Nodes without branch keys - group as legacy
                            set nodes_without_keys($node) 1
                        }
                    }

                    # Load branch metadata
                    foreach key [array names flow_array "branch_keys,*,name"] {
                        if {[regexp {branch_keys,([^,]+),name} $key -> branch_key]} {
                            set branch_metadata($branch_key) $flow_array($key)
                        }
                    }
                }
            }
        }

        # Build the result as list of branch structures
        set branch_structures {}

        # Add branches with keys (sorted by branch key)
        foreach branch_key [lsort [array names branch_groups]] {
            set nodes_in_branch $branch_groups($branch_key)
            set branch_name ""
            if {[info exists branch_metadata($branch_key)]} {
                set branch_name $branch_metadata($branch_key)
            }

            # Build execution paths within this branch
            set execution_paths [build_execution_paths_for_branch $nodes_in_branch $flow_type $run_dir]

            lappend branch_structures [list \
                "branch_key" $branch_key \
                "branch_name" $branch_name \
                "nodes" $nodes_in_branch \
                "execution_paths" $execution_paths \
            ]
        }

        # Handle nodes without branch keys using legacy method
        if {[array size nodes_without_keys] > 0} {
            set legacy_nodes [array names nodes_without_keys]
            set legacy_chains [identify_legacy_chains $legacy_nodes $flow_type $run_dir]
            foreach chain $legacy_chains {
                lappend branch_structures [list \
                    "branch_key" "legacy" \
                    "branch_name" "Legacy Nodes" \
                    "nodes" $chain \
                    "execution_paths" [list $chain] \
                ]
            }
        }

        return $branch_structures
    }

    proc build_execution_paths_for_branch {nodes flow_type {run_dir ""}} {
        # Build execution paths for nodes within a single branch
        # This finds the dependency relationships between nodes in the same branch
        array set dep_graph {}

        # Build dependency graph for these nodes
        foreach node $nodes {
            set dependencies [get_node_dependencies $node $flow_type $run_dir]
            set dep_graph($node) $dependencies
        }

        # Find root nodes (nodes with no dependencies within this branch)
        set root_nodes {}
        foreach node $nodes {
            set dependencies $dep_graph($node)
            set has_internal_dep false

            foreach dep $dependencies {
                if {[lsearch -exact $nodes $dep] >= 0} {
                    set has_internal_dep true
                    break
                }
            }

            if {!$has_internal_dep} {
                lappend root_nodes $node
            }
        }

        # Build execution paths from each root
        set execution_paths {}
        foreach root $root_nodes {
            set path [build_execution_path_from_node $root $nodes dep_graph]
            if {[llength $path] > 0} {
                lappend execution_paths $path
            }
        }

        # Handle any remaining nodes (shouldn't happen with proper branch keys)
        set processed_nodes {}
        foreach path $execution_paths {
            foreach node $path {
                lappend processed_nodes $node
            }
        }

        foreach node $nodes {
            if {[lsearch -exact $processed_nodes $node] < 0} {
                lappend execution_paths [list $node]
            }
        }

        return $execution_paths
    }

    proc build_execution_path_from_node {start_node all_nodes dep_graph_ref} {
        # Build a single execution path starting from a node
        upvar $dep_graph_ref dep_graph
        set path [list $start_node]
        set current_node $start_node

        while {1} {
            set found_next false

            # Find a node that depends on the current node
            foreach node $all_nodes {
                if {[lsearch -exact $path $node] >= 0} {
                    # Skip already processed nodes
                } elseif {[info exists dep_graph($node)] && [lsearch -exact $dep_graph($node) $current_node] >= 0} {
                    lappend path $node
                    set current_node $node
                    set found_next true
                    break
                }
            }

            if {!$found_next} {
                break
            }
        }

        return $path
    }

    proc identify_legacy_chains {legacy_nodes flow_type {run_dir ""}} {
        # Use the old dependency chain method for nodes without branch keys
        array set dep_graph [build_dependency_graph $legacy_nodes $flow_type $run_dir]

        # Find nodes that depend only on external nodes (branch roots)
        set branch_roots {}
        foreach node $legacy_nodes {
            set dependencies $dep_graph($node)
            set has_custom_dep false

            foreach dep $dependencies {
                if {[lsearch -exact $legacy_nodes $dep] >= 0} {
                    set has_custom_dep true
                    break
                }
            }

            if {!$has_custom_dep} {
                lappend branch_roots $node
            }
        }

        # Build chains from each root using simple path following
        set all_chains {}
        set processed_nodes {}

        foreach root $branch_roots {
            set chain [build_execution_path_from_node $root $legacy_nodes dep_graph]
            if {[llength $chain] > 0} {
                lappend all_chains $chain
                foreach node $chain {
                    lappend processed_nodes $node
                }
            }
        }

        # Handle remaining nodes
        foreach node $legacy_nodes {
            if {[lsearch -exact $processed_nodes $node] < 0} {
                lappend all_chains [list $node]
            }
        }

        return $all_chains
    }

    proc build_all_chains_from_root {root reverse_deps_ref all_nodes} {
        upvar $reverse_deps_ref reverse_deps

        # Use DFS to find all possible chains from this root
        set all_chains {}

        # Start DFS from root
        set chains_to_explore [list [list $root]]

        while {[llength $chains_to_explore] > 0} {
            set current_chain [lindex $chains_to_explore 0]
            set chains_to_explore [lrange $chains_to_explore 1 end]

            set current_node [lindex $current_chain end]
            set dependents $reverse_deps($current_node)

            if {[llength $dependents] == 0} {
                # End of chain - add to results
                lappend all_chains $current_chain
            } else {
                # Continue chain with each dependent
                foreach dependent $dependents {
                    # Avoid cycles
                    if {[lsearch -exact $current_chain $dependent] < 0} {
                        set new_chain [concat $current_chain [list $dependent]]
                        lappend chains_to_explore $new_chain
                    }
                }
            }
        }

        return $all_chains
    }

    proc get_prerequisite_base_stages {branch flow_type {run_dir ""}} {
        # Find all base flow stages that must complete before this branch can run
        set base_stages [get_base_flow_nodes $flow_type]
        set prerequisite_stages {}

        # Get the precedence order for this flow type
        array set precedence_map {}
        switch $flow_type {
            "PNR" {
                array set precedence_map {
                    inputs 0
                    place 10
                    cts 20
                    cts_opt 25
                    route 30
                    route_opt 35
                    pro 40
                    signoff 50
                    export_data 60
                    release_data 70
                }
            }
        }

        # For each node in the branch, find what base stages it ultimately depends on
        set all_base_deps {}
        foreach node $branch {
            set node_deps [trace_to_base_dependencies $node $flow_type $run_dir]
            foreach dep $node_deps {
                if {[lsearch -exact $all_base_deps $dep] < 0} {
                    lappend all_base_deps $dep
                }
            }
        }

        # Find the highest precedence base dependency to determine what upstream stages are needed
        set max_precedence -1
        foreach dep $all_base_deps {
            set base_type [get_stage_base_type $dep]
            if {[info exists precedence_map($base_type)]} {
                set prec $precedence_map($base_type)
                if {$prec > $max_precedence} {
                    set max_precedence $prec
                }
            }
        }

        # Build prerequisite list: all base stages up to (but not including) the max precedence
        foreach stage $base_stages {
            if {[info exists precedence_map($stage)]} {
                set stage_prec $precedence_map($stage)
                if {$stage_prec < $max_precedence} {
                    lappend prerequisite_stages $stage
                }
            }
        }

        return $prerequisite_stages
    }

    proc trace_to_base_dependencies {node_name flow_type {run_dir ""}} {
        # Recursively trace dependencies until we reach base flow stages
        set base_stages [get_base_flow_nodes $flow_type]
        set base_deps {}
        set visited {}

        trace_dependencies_recursive $node_name $flow_type $run_dir base_stages base_deps visited

        return $base_deps
    }

    proc trace_dependencies_recursive {node_name flow_type run_dir base_stages_ref base_deps_ref visited_ref} {
        upvar $base_stages_ref base_stages
        upvar $base_deps_ref base_deps
        upvar $visited_ref visited

        # Avoid infinite recursion
        if {[lsearch -exact $visited $node_name] >= 0} {
            return
        }
        lappend visited $node_name

        # Get dependencies for this node
        set dependencies [get_node_dependencies $node_name $flow_type $run_dir]

        foreach dep $dependencies {
            # Check if this dependency is literally a base stage name (e.g., "inputs", "cts")
            if {[lsearch -exact $base_stages $dep] >= 0} {
                # This is a literal base stage dependency (like "inputs", "cts")
                if {[lsearch -exact $base_deps $dep] < 0} {
                    lappend base_deps $dep
                }
            } else {
                # This is a custom node (like "place1"), trace its dependencies recursively
                trace_dependencies_recursive $dep $flow_type $run_dir base_stages base_deps visited
            }
        }
    }

    proc get_stage_base_type {stage_name} {
        # Extract base stage type from stage name (e.g., "place1" -> "place", "cts_opt1" -> "cts_opt")
        # Order patterns from most specific to least specific to avoid partial matches
        set base_patterns {
            {^(export_data).*$} {export_data}
            {^(release_data).*$} {release_data}
            {^(route_opt).*$} {route_opt}
            {^(cts_opt).*$} {cts_opt}
            {^(inputs).*$} {inputs}
            {^(place).*$} {place}
            {^(cts).*$} {cts}
            {^(route).*$} {route}
            {^(pro).*$} {pro}
            {^(signoff).*$} {signoff}
            {^(synthesis).*$} {synthesis}
            {^(dft).*$} {dft}
            {^(floorplan).*$} {floorplan}
            {^(powerplan).*$} {powerplan}
        }

        foreach {pattern base} $base_patterns {
            if {[regexp $pattern $stage_name -> matched]} {
                return $matched
            }
        }

        # If no pattern matches, return the stage name itself
        return $stage_name
    }

    proc get_flow_nodes {flow_type {run_dir ""}} {
        # Legacy function - returns combined list for compatibility
        set base_nodes [get_base_flow_nodes $flow_type]
        set custom_nodes [get_custom_nodes $flow_type $run_dir]
        return [concat $base_nodes $custom_nodes]
    }

    proc show_run_status {run_dir} {
        variable show_details
        variable show_logs

        # Load run-specific configuration
        if {![load_tcl_environment $run_dir]} {
            handle_warning "No TCL environment found in $run_dir, using default configuration"
        }

        handle_info "═══════════════════════════════════════════════════════════════"
        handle_info "  CBFlow Run Status"
        handle_info "═══════════════════════════════════════════════════════════════"

        # Analyze run directory
        lassign [analyze_run_directory $run_dir] phase flow_type run_name
        set overall_status [detect_run_status $run_dir]
        set status_icon [get_status_icon $overall_status]

        # Show basic information
        handle_info ""
        handle_info "📁 Run Directory: [file tail $run_dir]"
        handle_info "🏗️  Project Phase: $phase"
        handle_info "⚙️  Flow Type: $flow_type"
        handle_info "🏃 Run Name: $run_name"
        handle_info "📊 Overall Status: $status_icon $overall_status"
        handle_info ""

        # Show timestamps
        if {[file exists $run_dir]} {
            set created_time [clock format [file mtime $run_dir] -format "%Y-%m-%d %H:%M:%S"]
            handle_info "📅 Created: $created_time"
        }

        # Show base flow nodes status
        set base_nodes [get_base_flow_nodes $flow_type]
        if {[llength $base_nodes] > 0} {
            handle_info ""
            handle_info "───────────────────────────────────────────────────────────────"
            # Check if we're in flat mode to display appropriate label
            set run_type "node"
            if {[info exists ::flow(run_type)]} {
                set run_type $::flow(run_type)
            }
            if {$run_type eq "flat"} {
                handle_info "Flow Nodes (flat mode):"
            } else {
                handle_info "Base Flow Nodes:"
            }
            handle_info "───────────────────────────────────────────────────────────────"

            foreach node $base_nodes {
                set node_status [get_node_status $run_dir $node $flow_type]
                set node_icon [get_status_icon $node_status]

                if {$show_details} {
                    # Show detailed node information
                    global NODE_TYPE_DESCRIPTIONS
                    set description ""
                    if {[info exists NODE_TYPE_DESCRIPTIONS($node)]} {
                        set description "- $NODE_TYPE_DESCRIPTIONS($node)"
                    }
                    handle_info "  $node_icon $node $description"
                    handle_info "      Status: $node_status"

                    # Show work directories
                    set work_dirs [glob -nocomplain "$run_dir/work/*/*/$node"]
                    if {[llength $work_dirs] > 0} {
                        handle_info "      Work Dir: [lindex $work_dirs 0]"
                    }
                } else {
                    # Simple format
                    handle_info "  $node_icon $node ($node_status)"
                }
            }
        }

        # Show custom branch nodes status
        set custom_nodes [get_custom_nodes $flow_type $run_dir]
        if {[llength $custom_nodes] > 0} {
            # Group custom nodes into branches
            set branches [identify_branch_chains $custom_nodes $flow_type $run_dir]

            handle_info ""
            handle_info "───────────────────────────────────────────────────────────────"
            handle_info "Custom Branch Nodes:"
            handle_info "───────────────────────────────────────────────────────────────"

            foreach branch_data $branches {
                # Extract branch information from the new structure
                array unset branch_info
                array set branch_info $branch_data

                set branch_key $branch_info(branch_key)
                set branch_name $branch_info(branch_name)
                set nodes_in_branch $branch_info(nodes)
                set execution_paths $branch_info(execution_paths)

                # Display branch header with key and name
                handle_info ""
                if {$branch_name ne ""} {
                    handle_info "🌿 Branch $branch_key: $branch_name"
                } else {
                    handle_info "🌿 Branch $branch_key"
                }

                # Show complete upcone dependencies for this branch
                set complete_upcones [get_external_upcones $nodes_in_branch $custom_nodes $flow_type $run_dir]
                if {[llength $complete_upcones] > 0} {
                    if {[llength $complete_upcones] == 1} {
                        # Single upcone chain with status indicators - line by line
                        set upcone_chain [lindex $complete_upcones 0]
                        handle_info "  🔗 Upcone:"
                        foreach node $upcone_chain {
                            handle_info "    $node"
                        }
                    } else {
                        # Multiple upcone chains with status indicators - line by line
                        handle_info "  🔗 Upcones:"
                        set chain_num 1
                        foreach upcone_chain $complete_upcones {
                            handle_info "    Chain $chain_num:"
                            foreach node $upcone_chain {
                                handle_info "      $node"
                            }
                            incr chain_num
                        }
                    }
                }

                # Show execution path nodes line-by-line with status indicators
                foreach node $nodes_in_branch {
                    set node_status [get_node_status $run_dir $node $flow_type]
                    set node_icon [get_status_icon $node_status]
                    handle_info "    $node_icon $node ($node_status)"
                }
            }
        }

        # Show recent logs if requested
        if {$show_logs} {
            handle_info ""
            handle_info "───────────────────────────────────────────────────────────────"
            handle_info "Recent Log Entries:"
            handle_info "───────────────────────────────────────────────────────────────"

            set log_files [glob -nocomplain "$run_dir/logs/*.log"]
            if {[llength $log_files] > 0} {
                set latest_log [lindex [lsort -decreasing $log_files] 0]
                if {[catch {
                    set fp [open $latest_log r]
                    set lines [split [read $fp] "\n"]
                    close $fp

                    # Show last 10 lines
                    set start [expr {max(0, [llength $lines] - 10)}]
                    for {set i $start} {$i < [llength $lines]} {incr i} {
                        set line [lindex $lines $i]
                        if {[string trim $line] ne ""} {
                            handle_info "  $line"
                        }
                    }
                }]} {
                    handle_info "  (Unable to read log file)"
                }
            } else {
                handle_info "  No log files found"
            }
        }

        handle_info ""
    }

    # ┌─ Argument Parsing Functions ──────────────────────────────────────────────┐

    proc parse_args {argc argv} {
        variable show_details
        variable show_logs
        variable watch_mode

        set run_dir ""

        for {set i 0} {$i < $argc} {incr i} {
            set arg [lindex $argv $i]
            switch -- $arg {
                "-d" - "--details" { set show_details true }
                "-l" - "--logs" { set show_logs true }
                "-w" - "--watch" { set watch_mode true }
                "-h" - "--help" - "help" {
                    show_help
                    exit 0
                }
                default {
                    if {$run_dir eq ""} {
                        set run_dir $arg
                    } else {
                        handle_error "Multiple run directories specified"
                        exit 1
                    }
                }
            }
        }

        # Default to current directory if no run directory specified
        if {$run_dir eq ""} {
            set run_dir "."
        }

        return $run_dir
    }

    # ┌─ Main Status Display Function ────────────────────────────────────────────┐

    proc run_status_monitor {run_dir} {
        variable watch_mode

        if {![file exists $run_dir]} {
            handle_error "Run directory not found: $run_dir"
            return false
        }

        if {![file isdirectory $run_dir]} {
            handle_error "Path is not a directory: $run_dir"
            return false
        }

        if {$watch_mode} {
            handle_info "Watch mode enabled - Press Ctrl+C to exit"
            while {true} {
                # Clear screen in watch mode
                puts "\033\[2J\033\[H"
                show_run_status $run_dir
                handle_info "Refreshing every 10 seconds... (Ctrl+C to exit)"
                after 10000
            }
        } else {
            show_run_status $run_dir
        }

        return true
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Run Status (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] \\[options\\] \\[run_directory\\]"
        puts ""
        puts "Arguments:"
        puts "  run_directory: CBFlow run directory (default: current directory)"
        puts ""
        puts "Options:"
        puts "  -d, --details    Show detailed node information"
        puts "  -l, --logs       Show recent log entries"
        puts "  -w, --watch      Watch mode (auto-refresh every 10s)"
        puts "  -h, --help       Show this help message"
        puts ""
        puts "Description:"
        puts "  Shows detailed status of CBFlow runs with node flow and dependency validation"
        puts ""
        puts "Examples:"
        puts "  tclsh run_status_refactored.tcl"
        puts "  tclsh run_status_refactored.tcl -d -l P0_run_SYNTH_test_001"
        puts "  tclsh run_status_refactored.tcl -w"
        puts ""
    }

    proc main {argc argv} {
        # Parse command line arguments first to get run directory
        set run_dir [parse_args $argc $argv]

        # Ensure global arrays are accessible with run directory
        if {![initialize_global_access $run_dir]} {
            return 1
        }

        # Run the status monitor
        if {[run_status_monitor $run_dir]} {
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
    exit [::CBFlow::Utilities::RunStatus::main $argc $argv]
}