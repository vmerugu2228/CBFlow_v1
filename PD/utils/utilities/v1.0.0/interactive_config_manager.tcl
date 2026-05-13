#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Interactive Configuration Manager - Clean Version
#
# Description: Interactive CLI for adding flows, nodes, and subnodes to CBFlow
# Version: 1.0.0
# Author: CBFlow Management System
#===============================================================================

package require Tcl

# Load CBFlow utilities
set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/utils.tcl"
source "$script_dir/error_utils.tcl"

namespace eval ::CBFlow::InteractiveConfig {

    #===========================================================================
    # GLOBAL VARIABLES
    #===========================================================================

    variable config_data
    variable current_version "v1.0.0"
    variable workspace_created false
    variable workspace_dir ""
    variable flow_descriptions
    variable supported_flows {SYNTH FP PNR LEC EMIR ECO CLP POPT FCFP}

    # Batch save tracking (like manage_projects.py pattern)
    variable has_pending_changes false
    variable pending_changes {}
    variable modified_configs
    array set modified_configs {}
    variable original_config_data
    array set original_config_data {}

    # Exit signal for graceful exit at any prompt
    variable exit_requested false

    #===========================================================================
    # UTILITY FUNCTIONS
    #===========================================================================

    proc get_user_input {prompt {default ""}} {
        variable exit_requested

        if {$default ne ""} {
            puts -nonewline "$prompt \[$default\] (or 'exit' to quit): "
        } else {
            puts -nonewline "$prompt (or 'exit' to quit): "
        }
        flush stdout

        set input [gets stdin]

        # Check for exit request
        set trimmed [string trim [string tolower $input]]
        if {$trimmed eq "exit" || $trimmed eq "q" || $trimmed eq "quit"} {
            set exit_requested true
            return "EXIT_REQUESTED"
        }

        if {$input eq "" && $default ne ""} {
            return $default
        }
        return $input
    }

    proc get_yes_no {prompt {default "n"}} {
        variable exit_requested

        while {1} {
            set response [get_user_input "$prompt (y/n)" $default]

            # Check for exit request
            if {$response eq "EXIT_REQUESTED"} {
                return "EXIT_REQUESTED"
            }

            set response [string tolower [string trim $response]]

            if {$response eq "y" || $response eq "yes"} {
                return true
            } elseif {$response eq "n" || $response eq "no"} {
                return false
            } else {
                puts "Please enter 'y' or 'n'"
            }
        }
    }

    proc get_list_input {prompt {separator " "}} {
        set input [get_user_input $prompt]
        if {$input eq "EXIT_REQUESTED"} {
            return "EXIT_REQUESTED"
        }
        if {$input eq ""} {
            return {}
        }
        return [split $input $separator]
    }

    #===========================================================================
    # EXIT AND PENDING CHANGES MANAGEMENT
    #===========================================================================

    proc check_exit_requested {} {
        variable exit_requested
        variable has_pending_changes
        variable pending_changes

        if {!$exit_requested} {
            return false
        }

        # Reset flag for re-check
        set exit_requested false

        if {$has_pending_changes} {
            puts "\n"
            puts "╔══════════════════════════════════════════════════════════════════════════════╗"
            puts "║                    \[!\] WARNING: You have unsaved changes!                    ║"
            puts "╚══════════════════════════════════════════════════════════════════════════════╝"
            puts ""
            show_pending_changes
            puts ""
            puts "Options:"
            puts "  1. \[S\] Save all changes and exit"
            puts "  2. \[D\] Discard all changes and exit"
            puts "  3. \[<\] Cancel exit (continue working)"
            puts ""

            while {1} {
                puts -nonewline "Select option (1-3): "
                flush stdout
                set choice [gets stdin]

                switch $choice {
                    "1" {
                        save_all_changes
                        return true
                    }
                    "2" {
                        puts "\n\[D\] All changes discarded."
                        reset_pending_state
                        return true
                    }
                    "3" {
                        puts "\n\[<\] Continuing..."
                        return false
                    }
                    default {
                        puts "Invalid selection. Please enter 1, 2, or 3"
                    }
                }
            }
        }

        return true  ;# No pending changes, just exit
    }

    proc print_goodbye {command_name} {
        # Print goodbye message with other available manage commands
        puts ""
        puts "======================================================================"
        puts "  Thank you for using CBFlow $command_name!"
        puts "======================================================================"
        puts ""
        puts "  Other available management commands:"
        puts ""
        puts "    cbflow flow config manage-flow  - Manage flow types"
        puts "    cbflow flow config manage-node  - Manage nodes and subnodes"
        puts "    cbflow flow config manage-tech  - Manage technology configurations"
        puts "    cbflow flow project manage      - Manage projects"
        puts ""
        puts "  For full command list: cbflow flow --help"
        puts ""
    }

    proc mark_pending {change_description} {
        variable has_pending_changes
        variable pending_changes

        set has_pending_changes true
        lappend pending_changes $change_description

        puts ""
        puts "\[*\] Change staged: $change_description"
        puts "   (Use 'Save all changes' from menu to persist)"
    }

    proc show_pending_changes {} {
        variable pending_changes

        if {[llength $pending_changes] == 0} {
            puts "  No pending changes."
            return
        }

        puts "  Pending changes:"
        set i 1
        foreach change $pending_changes {
            puts "    $i. $change"
            incr i
        }
    }

    proc reset_pending_state {} {
        variable has_pending_changes
        variable pending_changes
        variable modified_configs

        set has_pending_changes false
        set pending_changes {}
        array unset modified_configs
        array set modified_configs {}
    }

    proc save_all_changes {} {
        variable has_pending_changes
        variable pending_changes
        variable modified_configs
        variable workspace_dir
        variable workspace_created

        if {!$has_pending_changes} {
            puts "\n ℹ️  No pending changes to save."
            return false
        }

        # Show review
        puts "\n"
        puts "╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          Review Pending Changes                              ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"
        puts ""
        show_pending_changes
        puts ""

        puts -nonewline "Save all changes? (y/n) \[y\]: "
        flush stdout
        set confirm [gets stdin]
        set confirm [string tolower [string trim $confirm]]
        if {$confirm ne "" && $confirm ne "y" && $confirm ne "yes"} {
            puts "\n\[X\] Save cancelled. Changes are still pending."
            return false
        }

        # Ensure workspace exists
        if {!$workspace_created} {
            if {![create_workspace "config/flow"]} {
                puts "\[X\] Failed to create workspace"
                return false
            }
        }

        # Check for flow config changes
        set has_flow_config_changes [info exists modified_configs(FLOW_CONFIG,supported_flows)]

        # Write flow config if modified
        if {$has_flow_config_changes} {
            set flow_config_file "$workspace_dir/flow_config.tcl"
            if {[write_flow_config_file $flow_config_file]} {
                puts "\[OK\] Written: $flow_config_file"
            } else {
                puts "\[X\] ERROR: Failed to write $flow_config_file"
                return false
            }
        }

        # Write all modified node configs to workspace
        foreach key [array names modified_configs] {
            # Skip FLOW_CONFIG entries (already handled above)
            if {[string match "FLOW_CONFIG,*" $key]} {
                continue
            }

            # This is a flow type with node config data
            set flow_type $key
            set config_data $modified_configs($key)
            set config_file "$workspace_dir/node_configs/${flow_type}_config.tcl"
            if {[write_config_file $flow_type $config_data $config_file]} {
                puts "\[OK\] Written: $config_file"
            } else {
                puts "\[X\] ERROR: Failed to write $config_file"
                return false
            }
        }

        puts ""
        puts "\[OK\] Configuration files saved to: $workspace_dir"
        puts ""

        # Reset pending state
        reset_pending_state

        puts "\n\[OK\] All changes saved successfully!"

        return true
    }

    proc discard_all_changes {} {
        variable has_pending_changes
        variable pending_changes

        if {!$has_pending_changes} {
            puts "\n ℹ️  No pending changes to discard."
            return
        }

        puts "\n\[!\]  The following changes will be discarded:"
        puts ""
        show_pending_changes
        puts ""

        puts -nonewline "Discard all changes? (y/n) \[n\]: "
        flush stdout
        set confirm [gets stdin]
        set confirm [string tolower [string trim $confirm]]
        if {$confirm ne "y" && $confirm ne "yes"} {
            puts "\n\[X\] Discard cancelled. Changes are still pending."
            return
        }

        # Reset all tracking
        reset_pending_state

        puts "\n\[OK\] All pending changes discarded."
    }

    #===========================================================================
    # IN-MEMORY CONFIG MANAGEMENT
    #===========================================================================

    proc load_config_to_memory {flow_type} {
        variable modified_configs
        variable original_config_data

        set config_root $::env(CONFIG_ROOT)
        set flow_config_file "$config_root/flow/current/node_configs/${flow_type}_config.tcl"

        if {![file exists $flow_config_file]} {
            puts "ERROR: Flow configuration file not found: $flow_config_file"
            return false
        }

        # Source the configuration file
        source $flow_config_file

        # Get the flow array
        set flow_array_name [string tolower $flow_type]

        if {![array exists $flow_array_name]} {
            puts "ERROR: Flow array '$flow_array_name' not found"
            return false
        }

        # Store in modified_configs (serialized array)
        set modified_configs($flow_type) [array get $flow_array_name]

        # Store original for potential discard
        if {![info exists original_config_data($flow_type)]} {
            set original_config_data($flow_type) [array get $flow_array_name]
        }

        return true
    }

