#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Node Management - Main Dispatcher
# Description: Slim entry point that dispatches to modular components
# Version: v2.0.0
# Usage: tclsh manage_node.tcl <command> [options]
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Module Loading ────────────────────────────────────────────────────────────┐

# Get script directory for relative module loading (use unique variable name)
set _manage_node_dir [file dirname [file normalize [info script]]]

# Source common utilities first (includes environment loading)
source "$_manage_node_dir/lib/common.tcl"

# Load CBFlow environment
::CBFlow::NodeManagement::load_tcl_environment

# Load error handling utilities
if {![info exists ::env(SCRIPTS_ROOT)] || ![info exists ::env(UTILITIES_VERSION)]} {
    puts stderr "Error: Required environment variables SCRIPTS_ROOT and UTILITIES_VERSION not found"
    exit 1
}
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/run_status.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/config_loader.tcl"

# Source remaining modules in dependency order
source "$_manage_node_dir/lib/flow_config.tcl"
source "$_manage_node_dir/lib/graph_ops.tcl"
source "$_manage_node_dir/lib/persistence.tcl"
source "$_manage_node_dir/lib/node_ops.tcl"
source "$_manage_node_dir/lib/branch_ops.tcl"

# ┌─ Global Variables ──────────────────────────────────────────────────────────┐
global flow project tech team logo directory
global runtime tools output
global argc argv argv0

# ┌─ Command Dispatcher ────────────────────────────────────────────────────────┐

namespace eval ::CBFlow::NodeManagement::Dispatcher {
    variable version "v2.0.0"

    proc show_help {} {
        variable version
        puts "CBFlow Node Management (Modular v$version)"
        puts "Usage: tclsh [info script] <command> \[options\]"
        puts ""
        puts "Commands:"
        puts "  list                                                      List all nodes"
        puts "  graph                                                     Show dependency graph"
        puts "  validate                                                  Validate node configuration"
        puts "  -add -node <name> -node_type <type> -dep <deps>          Add new node"
        puts "  -delete -node <name>                                      Delete existing node"
        puts "  -delete_branch -node <start_node>                        Delete entire branch"
        puts "  -create_branch -node <node> \[-dep <dep>\] \[-branch_key <key>\] \[-branch_name <name>\]"
        puts "                                                            Create branch from node"
        puts "  -list_branches                                            List all branches"
        puts "  save_local                                                Save configuration"
        puts "  load_local                                                Load configuration"
        puts "  help                                                      Show this help"
        puts ""
        puts "Examples:"
        puts "  tclsh [info script] list"
        puts "  tclsh [info script] graph"
        puts "  tclsh [info script] -add -node synthesis1 -node_type synthesis -dep inputs"
        puts "  tclsh [info script] -create_branch -node place1 -branch_name \"Custom Branch\""
        puts "  tclsh [info script] -delete_branch -node place1"
        puts ""
    }

    proc parse_args {argc argv} {
        # Parse command line arguments into a dictionary
        set args {}
        dict set args node ""
        dict set args node_type ""
        dict set args dep ""
        dict set args branch_key ""
        dict set args branch_name ""

        for {set i 1} {$i < $argc} {incr i} {
            set arg [lindex $argv $i]
            switch -- $arg {
                "-node" {
                    incr i
                    if {$i < $argc} {
                        dict set args node [lindex $argv $i]
                    }
                }
                "-node_type" {
                    incr i
                    if {$i < $argc} {
                        dict set args node_type [lindex $argv $i]
                    }
                }
                "-dep" {
                    incr i
                    if {$i < $argc} {
                        set dep_str [lindex $argv $i]
                        if {[string match "*,*" $dep_str]} {
                            set deps [split $dep_str ","]
                        } else {
                            set deps [list $dep_str]
                        }
                        set clean_deps {}
                        foreach dep $deps {
                            lappend clean_deps [string trim $dep]
                        }
                        dict set args dep $clean_deps
                    }
                }
                "-branch_key" {
                    incr i
                    if {$i < $argc} {
                        dict set args branch_key [lindex $argv $i]
                    }
                }
                "-branch_name" {
                    incr i
                    if {$i < $argc} {
                        dict set args branch_name [lindex $argv $i]
                    }
                }
            }
        }

        return $args
    }

    proc validate_node_type_for_add {node_type flow_type} {
        # Validate node type against current flow
        global flow

        ::CBFlow::Utilities::RunStatus::initialize_global_access $::env(CBFLOW_RUN_DIR)

        set run_type "node"
        if {[info exists flow(run_type)]} {
            set run_type $flow(run_type)
        }

        if {$run_type eq "flat"} {
            set valid_flat_nodes [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $flow_type]

            set blocked_execution_nodes [::CBFlow::Config::get_execution_nodes $flow_type]

            if {[lsearch -exact $blocked_execution_nodes $node_type] != -1} {
                puts stderr "\u274C \[CBFlow_ERROR\] In flat mode, individual execution nodes are not allowed"
                CBFLOW_ERROR "Cannot add individual execution node '$node_type' in flat mode"
                return false
            }

            if {[lsearch -exact $valid_flat_nodes $node_type] == -1} {
                CBFLOW_ERROR "Invalid node type: $node_type for flow $flow_type (flat mode)"
                return false
            }
        } else {
            set flow_sequence [::CBFlow::Utilities::RunStatus::get_base_flow_nodes $flow_type]
            # Strip numeric suffixes for comparison (flow_sequence may have place1, cts1, etc.)
            set base_sequence {}
            foreach node $flow_sequence {
                regsub {[0-9]+$} $node "" stripped
                lappend base_sequence $stripped
            }
            if {[lsearch -exact $flow_sequence $node_type] == -1 && [lsearch -exact $base_sequence $node_type] == -1} {
                set sorted_types [lsort -unique $base_sequence]
                puts stderr ""
                puts stderr "  ERROR: Invalid node type '$node_type' for $flow_type flow"
                puts stderr ""
                puts stderr "  Valid node types for $flow_type:"
                foreach vt $sorted_types {
                    puts stderr "    - $vt"
                }
                puts stderr ""
                puts stderr "  Example:"
                set first_type [lindex $sorted_types 0]
                set last_type [lindex $sorted_types end]
                puts stderr "    cbflow run add-node --node ${first_type}2 --type $first_type --dep $last_type"
                puts stderr ""
                return false
            }
        }

        return true
    }

    proc main {argc argv} {
        # Validate environment first
        if {![::CBFlow::NodeManagement::validate_environment]} {
            return 1
        }

        if {$argc == 0} {
            show_help
            return 1
        }

        set command [lindex $argv 0]
        set args [parse_args $argc $argv]

        switch -- $command {
            "help" - "--help" - "-h" {
                show_help
                return 0
            }

            "list" {
                return [expr {[::CBFlow::NodeManagement::NodeOps::list_current_nodes] ? 0 : 1}]
            }

            "graph" {
                return [::CBFlow::NodeManagement::Graph::show_graph]
            }

            "validate" {
                return [::CBFlow::NodeManagement::Graph::validate]
            }

            "-add" {
                set node_name [dict get $args node]
                set node_type [dict get $args node_type]
                set dependencies [dict get $args dep]

                if {$node_name eq ""} {
                    CBFLOW_ERROR "Node name is required (-node parameter)"
                    return 1
                }
                if {$node_type eq ""} {
                    CBFLOW_ERROR "Node type is required (-node_type parameter)"
                    return 1
                }

                set flow_type [::CBFlow::NodeManagement::get_current_flow_type]
                if {![validate_node_type_for_add $node_type $flow_type]} {
                    return 1
                }

                set result [::CBFlow::NodeManagement::NodeOps::add_stage_internal $node_type $node_name $dependencies]
                if {$result eq "duplicate"} {
                    CBFLOW_INFO "No changes made - node already exists"
                    return 0
                } elseif {$result} {
                    ::CBFlow::NodeManagement::save_flow_config
                    CBFLOW_INFO "Successfully added node: $node_name"
                    return 0
                } else {
                    CBFLOW_ERROR "Failed to add node: $node_name"
                    return 1
                }
            }

            "-delete" {
                set node_name [dict get $args node]
                if {$node_name eq ""} {
                    CBFLOW_ERROR "Node name is required (-node parameter)"
                    return 1
                }

                if {[::CBFlow::NodeManagement::NodeOps::remove_stage $node_name]} {
                    CBFLOW_INFO "Successfully deleted node: $node_name"
                    return 0
                } else {
                    CBFLOW_ERROR "Failed to delete node: $node_name"
                    return 1
                }
            }

            "-delete_branch" {
                set node_name [dict get $args node]
                if {$node_name eq ""} {
                    CBFLOW_ERROR "Node name is required (-node parameter)"
                    return 1
                }

                if {[::CBFlow::NodeManagement::NodeOps::delete_branch $node_name]} {
                    CBFLOW_INFO "Successfully deleted branch starting from: $node_name"
                    return 0
                } else {
                    CBFLOW_ERROR "Failed to delete branch from: $node_name"
                    return 1
                }
            }

            "-create_branch" {
                set node_name [dict get $args node]
                set dependency [dict get $args dep]
                set branch_key [dict get $args branch_key]
                set branch_name [dict get $args branch_name]

                if {$node_name eq ""} {
                    CBFLOW_ERROR "Node name is required (-node parameter)"
                    return 1
                }

                # Handle dep as list or string
                if {[llength $dependency] == 1} {
                    set dependency [lindex $dependency 0]
                } elseif {[llength $dependency] == 0} {
                    set dependency ""
                }

                if {[::CBFlow::NodeManagement::BranchOps::create_branch $node_name $dependency $branch_key $branch_name]} {
                    return 0
                } else {
                    return 1
                }
            }

            "-list_branches" {
                return [::CBFlow::NodeManagement::BranchOps::show_branches]
            }

            "save_local" {
                if {[::CBFlow::NodeManagement::save_flow_config]} {
                    CBFLOW_INFO "Local configuration saved successfully"
                    return 0
                } else {
                    CBFLOW_ERROR "Failed to save local configuration"
                    return 1
                }
            }

            "load_local" {
                if {[::CBFlow::NodeManagement::Persistence::load_runtime_config]} {
                    CBFLOW_INFO "Local configuration loaded successfully"
                    return 0
                } else {
                    CBFLOW_WARNING "No local configuration file found"
                    return 1
                }
            }

            default {
                CBFLOW_ERROR "Unknown command: $command"
                show_help
                return 1
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

if {[info script] eq $argv0} {
    exit [::CBFlow::NodeManagement::Dispatcher::main $argc $argv]
}