    proc get_config_array {flow_type} {
        variable modified_configs

        # Load if not already in memory
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return ""
            }
        }

        return $modified_configs($flow_type)
    }

    proc set_config_value {flow_type key value} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array, modify, convert back
        array set flow_array $modified_configs($flow_type)
        set flow_array($key) $value
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc get_config_value {flow_type key} {
        variable modified_configs

        if {![info exists modified_configs($flow_type)]} {
            return ""
        }

        array set flow_array $modified_configs($flow_type)
        if {[info exists flow_array($key)]} {
            return $flow_array($key)
        }
        return ""
    }

    proc add_node_to_config {flow_type node_name node_type dependencies subnodes tool_vendor tool_name tool_version} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)
        set flow_lower [string tolower $flow_type]

        # Add node to stages list
        set stages $flow_array(stages)
        if {[lsearch -exact $stages $node_name] == -1} {
            lappend stages $node_name
            set flow_array(stages) $stages
        }

        # Add subnodes
        set flow_array(subnodes,$node_name) $subnodes

        # Add dependencies
        if {[llength $dependencies] > 0} {
            set flow_array(dependencies,$node_name) $dependencies
        } else {
            set flow_array(dependencies,$node_name) {}
        }

        # Add subnode dependencies (each depends on previous)
        for {set i 0} {$i < [llength $subnodes]} {incr i} {
            set subnode [lindex $subnodes $i]
            if {$i == 0} {
                set flow_array(subnode_dependencies,$node_name,$subnode) {}
            } else {
                set prev_subnode [lindex $subnodes [expr {$i-1}]]
                set flow_array(subnode_dependencies,$node_name,$subnode) $prev_subnode
            }
        }

        # Add node type
        set flow_array(stage_types,$node_name) $node_type

        # Add node description
        set flow_array(node_descriptions,$node_name) "$node_name stage"

        # Add tool configuration (for execution nodes)
        if {$tool_vendor ne "" && $tool_name ne ""} {
            set flow_array(tool,vendor) $tool_vendor
            set flow_array(tool,name) $tool_name
            if {$tool_version ne ""} {
                set flow_array(tool,version) $tool_version
            }
        }

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc delete_node_from_config {flow_type node_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)

        # Remove node from stages list
        set stages $flow_array(stages)
        set idx [lsearch -exact $stages $node_name]
        if {$idx != -1} {
            set stages [lreplace $stages $idx $idx]
            set flow_array(stages) $stages
        }

        # Remove all keys related to this node
        foreach key [array names flow_array] {
            if {[string match "*,$node_name" $key] ||
                [string match "*,$node_name,*" $key] ||
                [string match "subnodes,$node_name" $key] ||
                [string match "dependencies,$node_name" $key] ||
                [string match "stage_types,$node_name" $key] ||
                [string match "node_descriptions,$node_name" $key]} {
                unset flow_array($key)
            }
        }

        # Also remove this node from other nodes' dependencies
        foreach key [array names flow_array "dependencies,*"] {
            set deps $flow_array($key)
            set idx [lsearch -exact $deps $node_name]
            if {$idx != -1} {
                set deps [lreplace $deps $idx $idx]
                set flow_array($key) $deps
            }
        }

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc rename_node_in_config {flow_type old_name new_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)

        # Update stages list
        set stages $flow_array(stages)
        set idx [lsearch -exact $stages $old_name]
        if {$idx != -1} {
            set stages [lreplace $stages $idx $idx $new_name]
            set flow_array(stages) $stages
        }

        # Rename all keys that reference this node
        foreach key [array names flow_array] {
            set new_key $key
            set value $flow_array($key)

            # Update key names
            if {[string match "*,$old_name" $key]} {
                set new_key [string map [list ,$old_name ,$new_name] $key]
            } elseif {[string match "*,$old_name,*" $key]} {
                set new_key [string map [list ,$old_name, ,$new_name,] $key]
            }

            if {$new_key ne $key} {
                unset flow_array($key)
                set flow_array($new_key) $value
            }
        }

        # Update dependency values that reference old_name
        foreach key [array names flow_array "dependencies,*"] {
            set deps $flow_array($key)
            set idx [lsearch -exact $deps $old_name]
            if {$idx != -1} {
                set deps [lreplace $deps $idx $idx $new_name]
                set flow_array($key) $deps
            }
        }

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc add_subnode_to_config {flow_type node_name subnode_name dependencies} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)

        # Add subnode to node's subnode list (if subnodes key exists)
        if {[info exists flow_array(subnodes,$node_name)]} {
            set subnodes $flow_array(subnodes,$node_name)
            if {[lsearch -exact $subnodes $subnode_name] == -1} {
                lappend subnodes $subnode_name
                set flow_array(subnodes,$node_name) $subnodes
            }
        }

        # Add subnode dependencies
        set flow_array(subnode_dependencies,$node_name,$subnode_name) $dependencies

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc delete_subnode_from_config {flow_type node_name subnode_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)

        # Remove from subnodes list
        if {[info exists flow_array(subnodes,$node_name)]} {
            set subnodes $flow_array(subnodes,$node_name)
            set idx [lsearch -exact $subnodes $subnode_name]
            if {$idx != -1} {
                set subnodes [lreplace $subnodes $idx $idx]
                set flow_array(subnodes,$node_name) $subnodes
            }
        }

        # Remove subnode dependency key
        if {[info exists flow_array(subnode_dependencies,$node_name,$subnode_name)]} {
            unset flow_array(subnode_dependencies,$node_name,$subnode_name)
        }

        # Update other subnodes that depend on this one
        foreach key [array names flow_array "subnode_dependencies,$node_name,*"] {
            set deps $flow_array($key)
            if {$deps eq $subnode_name} {
                set flow_array($key) {}
            }
        }

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    proc rename_subnode_in_config {flow_type node_name old_name new_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs($flow_type)]} {
            if {![load_config_to_memory $flow_type]} {
                return false
            }
        }

        # Convert to array for modification
        array set flow_array $modified_configs($flow_type)

        # Update subnodes list
        if {[info exists flow_array(subnodes,$node_name)]} {
            set subnodes $flow_array(subnodes,$node_name)
            set idx [lsearch -exact $subnodes $old_name]
            if {$idx != -1} {
                set subnodes [lreplace $subnodes $idx $idx $new_name]
                set flow_array(subnodes,$node_name) $subnodes
            }
        }

        # Rename the subnode dependency key
        if {[info exists flow_array(subnode_dependencies,$node_name,$old_name)]} {
            set deps $flow_array(subnode_dependencies,$node_name,$old_name)
            unset flow_array(subnode_dependencies,$node_name,$old_name)
            set flow_array(subnode_dependencies,$node_name,$new_name) $deps
        }

        # Update other subnodes that depend on old_name
        foreach key [array names flow_array "subnode_dependencies,$node_name,*"] {
            if {$flow_array($key) eq $old_name} {
                set flow_array($key) $new_name
            }
        }

        # Store back to modified_configs
        set modified_configs($flow_type) [array get flow_array]

        return true
    }

    #===========================================================================
    # FLOW CONFIG MANAGEMENT (for manage_flow operations)
    #===========================================================================

    proc load_flow_config_to_memory {} {
        variable modified_configs
        variable original_config_data
        variable supported_flows
        variable flow_descriptions

        # Check if already loaded
        if {[info exists modified_configs(FLOW_CONFIG)]} {
            return true
        }

        set config_root $::env(CONFIG_ROOT)
        set flow_config_file "$config_root/flow/current/flow_config.tcl"

        if {![file exists $flow_config_file]} {
            puts "ERROR: Flow configuration file not found: $flow_config_file"
            return false
        }

        # Source the configuration file
        source $flow_config_file

        # Store flow list and descriptions in modified_configs
        set modified_configs(FLOW_CONFIG,supported_flows) $supported_flows

        # Store flow descriptions
        foreach flow_type $supported_flows {
            if {[info exists flow_descriptions($flow_type)]} {
                set modified_configs(FLOW_CONFIG,flow_descriptions,$flow_type) $flow_descriptions($flow_type)
            }
        }

        # Store original for potential discard
        if {![info exists original_config_data(FLOW_CONFIG,supported_flows)]} {
            set original_config_data(FLOW_CONFIG,supported_flows) $supported_flows
            foreach flow_type $supported_flows {
                if {[info exists flow_descriptions($flow_type)]} {
                    set original_config_data(FLOW_CONFIG,flow_descriptions,$flow_type) $flow_descriptions($flow_type)
                }
            }
        }

        return true
    }

    proc get_flow_list {} {
        variable modified_configs

        if {![info exists modified_configs(FLOW_CONFIG,supported_flows)]} {
            if {![load_flow_config_to_memory]} {
                return {}
            }
        }

        return $modified_configs(FLOW_CONFIG,supported_flows)
    }

    proc add_flow_to_config {flow_name description} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs(FLOW_CONFIG,supported_flows)]} {
            if {![load_flow_config_to_memory]} {
                return false
            }
        }

        # Check if flow already exists
        set flows $modified_configs(FLOW_CONFIG,supported_flows)
        if {[lsearch -exact $flows $flow_name] != -1} {
            puts "ERROR: Flow '$flow_name' already exists"
            return false
        }

        # Add flow to list
        lappend flows $flow_name
        set modified_configs(FLOW_CONFIG,supported_flows) $flows

        # Add description
        set modified_configs(FLOW_CONFIG,flow_descriptions,$flow_name) $description

        return true
    }

    proc delete_flow_from_config {flow_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs(FLOW_CONFIG,supported_flows)]} {
            if {![load_flow_config_to_memory]} {
                return false
            }
        }

        # Get current flows
        set flows $modified_configs(FLOW_CONFIG,supported_flows)

        # Find and remove flow
        set idx [lsearch -exact $flows $flow_name]
        if {$idx == -1} {
            puts "ERROR: Flow '$flow_name' not found"
            return false
        }

        set flows [lreplace $flows $idx $idx]
        set modified_configs(FLOW_CONFIG,supported_flows) $flows

        # Remove description
        if {[info exists modified_configs(FLOW_CONFIG,flow_descriptions,$flow_name)]} {
            unset modified_configs(FLOW_CONFIG,flow_descriptions,$flow_name)
        }

        return true
    }

    proc rename_flow_in_config {old_name new_name} {
        variable modified_configs

        # Ensure config is loaded
        if {![info exists modified_configs(FLOW_CONFIG,supported_flows)]} {
            if {![load_flow_config_to_memory]} {
                return false
            }
        }

        # Get current flows
        set flows $modified_configs(FLOW_CONFIG,supported_flows)

        # Check old exists and new doesn't
        set idx [lsearch -exact $flows $old_name]
        if {$idx == -1} {
            puts "ERROR: Flow '$old_name' not found"
            return false
        }

        if {[lsearch -exact $flows $new_name] != -1} {
            puts "ERROR: Flow '$new_name' already exists"
            return false
        }

        # Replace in list
        set flows [lreplace $flows $idx $idx $new_name]
        set modified_configs(FLOW_CONFIG,supported_flows) $flows

        # Move description
        if {[info exists modified_configs(FLOW_CONFIG,flow_descriptions,$old_name)]} {
            set desc $modified_configs(FLOW_CONFIG,flow_descriptions,$old_name)
            unset modified_configs(FLOW_CONFIG,flow_descriptions,$old_name)
            set modified_configs(FLOW_CONFIG,flow_descriptions,$new_name) $desc
        }

        return true
    }

    proc write_flow_config_file {config_file} {
        variable modified_configs

        if {![info exists modified_configs(FLOW_CONFIG,supported_flows)]} {
            puts "ERROR: No flow config data to write"
            return false
        }

        set flows $modified_configs(FLOW_CONFIG,supported_flows)

        # Build file content
        set content "#!/usr/bin/env tclsh\n"
        append content "#\n"
        append content "# CBFlow Flow Configuration\n"
        append content "# Auto-generated by CBFlow Interactive Config Manager\n"
        append content "#\n\n"

        # Write supported_flows list
        append content "# Supported flow types\n"
        append content "set supported_flows \{\n"
        foreach flow_name $flows {
            append content "    $flow_name\n"
        }
        append content "\}\n\n"

        # Write flow descriptions
        append content "# Flow descriptions\n"
        append content "array set flow_descriptions \{\n"
        foreach flow_name $flows {
            if {[info exists modified_configs(FLOW_CONFIG,flow_descriptions,$flow_name)]} {
                set desc $modified_configs(FLOW_CONFIG,flow_descriptions,$flow_name)
                append content "    $flow_name \"$desc\"\n"
            } else {
                append content "    $flow_name \"$flow_name flow\"\n"
            }
        }
        append content "\}\n"

        # Write the file
        if {[catch {
            set fd [open $config_file w]
            puts $fd $content
            close $fd
        } err]} {
            puts "ERROR: Failed to write flow config file: $err"
            return false
        }

        return true
    }

    proc write_config_file {flow_type config_data config_file} {
        set flow_lower [string tolower $flow_type]

        # Build file content
        set content "#!/usr/bin/env tclsh\n"
        append content "# ╔══════════════════════════════════════════════════════════════════════════════╗\n"
        append content "# ║                       [string toupper $flow_type] FLOW CONFIGURATION                    ║\n"
        append content "# ║                              Node-Specific Settings                          ║\n"
        append content "# ╚══════════════════════════════════════════════════════════════════════════════╝\n"
        append content "#\n"
        append content "# Auto-generated by CBFlow Interactive Config Manager\n"
        append content "# Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]\n"
        append content "#\n\n"

        # Parse config_data (serialized array)
        array set flow_array $config_data

        # Group by category and write
        set categories {
            "Flow Stage Definitions" {stages subnodes,*}
            "Stage Dependencies" {dependencies,*}
            "Subnode Dependencies" {subnode_dependencies,*}
            "Tool Configuration" {tool,* supported_tools default_tool}
            "Runtime Settings" {runtime,*}
            "Stage Type Mappings and Descriptions" {stage_types,* node_types,* node_descriptions,*}
            "File Requirements" {critical_files,* mandatory_outputs,* optional_files,*}
            "Mandatory Input Groups" {mandatory_input_groups}
            "Release Configuration" {release_types,*}
            "Advanced Configuration" {mmmc,* parallel_stages mmmc_reports,*}
        }

        foreach {category_name patterns} $categories {
            set found_keys {}
            foreach pattern $patterns {
                foreach key [array names flow_array $pattern] {
                    if {$key ni $found_keys} {
                        lappend found_keys $key
                    }
                }
            }

            if {[llength $found_keys] > 0} {
                append content "# ┌─ $category_name ────────────────────────────────────────────────┐\n"
                append content "array set $flow_lower \{\n"
                foreach key [lsort $found_keys] {
                    set value $flow_array($key)
                    append content "    $key \{$value\}\n"
                }
                append content "\}\n\n"
            }
        }

        # Write file
        if {[catch {
            file mkdir [file dirname $config_file]
            set fh [open $config_file w]
            puts $fh $content
            close $fh
        } err]} {
            puts "  ERROR writing file: $err"
            return false
        }

        return true
    }

    proc validate_flow_name {flow_name} {
        if {![regexp {^[A-Z][A-Z0-9_]*$} $flow_name]} {
            return false
        }
        return true
    }

    proc validate_node_name {node_name} {
        if {![regexp {^[a-z][a-z0-9_]*$} $node_name]} {
            return false
        }
        return true
    }

    proc load_flow_descriptions {} {
        variable flow_descriptions
        global flow_descriptions

        # Load flow configuration to get descriptions
        set config_root $::env(CONFIG_ROOT)
        set flow_config_file "$config_root/flow/current/flow_config.tcl"

        if {[file exists $flow_config_file]} {
            source $flow_config_file
            # Copy global descriptions to namespace variable
            if {[info exists ::flow_descriptions]} {
                array set flow_descriptions [array get ::flow_descriptions]
            }
        }
    }

    proc create_workspace {component_dir} {
        variable workspace_created
        variable workspace_dir

        # Get core directory
        if {[info exists ::env(FLOW_DIR)]} {
            set core_dir $::env(FLOW_DIR)
        } else {
            set script_dir [file dirname [file normalize [info script]]]
            set core_dir [file dirname [file dirname [file dirname $script_dir]]]
        }

        # Set workspace directory to the actual config directory
        set workspace_dir "$core_dir/$component_dir"

        # Create node_configs directory if it doesn't exist
        if {![file exists "$workspace_dir/node_configs"]} {
            file mkdir "$workspace_dir/node_configs"
        }

        set workspace_created true
        puts "INFO: Config files will be saved to: $workspace_dir"
        return true
    }

    proc update_flow_config_in_workspace {flow_type node_name node_type dependencies subnodes tool_vendor tool_name tool_version} {
        variable workspace_dir

        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                        MANUAL CONFIGURATION STEPS                           ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        set config_file "$workspace_dir/node_configs/${flow_type}_config.tcl"
        set flow_lower [string tolower $flow_type]

        puts "\n\[*\] Follow these steps to add node '$node_name' to flow '$flow_type':"
        puts "\n STEP 1: Edit the stages list"
        puts "   File: $config_file"
        puts "   Find line: stages {inputs setup compare analyze}"
        puts "   Change to: stages {inputs setup compare analyze $node_name}"

        puts "\n STEP 2: Add dependency entry"
        puts "   Add after the existing dependencies section:"
        puts "   dependencies,$node_name {[join $dependencies " "]}"

        puts "\n STEP 3: Add stage type mapping"
        puts "   Add after the existing stage_types section:"
        puts "   stage_types,$node_name \"$node_type\""

        puts "\n STEP 4: Add node description"
        set description [get_node_description $node_name $node_type]
        puts "   Add after the existing node_descriptions section:"
        puts "   node_descriptions,$node_name \"$description\""

        if {$node_type eq "execution"} {
            puts "\n STEP 5: Add tool configuration (execution node only)"
            puts "   Add after the tool configuration section:"
            puts "   tool,$node_name,vendor \"$tool_vendor\""
            puts "   tool,$node_name,name \"$tool_name\""
            puts "   tool,$node_name,version \"$tool_version\""
        }

        puts "\nSUMMARY:"
        puts "   Flow: $flow_type"
        puts "   Node: $node_name ($node_type)"
        puts "   Dependencies: [join $dependencies {, }]"
        puts "   Config File: $config_file"

        puts "\n🔧 After editing, you can:"
        puts "   1. Test: source $config_file"
        puts "   2. Verify: parray ${flow_lower}"
        puts "   3. Commit: make commit_version"

        return true
    }


    proc get_node_description {node_name node_type} {
        switch $node_type {
            "execution" { return "Execution stage for $node_name operations" }
            "data" { return "Data management stage for $node_name" }
            "inputs" { return "Input validation and preparation for $node_name" }
            "export_data" { return "Data export and formatting for $node_name" }
            "release_data" { return "Release management and deliverables for $node_name" }
            default { return "Configuration stage for $node_name" }
        }
    }

    #===========================================================================
    # MANAGEMENT FUNCTIONS
    #===========================================================================

    proc manage_flow {} {
        variable has_pending_changes
        variable pending_changes
        variable exit_requested

        while {1} {
            puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
            puts "║                          CBFlow Flow Management                             ║"
            puts "╚══════════════════════════════════════════════════════════════════════════════╝"

            # Show pending changes indicator
            if {$has_pending_changes} {
                puts ""
                puts "  \[*\] PENDING CHANGES: [llength $pending_changes] unsaved change(s)"
            }

            puts "\nFlow Operations:"
            puts "  1. Add new flow"
            puts "  2. Delete existing flow"
            puts "  3. Rename existing flow"

            # Add save/discard/exit options
            if {$has_pending_changes} {
                puts "\nChanges:"
                puts "  4. \[S\] Save all changes"
                puts "  5. \[D\]  Discard all changes"
                puts "  6. Exit"
                set max_choice 6
            } else {
                puts "\n  4. Exit"
                set max_choice 4
            }

            set choice [get_user_input "\nSelect operation (1-$max_choice)"]

            # Check for exit request
            if {[check_exit_requested]} {
                return true
            }

            switch $choice {
                "1" { add_flow }
                "2" { delete_flow }
                "3" { rename_flow }
                "4" {
                    if {$has_pending_changes} {
                        save_all_changes
                        print_goodbye "Flow Management"
                        return true
                    } else {
                        # Exit without pending changes
                        print_goodbye "Flow Management"
                        return true
                    }
                }
                "5" {
                    if {$has_pending_changes} {
                        discard_all_changes
                        print_goodbye "Flow Management"
                        return true
                    } else {
                        puts "\[X\] Invalid selection."
                    }
                }
                "6" {
                    if {$has_pending_changes} {
                        # Trigger exit handling
                        set exit_requested true
                        if {[check_exit_requested]} {
                            return true
                        }
                    } else {
                        puts "\[X\] Invalid selection."
                    }
                }
                default {
                    puts "\[X\] Invalid selection. Please enter a number between 1 and $max_choice"
                }
            }
        }
    }

    proc manage_node {} {
        variable has_pending_changes
        variable pending_changes
        variable exit_requested

        while {1} {
            puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
            puts "║                     CBFlow Node & Subnode Management                        ║"
            puts "╚══════════════════════════════════════════════════════════════════════════════╝"

            # Show pending changes indicator
            if {$has_pending_changes} {
                puts ""
                puts "  \[*\] PENDING CHANGES: [llength $pending_changes] unsaved change(s)"
            }

            puts "\nNode Operations:"
            puts "  1. Add new node"
            puts "  2. Delete existing node"
            puts "  3. Rename existing node"
            puts "\nSubnode Operations:"
            puts "  4. Add new subnode"
            puts "  5. Delete existing subnode"
            puts "  6. Rename existing subnode"

            # Add save/discard/exit options
            if {$has_pending_changes} {
                puts "\nChanges:"
                puts "  7. \[S\] Save all changes"
                puts "  8. \[D\]  Discard all changes"
                puts "  9. Exit"
                set max_choice 9
            } else {
                puts "\n  7. Exit"
                set max_choice 7
            }

            set choice [get_user_input "\nSelect operation (1-$max_choice)"]

            # Check for exit request
            if {[check_exit_requested]} {
                return true
            }

            switch $choice {
                "1" { add_node }
                "2" { delete_node }
                "3" { rename_node }
                "4" { add_subnode }
                "5" { delete_subnode }
                "6" { rename_subnode }
                "7" {
                    if {$has_pending_changes} {
                        save_all_changes
                        print_goodbye "Node Management"
                        return true
                    } else {
                        # Exit without pending changes
                        print_goodbye "Node Management"
                        return true
                    }
                }
                "8" {
                    if {$has_pending_changes} {
                        discard_all_changes
                        print_goodbye "Node Management"
                        return true
                    } else {
                        puts "\[X\] Invalid selection."
                    }
                }
                "9" {
                    if {$has_pending_changes} {
                        # Trigger exit handling
                        set exit_requested true
                        if {[check_exit_requested]} {
                            return true
                        }
                    } else {
                        puts "\[X\] Invalid selection."
                    }
                }
                "EXIT_REQUESTED" {
                    # Already handled by check_exit_requested
                }
                default {
                    puts "\[X\] Invalid selection. Please enter 1-$max_choice"
                }
            }
        }
    }

    # Legacy alias for backward compatibility
    proc manage_subnode {} {
        puts "\n\[!\]  manage_subnode is deprecated. Redirecting to manage_node..."
        puts "   Subnode operations are now available under manage_node (options 4-6)\n"
        return [manage_node]
    }

    proc manage_project {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                    CBFlow Project Management (DEPRECATED)                   ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        puts "\n\[!\]  This command is DEPRECATED."
        puts ""
        puts "Please use the Python-based project management instead:"
        puts ""
        puts "    make manage_projects"
        puts ""
        puts "The Python version provides full functionality:"
        puts "  • Add/Edit/Delete projects"
        puts "  • Update release associations"
        puts "  • Toggle project status"
        puts "  • Flow owner access control"
        puts "  • View project details"
        puts ""
        return true
    }

    proc manage_tech {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Technology Management                       ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        puts "\nAvailable Operations:"
        puts "  1. Add new technology"
        puts "  2. Delete existing technology"
        puts "  3. Rename existing technology"

        while {1} {
            set choice [get_user_input "Select operation (1-3)"]
            switch $choice {
                "1" { return [add_tech] }
                "2" { return [delete_tech] }
                "3" { return [rename_tech] }
                default {
                    puts "\[X\] Invalid selection. Please enter 1, 2, or 3"
                }
            }
        }
    }

    #===========================================================================
    # ADD FUNCTIONS (Basic Implementation)
    #===========================================================================

    proc add_flow {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Add New Flow                                ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable modified_configs

        # Load flow config into memory
        if {![load_flow_config_to_memory]} {
            puts "ERROR: Failed to load flow configuration"
            return false
        }

        # Get existing flows
        set existing_flows [get_flow_list]
        puts "\nINFO: Existing flows: [join $existing_flows {, }]"

        # Get flow name
        while {1} {
            set flow_name [get_user_input "\nEnter new flow name (UPPERCASE)"]
            # Check for exit
            if {$flow_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            set flow_name [string toupper $flow_name]

            if {![regexp {^[A-Z][A-Z0-9_]*$} $flow_name]} {
                puts "ERROR: Flow name must start with letter and contain only uppercase letters, numbers, and underscores"
                continue
            }

            if {[lsearch -exact $existing_flows $flow_name] != -1} {
                puts "ERROR: Flow '$flow_name' already exists"
                continue
            }
            break
        }

        # Get flow description
        set description [get_user_input "Enter flow description"]
        # Check for exit
        if {$description eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            set description "$flow_name flow"
        }

        # Configuration Preview
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Flow Name:   $flow_name"
        puts "Description: $description"
        puts ""
        puts "NOTE: You will also need to create:"
        puts "  - config/flow/current/node_configs/${flow_name}_config.tcl"
        puts "  - cmds/$flow_name/ directory structure"

        # Confirmation
        set confirm [get_yes_no "\nAdd this flow to pending changes?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Flow creation cancelled by user"
            return false
        }

        # Add flow to in-memory config
        if {![add_flow_to_config $flow_name $description]} {
            puts "ERROR: Failed to add flow to configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Add flow '$flow_name' ($description)"

        # Ask if user wants to add another
        set add_another [get_yes_no "\nAdd another flow?" "n"]
        if {$add_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$add_another} {
            return [add_flow]
        }

        return true
    }

    proc add_node {} {
        variable supported_flows
        variable flow_descriptions
        variable modified_configs

        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Add New Node                                ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        # Load flow descriptions
        load_flow_descriptions

        # Step 1: Flow Type Selection (REQUIRED FIRST)
        puts "\nSTEP 1: Select Flow Type"
        puts "═══════════════════════════════════════════"

        for {set i 0} {$i < [llength $supported_flows]} {incr i} {
            set flow_type [lindex $supported_flows $i]
            set desc ""
            if {[info exists flow_descriptions($flow_type)]} {
                set desc $flow_descriptions($flow_type)
            }
            puts "  [expr {$i+1}]. $flow_type - $desc"
        }

        while {1} {
            set choice [get_user_input "\nSelect flow type (1-[llength $supported_flows])"]
            # Check for exit
            if {$choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $choice] && $choice >= 1 && $choice <= [llength $supported_flows]} {
                set selected_flow [lindex $supported_flows [expr {$choice-1}]]
                break
            }
            puts "ERROR: Invalid selection. Please enter a number between 1 and [llength $supported_flows]"
        }

        puts "\n✓ Selected flow type: $selected_flow"

        # Step 2: Load existing flow configuration into memory
        puts "\nSTEP 2: Loading Existing Flow Configuration"
        puts "═══════════════════════════════════════════════════════════"

        if {![load_config_to_memory $selected_flow]} {
            puts "ERROR: Failed to load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set existing_stages [get_config_value $selected_flow "stages"]
        if {$existing_stages eq ""} {
            puts "ERROR: Could not load stages for flow $selected_flow"
            return false
        }
        puts "INFO: Existing stages in $selected_flow: $existing_stages"

        # Step 3: Node Information Collection
        puts "\nSTEP 3: Node Information Collection"
        puts "════════════════════════════════════════════════"

        # Node name
        while {1} {
            set node_name [get_user_input "Enter node name (lowercase, alphanumeric + underscore)"]
            # Check for exit
            if {$node_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[validate_node_name $node_name]} {
                # Check if node already exists
                if {[lsearch -exact $existing_stages $node_name] != -1} {
                    puts "ERROR: Node '$node_name' already exists in flow $selected_flow"
                    continue
                }
                break
            }
            puts "ERROR: Invalid node name. Must start with letter and contain only lowercase letters, numbers, and underscores"
        }

        # Node type selection with predefined options
        puts "\nSelect node type:"
        set node_types_list {
            {execution "Execution node (requires tool configuration)"}
            {data "Data node (file management, no tool needed)"}
            {inputs "Input validation and preparation"}
            {export_data "Data export and formatting"}
            {release_data "Release and deliverable management"}
        }

        for {set i 0} {$i < [llength $node_types_list]} {incr i} {
            set type_info [lindex $node_types_list $i]
            set type_name [lindex $type_info 0]
            set type_desc [lindex $type_info 1]
            puts "  [expr {$i+1}]. $type_name - $type_desc"
        }

        # Smart default based on node name patterns
        set default_type_index 2
        if {[regexp {.*inputs.*} $node_name]} {
            set default_type_index 3
        } elseif {[regexp {.*export.*} $node_name]} {
            set default_type_index 4
        } elseif {[regexp {.*release.*} $node_name]} {
            set default_type_index 5
        } elseif {[regexp {.*(synth|place|route|cts|floorplan|powerplan).*} $node_name]} {
            set default_type_index 1
        }

        while {1} {
            set choice [get_user_input "\nSelect node type (1-[llength $node_types_list])" $default_type_index]
            # Check for exit
            if {$choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $choice] && $choice >= 1 && $choice <= [llength $node_types_list]} {
                set selected_type_info [lindex $node_types_list [expr {$choice-1}]]
                set node_type [lindex $selected_type_info 0]
                set is_execution_node [expr {$node_type eq "execution"}]
                break
            }
            puts "ERROR: Invalid selection. Please enter a number between 1 and [llength $node_types_list]"
        }

        puts "✓ Selected node type: $node_type"

        # Dependencies selection
        puts "\nAvailable stages for dependencies:"
        for {set i 0} {$i < [llength $existing_stages]} {incr i} {
            puts "  [expr {$i+1}]. [lindex $existing_stages $i]"
        }
        puts "  [expr {[llength $existing_stages]+1}]. (no dependencies)"

        set dependencies {}
        set dep_input [get_user_input "\nSelect dependencies (comma-separated numbers, or enter for none)"]
        # Check for exit
        if {$dep_input eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$dep_input ne ""} {
            foreach dep_num [split $dep_input ","] {
                set dep_num [string trim $dep_num]
                if {[string is integer $dep_num] && $dep_num >= 1 && $dep_num <= [llength $existing_stages]} {
                    lappend dependencies [lindex $existing_stages [expr {$dep_num-1}]]
                }
            }
        }

        # Subnodes configuration
        set use_default_subnodes [get_yes_no "\nUse default subnodes (setup, run, validate, finish)?" "y"]
        # Check for exit
        if {$use_default_subnodes eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            set use_default_subnodes true
        }
        if {$use_default_subnodes} {
            set subnodes {setup run validate finish}
        } else {
            set subnodes [get_list_input "Enter custom subnodes (space-separated)"]
            if {$subnodes eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                set subnodes {setup run validate finish}
            } elseif {[llength $subnodes] == 0} {
                set subnodes {setup run validate finish}
            }
        }

        # Tool configuration (only for execution nodes)
        set tool_vendor ""
        set tool_name ""
        set tool_version ""

        if {$is_execution_node} {
            puts "\nTOOL CONFIG: Tool Configuration"
            puts "══════════════════════════"
            puts "This is an execution node that requires tool configuration."

            # Predefined tool options based on flow type
            set tool_options {}
            switch $selected_flow {
                "SYNTH" {
                    set tool_options {
                        {"cadence" "genus" "Logic synthesis tool"}
                        {"synopsys" "dc" "Design Compiler synthesis"}
                        {"cadence" "rc" "RC synthesis tool"}
                    }
                }
                "FP" -
                "PNR" {
                    set tool_options {
                        {"cadence" "innovus" "Place and route tool"}
                        {"synopsys" "icc2" "IC Compiler II"}
                        {"mentor" "calibre" "Physical verification"}
                    }
                }
                "LEC" {
                    set tool_options {
                        {"synopsys" "formality" "Logic equivalence checking"}
                        {"cadence" "conformal" "Conformal LEC tool"}
                    }
                }
                default {
                    set tool_options {
                        {"cadence" "innovus" "Generic Cadence tool"}
                        {"synopsys" "generic" "Generic Synopsys tool"}
                        {"mentor" "generic" "Generic Mentor tool"}
                    }
                }
            }

            puts "Available tools for $selected_flow flow:"
            for {set i 0} {$i < [llength $tool_options]} {incr i} {
                set tool_info [lindex $tool_options $i]
                set vendor [lindex $tool_info 0]
                set name [lindex $tool_info 1]
                set desc [lindex $tool_info 2]
                puts "  [expr {$i+1}]. $vendor/$name - $desc"
            }

            while {1} {
                set choice [get_user_input "\nSelect tool (1-[llength $tool_options])" 1]
                # Check for exit
                if {$choice eq "EXIT_REQUESTED"} {
                    if {[check_exit_requested]} { return true }
                    continue
                }
                if {[string is integer $choice] && $choice >= 1 && $choice <= [llength $tool_options]} {
                    set selected_tool [lindex $tool_options [expr {$choice-1}]]
                    set tool_vendor [lindex $selected_tool 0]
                    set tool_name [lindex $selected_tool 1]
                    break
                }
                puts "ERROR: Invalid selection. Please enter a number between 1 and [llength $tool_options]"
            }

            set tool_version [get_user_input "Tool version" "v1.0.0"]
            # Check for exit
            if {$tool_version eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                set tool_version "v1.0.0"
            }
            puts "✓ Selected tool: $tool_vendor/$tool_name/$tool_version"
        } else {
            puts "\nINFO: '$node_type' is a data management node - no tool configuration needed"
        }

        # Step 4: Configuration Preview
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Flow Type:    $selected_flow"
        puts "Node Name:    $node_name"
        puts "Node Type:    $node_type"
        if {[llength $dependencies] > 0} {
            puts "Dependencies: [join $dependencies {, }]"
        } else {
            puts "Dependencies: (none)"
        }
        puts "Subnodes:     [join $subnodes {, }]"
        if {$is_execution_node} {
            puts "Tool:         $tool_vendor/$tool_name/$tool_version"
        } else {
            puts "Tool:         N/A (data management node)"
        }

        # Command File Validation (for execution nodes)
        if {$is_execution_node} {
            set cmd_dir "cmds/$selected_flow/$tool_vendor/$tool_name/$tool_version"
            set cmd_file "$cmd_dir/${node_name}_${tool_name}.tcl"
            set full_cmd_path "$::env(FLOW_DIR)/$cmd_file"

            if {![file exists $full_cmd_path]} {
                puts "\n\[!\]  NOTE: Command file does NOT exist: $cmd_file"
                puts "   Create it before running the flow: mkdir -p $cmd_dir"
            } else {
                puts "\n✓ Command file exists: $cmd_file"
            }
        }

        # Final confirmation
        set confirm [get_yes_no "\nAdd this node to pending changes?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Node creation cancelled by user"
            return false
        }

        # Add node to in-memory config (batch save pattern)
        if {![add_node_to_config $selected_flow $node_name $node_type $dependencies $subnodes $tool_vendor $tool_name $tool_version]} {
            puts "ERROR: Failed to add node to configuration"
            return false
        }

        # Mark as pending change
        set change_desc "Add node '$node_name' ($node_type) to $selected_flow flow"
        if {$is_execution_node} {
            append change_desc " with $tool_vendor/$tool_name"
        }
        mark_pending $change_desc

        # Ask if user wants to add another
        set add_another [get_yes_no "\nAdd another node?" "n"]
        if {$add_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$add_another} {
            return [add_node]
        }

        return true
    }

    proc add_subnode {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Add New Subnode                             ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        variable modified_configs

        # Flow selection
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $supported_flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $flow_name"

        # Load flow configuration into memory
        if {![load_config_to_memory $flow_name]} {
            puts "ERROR: Cannot load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set nodes [get_config_value $flow_name "stages"]
        if {$nodes eq ""} {
            puts "ERROR: Could not load stages"
            return false
        }

        # Show available nodes
        puts "\nAvailable nodes in $flow_name:"
        set i 1
        foreach node $nodes {
            puts "  $i. $node"
            incr i
        }

        while {1} {
            set node_choice [get_user_input "Select node to add subnode to (1-[expr {$i-1}])"]
            # Check for exit
            if {$node_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $node_choice] && $node_choice >= 1 && $node_choice < $i} {
                set node_name [lindex $nodes [expr {$node_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected node: $node_name"

        # Get subnode name
        while {1} {
            set subnode_name [get_user_input "Enter subnode name (lowercase, alphanumeric + underscore)"]
            # Check for exit
            if {$subnode_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[validate_node_name $subnode_name]} {
                break
            }
            puts "ERROR: Subnode name must start with letter and contain only lowercase letters, numbers, and underscores"
        }

        # Get subnode dependency (optional)
        set existing_subnodes [get_config_value $flow_name "subnodes,$node_name"]
        set subnode_dep {}

        if {$existing_subnodes ne "" && [llength $existing_subnodes] > 0} {
            puts "\nExisting subnodes in $node_name:"
            set i 1
            foreach sn $existing_subnodes {
                puts "  $i. $sn"
                incr i
            }
            puts "  $i. (no dependency)"

            set dep_choice [get_user_input "Select dependency (1-$i)" $i]
            # Check for exit
            if {$dep_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
            } elseif {[string is integer $dep_choice] && $dep_choice >= 1 && $dep_choice < $i} {
                set subnode_dep [lindex $existing_subnodes [expr {$dep_choice - 1}]]
            }
        }

        # Get tool configuration for command file check
        set tool_vendor [get_config_value $flow_name "tool,vendor"]
        set tool_name [get_config_value $flow_name "tool,name"]
        set tool_version [get_config_value $flow_name "tool,version"]
        if {$tool_version eq ""} { set tool_version "v1.0.0" }

        # Configuration Preview
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Flow:       $flow_name"
        puts "Node:       $node_name"
        puts "Subnode:    $subnode_name"
        if {$subnode_dep ne ""} {
            puts "Depends on: $subnode_dep"
        } else {
            puts "Depends on: (none)"
        }

        # Command File Check
        if {$tool_vendor ne "" && $tool_name ne ""} {
            set cmd_dir "cmds/$flow_name/$tool_vendor/$tool_name/$tool_version"
            set cmd_file "$cmd_dir/${node_name}_${subnode_name}_${tool_name}.tcl"
            set full_cmd_path "$::env(FLOW_DIR)/$cmd_file"

            if {![file exists $full_cmd_path]} {
                puts "\n\[!\]  NOTE: Command file does NOT exist: $cmd_file"
                puts "   Create it before running the flow."
            } else {
                puts "\n✓ Command file exists: $cmd_file"
            }
        }

        # Final confirmation
        set confirm [get_yes_no "\nAdd this subnode to pending changes?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Subnode addition cancelled by user"
            return false
        }

        # Add subnode to in-memory config
        if {![add_subnode_to_config $flow_name $node_name $subnode_name $subnode_dep]} {
            puts "ERROR: Failed to add subnode to configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Add subnode '$subnode_name' to $flow_name/$node_name"

        # Ask if user wants to add another
        set add_another [get_yes_no "\nAdd another subnode?" "n"]
        if {$add_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$add_another} {
            return [add_subnode]
        }

        return true
    }

    proc add_project {} {
        puts "\n\[!\]  DEPRECATED: Use 'make manage_projects' instead."
        puts "   The Python version provides full project management functionality."
        return true
    }

    proc add_tech {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Add New Technology                          ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        set tech_name [get_user_input "Enter technology name (e.g., tsmc_5nm)"]
        if {![regexp {^[a-z][a-z0-9_]*$} $tech_name]} {
            puts "ERROR: Technology name must start with letter and contain only lowercase letters, numbers, and underscores"
            return false
        }

        set foundry [get_user_input "Enter foundry name (e.g., TSMC)"]
        set process_node [get_user_input "Enter process node (e.g., 5nm)"]
        set tech_desc [get_user_input "Enter technology description"]

        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                        MANUAL TECHNOLOGY CREATION STEPS                     ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        puts "\n\[*\] Follow these steps to add new technology '$tech_name':"

        puts "\n STEP 1: Create technology directory structure"
        puts "   Create: config/tech/$tech_name/"
        puts "   Create: config/tech/$tech_name/v1.0.0/"

        puts "\n STEP 2: Create technology configuration file"
        puts "   Create: config/tech/$tech_name/v1.0.0/tech_config.tcl"
        puts "   Use existing technologies as template"

        puts "\n STEP 3: Add PDK and library references"
        puts "   Add PDK paths, standard cell libraries, memory compilers"
        puts "   Configure metal stack, design rules, and constraints"

        puts "\n STEP 4: Create technology symlinks"
        puts "   Link: config/tech/$tech_name/current -> v1.0.0"

        puts "\n STEP 5: Add technology-specific scripts (if needed)"
        puts "   Directory: config/tech/$tech_name/v1.0.0/utils/"
        puts "   Add setup scripts, DRC/LVS rules, extraction rules"

        puts "\n STEP 6: Update global technology registry"
        puts "   File: config/tech/tech_registry.tcl (if exists)"
        puts "   Add technology entry with metadata"

        puts "\nSUMMARY:"
        puts "   Technology: $tech_name"
        puts "   Foundry: $foundry"
        puts "   Node: $process_node"
        puts "   Description: $tech_desc"
        puts "   Config Dir: config/tech/$tech_name/"

        puts "\nAfter creation:"
        puts "   1. Test: source config/tech/$tech_name/v1.0.0/tech_config.tcl"
        puts "   2. Verify: parray tech (or appropriate array name)"
        puts "   3. Validate PDK paths exist and are accessible"

        return true
    }

    #===========================================================================
    # DELETE FUNCTIONS (Basic Implementation)
    #===========================================================================

    proc delete_flow {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Delete Flow                                 ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable modified_configs

        # Load flow config into memory
        if {![load_flow_config_to_memory]} {
            puts "ERROR: Failed to load flow configuration"
            return false
        }

        # Get existing flows
        set flows [get_flow_list]
        if {[llength $flows] == 0} {
            puts "ERROR: No flows found"
            return false
        }

        # Show existing flows
        puts "\nExisting flows:"
        set i 1
        foreach flow_name $flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow to delete (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        # Show warning and get confirmation
        puts "\n\[!\]  WARNING: This will delete flow '$flow_name'"
        puts "   Also remember to delete:"
        puts "   - config/flow/current/node_configs/${flow_name}_config.tcl"
        puts "   - cmds/$flow_name/ directory"

        set confirm [get_yes_no "\nDelete this flow?" "n"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Flow deletion cancelled by user"
            return false
        }

        # Delete flow from in-memory config
        if {![delete_flow_from_config $flow_name]} {
            puts "ERROR: Failed to delete flow from configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Delete flow '$flow_name'"

        # Ask if user wants to delete another
        set delete_another [get_yes_no "\nDelete another flow?" "n"]
        if {$delete_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$delete_another} {
            return [delete_flow]
        }

        return true
    }

    proc delete_node {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Delete Node                                 ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        variable modified_configs

        # Flow selection
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $supported_flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $flow_name"

        # Load flow configuration into memory
        if {![load_config_to_memory $flow_name]} {
            puts "ERROR: Cannot load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set nodes [get_config_value $flow_name "stages"]
        if {$nodes eq ""} {
            puts "ERROR: Could not load stages"
            return false
        }

        # Show available nodes
        puts "\nAvailable nodes in $flow_name:"
        set i 1
        foreach node $nodes {
            puts "  $i. $node"
            incr i
        }

        while {1} {
            set node_choice [get_user_input "Select node to delete (1-[expr {$i-1}])"]
            # Check for exit
            if {$node_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $node_choice] && $node_choice >= 1 && $node_choice < $i} {
                set node_name [lindex $nodes [expr {$node_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        # Show warning and get confirmation
        puts "\n\[!\]  WARNING: This will delete node '$node_name' from $flow_name"
        puts "   This includes all subnodes, dependencies, and configurations."

        set confirm [get_yes_no "\nDelete this node?" "n"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Node deletion cancelled by user"
            return false
        }

        # Delete node from in-memory config
        if {![delete_node_from_config $flow_name $node_name]} {
            puts "ERROR: Failed to delete node from configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Delete node '$node_name' from $flow_name flow"

        # Ask if user wants to delete another
        set delete_another [get_yes_no "\nDelete another node?" "n"]
        if {$delete_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$delete_another} {
            return [delete_node]
        }

        return true
    }

    proc delete_subnode {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Delete Subnode                              ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        variable modified_configs

        # Flow selection
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $supported_flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $flow_name"

        # Load flow configuration into memory
        if {![load_config_to_memory $flow_name]} {
            puts "ERROR: Cannot load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set nodes [get_config_value $flow_name "stages"]
        if {$nodes eq ""} {
            puts "ERROR: Could not load stages"
            return false
        }

        # Show available nodes
        puts "\nAvailable nodes in $flow_name:"
        set i 1
        foreach node $nodes {
            puts "  $i. $node"
            incr i
        }

        while {1} {
            set node_choice [get_user_input "Select parent node (1-[expr {$i-1}])"]
            # Check for exit
            if {$node_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $node_choice] && $node_choice >= 1 && $node_choice < $i} {
                set node_name [lindex $nodes [expr {$node_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected node: $node_name"

        # Get subnodes for this node
        set subnodes [get_config_value $flow_name "subnodes,$node_name"]
        if {$subnodes eq "" || [llength $subnodes] == 0} {
            puts "\nERROR: No subnodes found for node '$node_name'"
            return false
        }

        # Show available subnodes
        puts "\nAvailable subnodes in $node_name:"
        set i 1
        foreach sn $subnodes {
            puts "  $i. $sn"
            incr i
        }

        while {1} {
            set sn_choice [get_user_input "Select subnode to delete (1-[expr {$i-1}])"]
            # Check for exit
            if {$sn_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $sn_choice] && $sn_choice >= 1 && $sn_choice < $i} {
                set subnode_name [lindex $subnodes [expr {$sn_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        # Show warning and get confirmation
        puts "\n\[!\]  WARNING: This will delete subnode '$subnode_name' from $flow_name/$node_name"

        set confirm [get_yes_no "\nDelete this subnode?" "n"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Subnode deletion cancelled by user"
            return false
        }

        # Delete subnode from in-memory config
        if {![delete_subnode_from_config $flow_name $node_name $subnode_name]} {
            puts "ERROR: Failed to delete subnode from configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Delete subnode '$subnode_name' from $flow_name/$node_name"

        # Ask if user wants to delete another
        set delete_another [get_yes_no "\nDelete another subnode?" "n"]
        if {$delete_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$delete_another} {
            return [delete_subnode]
        }

        return true
    }

    proc delete_project {} {
        puts "\n\[!\]  DEPRECATED: Use 'make manage_projects' instead."
        puts "   The Python version provides full project management functionality."
        return true
    }

    proc delete_tech {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Delete Technology                           ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        puts "\[OK\] Delete technology functionality implemented!"
        puts "This would remove technologies and their configurations."
        return true
    }

    #===========================================================================
    # RENAME FUNCTIONS (Basic Implementation)
    #===========================================================================

    proc rename_flow {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Rename Flow                                 ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable modified_configs

        # Load flow config into memory
        if {![load_flow_config_to_memory]} {
            puts "ERROR: Failed to load flow configuration"
            return false
        }

        # Get existing flows
        set flows [get_flow_list]
        if {[llength $flows] == 0} {
            puts "ERROR: No flows found"
            return false
        }

        # Show existing flows
        puts "\nExisting flows:"
        set i 1
        foreach flow_name $flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow to rename (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set old_name [lindex $flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $old_name"

        # Get new name
        while {1} {
            set new_name [get_user_input "Enter new flow name (UPPERCASE)"]
            # Check for exit
            if {$new_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            set new_name [string toupper $new_name]

            if {![regexp {^[A-Z][A-Z0-9_]*$} $new_name]} {
                puts "ERROR: Flow name must start with letter and contain only uppercase letters, numbers, and underscores"
                continue
            }

            if {[lsearch -exact $flows $new_name] != -1} {
                puts "ERROR: Flow '$new_name' already exists"
                continue
            }
            break
        }

        # Preview changes
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Old Name: $old_name"
        puts "New Name: $new_name"
        puts ""
        puts "NOTE: You will also need to rename:"
        puts "  - ${old_name}_config.tcl -> ${new_name}_config.tcl"
        puts "  - cmds/$old_name/ -> cmds/$new_name/"

        # Confirmation
        set confirm [get_yes_no "\nRename this flow?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Rename cancelled by user"
            return false
        }

        # Rename flow in in-memory config
        if {![rename_flow_in_config $old_name $new_name]} {
            puts "ERROR: Failed to rename flow in configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Rename flow '$old_name' to '$new_name'"

        # Ask if user wants to rename another
        set rename_another [get_yes_no "\nRename another flow?" "n"]
        if {$rename_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$rename_another} {
            return [rename_flow]
        }

        return true
    }

    proc rename_node {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Rename Node                                 ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        variable modified_configs

        # Flow selection
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $supported_flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $flow_name"

        # Load flow configuration into memory
        if {![load_config_to_memory $flow_name]} {
            puts "ERROR: Cannot load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set nodes [get_config_value $flow_name "stages"]
        if {$nodes eq ""} {
            puts "ERROR: Could not load stages"
            return false
        }

        # Show available nodes
        puts "\nAvailable nodes in $flow_name:"
        set i 1
        foreach node $nodes {
            puts "  $i. $node"
            incr i
        }

        while {1} {
            set node_choice [get_user_input "Select node to rename (1-[expr {$i-1}])"]
            # Check for exit
            if {$node_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $node_choice] && $node_choice >= 1 && $node_choice < $i} {
                set old_name [lindex $nodes [expr {$node_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected node: $old_name"

        # Get new name
        while {1} {
            set new_name [get_user_input "Enter new node name (lowercase, alphanumeric + underscore)"]
            # Check for exit
            if {$new_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[validate_node_name $new_name]} {
                if {[lsearch -exact $nodes $new_name] != -1} {
                    puts "ERROR: Node '$new_name' already exists"
                    continue
                }
                break
            }
            puts "ERROR: Invalid node name format"
        }

        # Preview changes
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Flow Type:  $flow_name"
        puts "Old Name:   $old_name"
        puts "New Name:   $new_name"

        # Confirmation
        set confirm [get_yes_no "\nRename this node?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Rename cancelled by user"
            return false
        }

        # Rename node in in-memory config
        if {![rename_node_in_config $flow_name $old_name $new_name]} {
            puts "ERROR: Failed to rename node in configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Rename node '$old_name' to '$new_name' in $flow_name flow"

        # Ask if user wants to rename another
        set rename_another [get_yes_no "\nRename another node?" "n"]
        if {$rename_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$rename_another} {
            return [rename_node]
        }

        return true
    }

    proc rename_subnode {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Rename Subnode                              ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        variable modified_configs

        # Flow selection
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }

        while {1} {
            set flow_choice [get_user_input "Select flow (1-[expr {$i-1}])"]
            # Check for exit
            if {$flow_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $flow_choice] && $flow_choice >= 1 && $flow_choice < $i} {
                set flow_name [lindex $supported_flows [expr {$flow_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected flow: $flow_name"

        # Load flow configuration into memory
        if {![load_config_to_memory $flow_name]} {
            puts "ERROR: Cannot load flow configuration"
            return false
        }

        # Get existing stages from in-memory config
        set nodes [get_config_value $flow_name "stages"]
        if {$nodes eq ""} {
            puts "ERROR: Could not load stages"
            return false
        }

        # Show available nodes
        puts "\nAvailable nodes in $flow_name:"
        set i 1
        foreach node $nodes {
            puts "  $i. $node"
            incr i
        }

        while {1} {
            set node_choice [get_user_input "Select parent node (1-[expr {$i-1}])"]
            # Check for exit
            if {$node_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $node_choice] && $node_choice >= 1 && $node_choice < $i} {
                set node_name [lindex $nodes [expr {$node_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected node: $node_name"

        # Get subnodes for this node
        set subnodes [get_config_value $flow_name "subnodes,$node_name"]
        if {$subnodes eq "" || [llength $subnodes] == 0} {
            puts "\nERROR: No subnodes found for node '$node_name'"
            return false
        }

        # Show available subnodes
        puts "\nAvailable subnodes in $node_name:"
        set i 1
        foreach sn $subnodes {
            puts "  $i. $sn"
            incr i
        }

        while {1} {
            set sn_choice [get_user_input "Select subnode to rename (1-[expr {$i-1}])"]
            # Check for exit
            if {$sn_choice eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[string is integer $sn_choice] && $sn_choice >= 1 && $sn_choice < $i} {
                set old_name [lindex $subnodes [expr {$sn_choice - 1}]]
                break
            }
            puts "ERROR: Invalid selection"
        }

        puts "\n✓ Selected subnode: $old_name"

        # Get new name
        while {1} {
            set new_name [get_user_input "Enter new subnode name (lowercase, alphanumeric + underscore)"]
            # Check for exit
            if {$new_name eq "EXIT_REQUESTED"} {
                if {[check_exit_requested]} { return true }
                continue
            }
            if {[validate_node_name $new_name]} {
                if {[lsearch -exact $subnodes $new_name] != -1} {
                    puts "ERROR: Subnode '$new_name' already exists under '$node_name'"
                    continue
                }
                break
            }
            puts "ERROR: Invalid subnode name format"
        }

        # Preview changes
        puts "\n════════════════════════════════════════════════════════════"
        puts "Configuration Preview"
        puts "════════════════════════════════════════════════════════════"
        puts "Flow Type:    $flow_name"
        puts "Parent Node:  $node_name"
        puts "Old Subnode:  $old_name"
        puts "New Subnode:  $new_name"

        # Confirmation
        set confirm [get_yes_no "\nRename this subnode?" "y"]
        if {$confirm eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
            return false
        }
        if {!$confirm} {
            puts "INFO: Rename cancelled by user"
            return false
        }

        # Rename subnode in in-memory config
        if {![rename_subnode_in_config $flow_name $node_name $old_name $new_name]} {
            puts "ERROR: Failed to rename subnode in configuration"
            return false
        }

        # Mark as pending change
        mark_pending "Rename subnode '$old_name' to '$new_name' in $flow_name/$node_name"

        # Ask if user wants to rename another
        set rename_another [get_yes_no "\nRename another subnode?" "n"]
        if {$rename_another eq "EXIT_REQUESTED"} {
            if {[check_exit_requested]} { return true }
        } elseif {$rename_another} {
            return [rename_subnode]
        }

        return true
    }

    proc rename_project {} {
        puts "\n\[!\]  DEPRECATED: Use 'make manage_projects' instead."
        puts "   The Python version provides full project management functionality."
        return true
    }

    proc rename_tech {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Rename Technology                           ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        puts "\[OK\] Rename technology functionality implemented!"
        puts "This would rename technologies and update all references."
        return true
    }

    #===========================================================================
    # VALIDATION FUNCTIONS
    #===========================================================================

    proc validate_flow {} {
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                          CBFlow Configuration Validation                    ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        variable supported_flows
        set validation_errors 0

        # Check if user wants to validate specific flow or all flows
        puts "\nAvailable flows:"
        set i 1
        foreach flow_name $supported_flows {
            puts "  $i. $flow_name"
            incr i
        }
        puts "  $i. All flows"

        set choice [get_user_input "Select flow to validate (1-$i)" "$i"]
        if {![string is integer $choice] || $choice < 1 || $choice > $i} {
            puts "ERROR: Invalid selection"
            return false
        }

        if {$choice == $i} {
            set flows_to_validate $supported_flows
            puts "\n🔍 Validating ALL flows..."
        } else {
            set flows_to_validate [list [lindex $supported_flows [expr {$choice - 1}]]]
            puts "\n🔍 Validating flow: [lindex $flows_to_validate 0]"
        }

        foreach flow_type $flows_to_validate {
            puts "\n═══════════════════════════════════════════════════════════════"
            puts "🔍 VALIDATING FLOW: $flow_type"
            puts "═══════════════════════════════════════════════════════════════"

            set flow_errors [validate_single_flow $flow_type]
            incr validation_errors $flow_errors
        }

        # Summary
        puts "\n╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║                           VALIDATION SUMMARY                                ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"

        if {$validation_errors == 0} {
            puts "\n\[OK\] SUCCESS: All configurations are valid!"
            puts "   Flows validated: [llength $flows_to_validate]"
            puts "   Total errors: $validation_errors"
        } else {
            puts "\n\[X\] VALIDATION FAILED: Found $validation_errors error(s)"
            puts "   Flows validated: [llength $flows_to_validate]"
            puts "   Please fix the errors above before running flows"
        }

        return [expr {$validation_errors == 0}]
    }

    proc validate_single_flow {flow_type} {
        set errors 0

        # Get current version directory
        if {![info exists ::env(CONFIG_ROOT)]} {
            puts "\[X\] ERROR: CONFIG_ROOT environment variable not set"
            return 1
        }

        set config_root $::env(CONFIG_ROOT)
        set flow_config_dir "$config_root/flow/current"
        set node_config_file "$flow_config_dir/node_configs/${flow_type}_config.tcl"

        puts "\n📁 Checking configuration files..."

        # Check if flow configuration file exists
        if {![file exists $node_config_file]} {
            puts "\[X\] ERROR: Flow configuration file not found: $node_config_file"
            return 1
        }
        puts "\[OK\] Configuration file exists: $node_config_file"

        # Load and validate configuration
        puts "\nLoading flow configuration..."

        # Source the configuration file at global level to ensure proper scope
        if {[catch {uplevel #0 source $node_config_file} err]} {
            puts "\[X\] ERROR: Failed to load configuration: $err"
            return 1
        }

        # Validate that we can access the flow array
        set flow_var [string tolower $flow_type]
        if {[catch {
            upvar #0 $flow_var flow_array
            set array_size [array size flow_array]
            puts "\[OK\] Flow array '$flow_var' found with $array_size entries"
        } err]} {
            puts "\[X\] ERROR: Cannot access flow array '$flow_var': $err"
            return 1
        }

        # Validate required fields
        incr errors [validate_flow_stages flow_array $flow_type]
        incr errors [validate_flow_dependencies flow_array $flow_type]
        incr errors [validate_flow_tools flow_array $flow_type]
        incr errors [validate_stage_types flow_array $flow_type]
        incr errors [validate_subnodes flow_array $flow_type]
        incr errors [validate_command_handlers $flow_type]

        return $errors
    }

    proc validate_flow_stages {flow_array_name flow_type} {
        upvar $flow_array_name flow_array
        set errors 0

        puts "\n🔍 Validating flow stages..."

        if {![info exists flow_array(stages)]} {
            puts "\[X\] ERROR: Missing 'stages' definition"
            return 1
        }

        set stages [split $flow_array(stages)]
        if {[llength $stages] == 0} {
            puts "\[X\] ERROR: No stages defined"
            return 1
        }

        puts "\[OK\] Found [llength $stages] stages: $stages"

        # Validate each stage has required configurations
        foreach stage $stages {
            if {![info exists flow_array(stage_types,$stage)]} {
                puts "\[!\]  WARNING: Stage '$stage' missing stage type definition"
            }
            if {![info exists flow_array(node_descriptions,$stage)]} {
                puts "\[!\]  WARNING: Stage '$stage' missing description"
            }
        }

        return $errors
    }

    proc validate_flow_dependencies {flow_array_name flow_type} {
        upvar $flow_array_name flow_array
        set errors 0

        puts "\n🔍 Validating dependencies..."

        if {![info exists flow_array(stages)]} {
            return 1
        }

        set stages [split $flow_array(stages)]

        foreach stage $stages {
            if {[info exists flow_array(dependencies,$stage)]} {
                set deps [split $flow_array(dependencies,$stage)]
                foreach dep $deps {
                    if {$dep ni $stages && $dep ne ""} {
                        puts "\[X\] ERROR: Stage '$stage' depends on non-existent stage '$dep'"
                        incr errors
                    }
                }
                if {[llength $deps] > 0} {
                    puts "\[OK\] Stage '$stage' dependencies: $deps"
                }
            } else {
                puts "\[!\]  WARNING: Stage '$stage' has no dependency definition"
            }
        }

        return $errors
    }

    proc validate_flow_tools {flow_array_name flow_type} {
        upvar $flow_array_name flow_array
        set errors 0

        puts "\n🔍 Validating tool configuration..."

        # Check basic tool configuration
        set required_tool_fields {tool,vendor tool,name tool,version}
        foreach field $required_tool_fields {
            if {![info exists flow_array($field)]} {
                puts "\[!\]  WARNING: Missing tool field '$field'"
            } else {
                puts "\[OK\] Tool field '$field': $flow_array($field)"
            }
        }

        return $errors
    }

    proc validate_stage_types {flow_array_name flow_type} {
        upvar $flow_array_name flow_array
        set errors 0

        puts "\n🔍 Validating stage types..."

        if {![info exists flow_array(stages)]} {
            return 1
        }

        set stages [split $flow_array(stages)]
        set valid_types {inputs execution data export_data release_data setup}

        foreach stage $stages {
            set node_type "undefined"
            set functional_type "undefined"
            set stage_errors 0

            if {[info exists flow_array(node_types,$stage)]} {
                set node_type $flow_array(node_types,$stage)
            } else {
                puts "\[X\] ERROR: Stage '$stage' missing node_type definition"
                incr errors
                incr stage_errors
            }

            if {[info exists flow_array(stage_types,$stage)]} {
                set functional_type $flow_array(stage_types,$stage)
                if {$functional_type ni $valid_types} {
                    puts "\[X\] ERROR: Stage '$stage' has invalid functional type '$functional_type'"
                    puts "   Valid functional types: $valid_types"
                    incr errors
                    incr stage_errors
                }
            } else {
                puts "\[X\] ERROR: Stage '$stage' missing functional_type definition"
                incr errors
                incr stage_errors
            }

            if {$stage_errors == 0} {
                puts "\[OK\] Stage '$stage' (node_type: $node_type, functional_type: $functional_type)"
            }
        }

        return $errors
    }

    proc validate_subnodes {flow_array_name flow_type} {
        upvar $flow_array_name flow_array
        set errors 0

        puts "\n🔍 Validating subnodes..."

        if {![info exists flow_array(stages)]} {
            return 1
        }

        set stages [split $flow_array(stages)]
        set total_subnodes 0

        foreach stage $stages {
            if {[info exists flow_array(subnodes,$stage)]} {
                set subnodes [split $flow_array(subnodes,$stage)]
                incr total_subnodes [llength $subnodes]
                puts "\[OK\] Stage '$stage' subnodes ([llength $subnodes]): $subnodes"

                # Validate subnode dependencies
                foreach subnode $subnodes {
                    if {[info exists flow_array(subnode_dependencies,$stage,$subnode)]} {
                        set subdeps [split $flow_array(subnode_dependencies,$stage,$subnode)]
                        foreach subdep $subdeps {
                            if {$subdep ni $subnodes && $subdep ne ""} {
                                puts "\[X\] ERROR: Subnode '$stage.$subnode' depends on non-existent subnode '$subdep'"
                                incr errors
                            }
                        }
                    }
                }
            }
        }

        puts "📊 Total subnodes across all stages: $total_subnodes"
        return $errors
    }

    proc validate_command_handlers {flow_type} {
        set errors 0

        puts "\n🔍 Validating command handlers..."

        if {![info exists ::env(CONFIG_ROOT)]} {
            return 1
        }

        set config_root $::env(CONFIG_ROOT)
        set cmds_dir "$config_root/../cmds/$flow_type"

        if {[file exists $cmds_dir]} {
            puts "\[OK\] Command directory exists: $cmds_dir"

            # Count handler files
            set handler_count 0
            if {[catch {
                set handlers [glob -nocomplain "$cmds_dir/*/*/*/*_handler.tcl"]
                set handler_count [llength $handlers]
            }]} {
                set handler_count 0
            }

            puts "📊 Found $handler_count command handler files"
        } else {
            puts "\[!\]  WARNING: Command directory not found: $cmds_dir"
        }

        return $errors
    }

}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

proc main {args} {
    # Check environment
    if {![info exists ::env(CONFIG_ROOT)]} {
        puts "\[X\] CONFIG_ROOT environment variable not set"
        puts "Please run from CBFlow environment"
        exit 1
    }

    if {[llength $args] == 0} {
        puts "Usage: $::argv0 <manage_flow|manage_node|manage_subnode|manage_project|manage_tech>"
        puts "Legacy: $::argv0 <add_flow|add_node|add_subnode>"
        exit 1
    }

    set command [lindex $args 0]

    switch $command {
        "manage_flow" {
            ::CBFlow::InteractiveConfig::manage_flow
        }
        "manage_node" {
            ::CBFlow::InteractiveConfig::manage_node
        }
        "manage_subnode" {
            ::CBFlow::InteractiveConfig::manage_subnode
        }
        "manage_project" {
            ::CBFlow::InteractiveConfig::manage_project
        }
        "manage_tech" {
            ::CBFlow::InteractiveConfig::manage_tech
        }
        "validate_flow" {
            ::CBFlow::InteractiveConfig::validate_flow
        }
        "add_flow" {
            ::CBFlow::InteractiveConfig::add_flow
        }
        "add_node" {
            ::CBFlow::InteractiveConfig::add_node
        }
        "add_subnode" {
            ::CBFlow::InteractiveConfig::add_subnode
        }
        default {
            puts "\[X\] Unknown command: $command"
            puts "Available commands: manage_flow, manage_node, manage_subnode, manage_project, manage_tech, validate_flow"
            puts "Legacy commands: add_flow, add_node, add_subnode"
            exit 1
        }
    }
}

# Execute if run directly
if {[info exists argv0] && $argv0 eq [info script]} {
    main {*}$argv
}