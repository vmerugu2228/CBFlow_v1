#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Setup and Config Generation Script (Refactored)
# Description: Expands hierarchical setup files (flow_proc hooks) and config files (variables)
# Version: v1.0.0
# Namespace: ::CBFlow::Generation::SetupGenerator
# Usage: tclsh generate_setup_refactored.tcl <flow_type> <node_type> <node_name> <run_dir>
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Script Initialization ──────────────────────────────────────────────────────┐
# Load CBFlow utilities for environment setup
set script_dir [file dirname [file normalize [info script]]]

# Use FLOW_DIR from environment if available (preferred)
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    # Fallback: calculate from script location (less robust)
    set FLOW_DIR [file dirname [file dirname [file dirname $script_dir]]]
    puts "WARNING: FLOW_DIR not set in environment, using calculated path: $FLOW_DIR"
}

# Load utilities
set utilities_version [expr {[info exists ::env(UTILITIES_VERSION)] ? $::env(UTILITIES_VERSION) : "v1.0.0"}]
set utils_path "$FLOW_DIR/utils/utilities/$utilities_version/utils.tcl"

if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts stderr "ERROR: Cannot find utils.tcl at $utils_path"
    exit 1
}

# Load centralized config loader
set config_loader_path "$FLOW_DIR/utils/utilities/$utilities_version/config_loader.tcl"
if {[file exists $config_loader_path]} {
    source $config_loader_path
} else {
    puts stderr "WARNING: Cannot find config_loader.tcl at $config_loader_path"
}

# Set required environment variables if not set
if {![info exists ::env(FLOW_DIR)]} {
    set ::env(FLOW_DIR) $FLOW_DIR
}
if {![info exists ::env(PROJECT_VERSION)]} {
    set ::env(PROJECT_VERSION) "v1.0.0"
}

# ┌─ Global Scope Setup ─────────────────────────────────────────────────────────┐
# Ensure all required global variables are available AFTER initialization
global flow STAGE_TYPES DEPENDENCY_STAGES NODE_TYPE_DESCRIPTIONS
global argc argv argv0

# ┌─ Main Namespace ─────────────────────────────────────────────────────────────┐
namespace eval ::CBFlow::Generation::SetupGenerator {

    # ┌─ Namespace Variables ─────────────────────────────────────────────────────┐
    variable script_dir [file dirname [file normalize [info script]]]
    variable version "v1.0.0"
    variable debug_mode false

    # ┌─ Import Global Arrays ────────────────────────────────────────────────────┐
    # Simplified global access - arrays will be loaded when configs are sourced
    proc initialize_global_access {} {
        # Just return true - configs will be loaded during file generation
        handle_debug "Global array access initialized"
        return true
    }

    # ┌─ Common Functions ────────────────────────────────────────────────────────┐
    # Use utils.tcl handle functions
    proc handle_error {message} {
        ::handle_error $message
        return 0
    }

    proc handle_warning {message} {
        ::handle_warning $message
        return 1
    }

    proc handle_info {message} {
        ::handle_info $message
        return 1
    }

    proc handle_debug {message} {
        # Use handle_info for debug messages since handle_debug doesn't exist
        ::handle_info "DEBUG: $message"
        return 1
    }

    # ┌─ Flow Validation Functions ──────────────────────────────────────────────┐

    proc get_current_flow_type {} {
        global flow

        # Try multiple methods to determine flow type
        set flow_type ""

        # Method 1: Environment variable (most reliable — set by cbflow)
        if {[info exists ::env(CBFLOW_FLOW_TYPE)] && $::env(CBFLOW_FLOW_TYPE) ne ""} {
            set flow_type $::env(CBFLOW_FLOW_TYPE)
            handle_debug "Flow type from env: $flow_type"
            return $flow_type
        }

        # Method 2: Check flow array if loaded
        if {[info exists flow(type)] && $flow(type) ne ""} {
            set flow_type $flow(type)
            handle_debug "Flow type from flow array: $flow_type"
            return $flow_type
        }

        # Method 3: Check user config file
        if {[info exists ::env(CBFLOW_RUN_DIR)]} {
            set user_config "$::env(CBFLOW_RUN_DIR)/setup/user_config.tcl"
            if {[file exists $user_config]} {
                set fd [open $user_config r]
                set content [read $fd]
                close $fd
                if {[regexp {set\s+flow\(type\)\s+"([^"]+)"} $content -> detected_type]} {
                    set flow_type $detected_type
                    handle_debug "Flow type detected from user config: $flow_type"
                    return $flow_type
                }
            }
        }

        # Method 4: Parse from run directory name (P0_run_SYNTH_PNR_run1 → SYNTH_PNR)
        if {[info exists ::env(CBFLOW_RUN_DIR)]} {
            set dirname [file tail $::env(CBFLOW_RUN_DIR)]
            if {[regexp {P\d+_run_([A-Z_]+)_} $dirname -> detected_type]} {
                set flow_type $detected_type
                handle_debug "Flow type from run dir name: $flow_type"
                return $flow_type
            }
        }

        # Fallback
        set flow_type "SYNTH"
        handle_debug "Using default flow type: $flow_type"
        return $flow_type
    }

    proc get_base_flow_sequence {flow_type} {
        set stages [::CBFlow::Config::get_flow_stages $flow_type]
        if {$stages ne ""} {
            return $stages
        }
        handle_error "Unknown flow type: $flow_type"
        return {}
    }

    # ┌─ Utility Functions ───────────────────────────────────────────────────────┐

    proc get_tool_name {run_dir} {
        # Try multiple methods to extract tool name
        set tool_name ""

        # Get flow type first
        set flow_type [get_current_flow_type]

        # Method 1: Extract from user config (explicit tool setting)
        if {[file exists "$run_dir/setup/user_config.tcl"]} {
            if {[catch {
                set user_config_handle [open "$run_dir/setup/user_config.tcl" r]
                set content [read $user_config_handle]
                close $user_config_handle
                # Match: set <arr>(tool,name) "genus" or set flow(tool) "genus"
                set fl [string tolower $flow_type]
                if {[regexp "set\\s+${fl}\\(tool,name\\)\\s+\"(\[^\"]+)\"" $content -> extracted_tool]} {
                    set tool_name $extracted_tool
                } elseif {[regexp {set\s+\w+\(tool,name\)\s+"([^"]+)"} $content -> extracted_tool]} {
                    set tool_name $extracted_tool
                } elseif {[regexp {set\s+flow\(tool\)\s+"([^"]+)"} $content -> extracted_tool]} {
                    set tool_name $extracted_tool
                }
            }]} {
                # If extraction fails, continue to next method
            }
        }

        # Method 2: Use flow-specific default tool from node config
        if {$tool_name eq "" && $flow_type ne ""} {
            # Load flow-specific config to get default tool
            global synth pnr fcfp

            set config_file ""
            switch $flow_type {
                "SYNTH" { set config_file "SYNTH_config.tcl" }
                "PNR" { set config_file "PNR_config.tcl" }
                "FP" { set config_file "FP_config.tcl" }
                "FCFP" { set config_file "FCFP_config.tcl" }
                default { set config_file "${flow_type}_config.tcl" }
            }

            if {[info exists ::env(FLOW_DIR)]} {
                set flow_dir $::env(FLOW_DIR)
                set node_config_path "$flow_dir/config/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/$config_file"

                if {[file exists $node_config_path]} {
                    if {[catch {
                        # Source the config temporarily
                        source $node_config_path

                        # Try to get tool name from flow-specific array
                        switch $flow_type {
                            "SYNTH" {
                                if {[info exists synth(tool,name)]} {
                                    set tool_name $synth(tool,name)
                                } elseif {[info exists synth(default_tool)]} {
                                    set tool_name $synth(default_tool)
                                }
                            }
                            "PNR" {
                                if {[info exists pnr(tool,name)]} {
                                    set tool_name $pnr(tool,name)
                                } elseif {[info exists pnr(default_tool)]} {
                                    set tool_name $pnr(default_tool)
                                }
                            }
                            "FP" {
                                if {[info exists fp(tool,name)]} {
                                    set tool_name $fp(tool,name)
                                } elseif {[info exists fp(default_tool)]} {
                                    set tool_name $fp(default_tool)
                                }
                            }
                            default {
                                # Generic handling for other flows
                            }
                        }
                    }]} {
                        # If loading fails, continue to fallback
                    }
                }
            }
        }

        # Method 3: Flow-specific default from centralized config — no hardcoded fallback
        if {$tool_name eq ""} {
            set tool_name [::CBFlow::Config::get_tool_name $flow_type]
            if {$tool_name eq ""} {
                puts "ERROR: Cannot resolve tool_name for flow $flow_type"
                puts "  Set <arr>(tool,name) in user_config or default_tool in node_config"
                error "Missing required config: tool,name"
            }
        }

        return $tool_name
    }

    proc read_file_content {file_path label} {
        if {[file exists $file_path]} {
            set read_handle [open $file_path r]
            set content [read $read_handle]
            close $read_handle
            return [list true $content]
        } else {
            return [list false ""]
        }
    }

    # ┌─ Hierarchical Path Functions ─────────────────────────────────────────────┐

    proc get_hierarchical_setup_paths {flow_dir run_dir flow_type node_type node_name} {
        set setup_files {}

        # Get tool name for tool-specific paths
        set tool_name [get_tool_name $run_dir]

        # Resolve config root and versions from environment
        set config_root [expr {[info exists ::env(CONFIG_ROOT)] ? $::env(CONFIG_ROOT) : "$flow_dir/config"}]
        set setup_version [expr {[info exists ::env(SETUP_VERSION)] ? $::env(SETUP_VERSION) : "v1.0.0"}]
        set project_name ""
        if {[info exists ::env(CBFLOW_PROJECT_NAME)]} { set project_name $::env(CBFLOW_PROJECT_NAME) }
        if {$project_name eq "" && [info exists ::env(PROJECT_NAME)]} { set project_name $::env(PROJECT_NAME) }
        set project_version [expr {[info exists ::env(PROJECT_VERSION)] ? $::env(PROJECT_VERSION) : "v1.0.0"}]

        # Determine tool vendor from env or auto-detect
        if {[info exists ::env(CBFLOW_TOOL_VENDOR)]} {
            set vendor $::env(CBFLOW_TOOL_VENDOR)
        } else {
            # Auto-detect vendor from tool name
            set vendor "synopsys"
            if {[string match "*genus*" $tool_name] || [string match "*innovus*" $tool_name] ||
                [string match "*tempus*" $tool_name] || [string match "*voltus*" $tool_name] ||
                [string match "*conformal*" $tool_name]} {
                set vendor "cadence"
            }
        }

        set tool_version [expr {[info exists ::env(TOOL_VERSION)] ? $::env(TOOL_VERSION) : "v1.0.0"}]

        # Base paths
        set common_setup "$config_root/setup/common/$setup_version"
        set project_setup "$config_root/setup/$project_name/$project_version"

        # Setup files (lowest to highest priority) - flow_proc hooks only

        # 1. Global Setup (Lowest Priority)
        lappend setup_files [list "global_setup" "$common_setup/setup.tcl"]
        lappend setup_files [list "global_flow_setup" "$common_setup/flow_setup.tcl"]

        # 2. Flow-Type Setup
        lappend setup_files [list "flow_type_setup" "$common_setup/$flow_type/$vendor/$tool_name/global_setup.tcl"]

        # 3. Stage-Specific Setup
        # Strip numeric suffix from node_type for stage setup lookup
        regsub {[0-9]+$} $node_type "" node_type_base
        lappend setup_files [list "stage_setup" "$common_setup/$flow_type/$vendor/$tool_name/${node_type_base}_setup.tcl"]

        # 4. Project-Level Setup
        if {$project_name ne ""} {
            lappend setup_files [list "project_setup" "$project_setup/setup.tcl"]
            lappend setup_files [list "project_flow_setup" "$project_setup/$flow_type/flow_setup.tcl"]
        }

        # 5. User/Workspace Setup Overrides
        lappend setup_files [list "workspace_setup" "$run_dir/setup/setup.tcl"]
        lappend setup_files [list "workspace_flow_setup" "$run_dir/setup/flow_setup.tcl"]
        lappend setup_files [list "workspace_stage_setup" "$run_dir/setup/${node_type_base}_setup.tcl"]

        # 6. Override Files (Highest Priority)
        set override_patterns [list \
            [list "override_global" "$run_dir/setup/override_setup.tcl"] \
            [list "override_flow" "$run_dir/setup/override_setup.$flow_type.tcl"] \
            [list "override_stage_${node_type_base}" "$run_dir/setup/override_setup.${node_type_base}.tcl"] \
            [list "override_node_${node_name}" "$run_dir/setup/override_setup.${node_name}.tcl"] \
        ]

        foreach override_entry $override_patterns {
            lassign $override_entry label file_path
            if {[file exists $file_path]} {
                lappend setup_files $override_entry
            }
        }

        return $setup_files
    }

    proc get_hierarchical_config_paths {flow_dir run_dir flow_type node_type node_name} {
        set config_files {}

        # Get tool name for tool-specific paths
        set tool_name [get_tool_name $run_dir]

        # Resolve paths from environment
        set config_root [expr {[info exists ::env(CONFIG_ROOT)] ? $::env(CONFIG_ROOT) : "$flow_dir/config"}]
        set project_name ""
        if {[info exists ::env(CBFLOW_PROJECT_NAME)]} { set project_name $::env(CBFLOW_PROJECT_NAME) }
        if {$project_name eq "" && [info exists ::env(PROJECT_NAME)]} { set project_name $::env(PROJECT_NAME) }
        set project_version [expr {[info exists ::env(PROJECT_VERSION)] ? $::env(PROJECT_VERSION) : "v1.0.0"}]
        set flow_config_ver [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
        set tech_name ""
        if {[info exists ::env(TECH_NAME)]} { set tech_name $::env(TECH_NAME) }
        if {$tech_name eq "" && [info exists ::env(TECH_NODE)]} { set tech_name $::env(TECH_NODE) }
        set tech_version [expr {[info exists ::env(TECH_VERSION)] ? $::env(TECH_VERSION) : "v1.0.0"}]
        if {[info exists ::env(TECHNOLOGY_VERSION)]} { set tech_version $::env(TECHNOLOGY_VERSION) }

        # Determine tool vendor from env or auto-detect
        if {[info exists ::env(CBFLOW_TOOL_VENDOR)]} {
            set vendor $::env(CBFLOW_TOOL_VENDOR)
        } else {
            set vendor "synopsys"
            if {[string match "*genus*" $tool_name] || [string match "*innovus*" $tool_name] ||
                [string match "*tempus*" $tool_name] || [string match "*voltus*" $tool_name] ||
                [string match "*conformal*" $tool_name]} {
                set vendor "cadence"
            }
        }
        set tool_version [expr {[info exists ::env(TOOL_VERSION)] ? $::env(TOOL_VERSION) : "v1.0.0"}]

        # Strip numeric suffix from node_type for config lookups
        regsub {[0-9]+$} $node_type "" node_type_base

        # Config files (lowest to highest priority) - configuration variables only

        # 1. Project Configuration (Base Layer)
        if {$project_name ne ""} {
            lappend config_files [list "project_config" "$config_root/project/$project_name/$project_version/${project_name}_config.tcl"]
            lappend config_files [list "team_config" "$config_root/project/$project_name/$project_version/team_config.tcl"]
        }

        # 2. Technology Configuration (pure data — all metal stack data included with <ms> prefix)
        if {$tech_name ne ""} {
            lappend config_files [list "technology_config" "$config_root/tech/$tech_name/$tech_version/tech_config.tcl"]
        }

        # 4. Library Configuration (generated by library-manager)
        #    Always requires project(lib_config_tag) — no default lib_config.tcl
        if {$tech_name ne ""} {
            set _lib_tag ""
            # Pre-source project_config to resolve lib_config_tag (not yet sourced at generation time)
            if {![info exists project(lib_config_tag)] || $project(lib_config_tag) eq ""} {
                set _proj_cfg "$config_root/project/$project_name/$project_version/${project_name}_config.tcl"
                if {[file exists $_proj_cfg]} {
                    catch { source $_proj_cfg }
                }
            }
            if {[info exists project(lib_config_tag)] && $project(lib_config_tag) ne ""} {
                set _lib_tag $project(lib_config_tag)
            }
            if {$_lib_tag ne ""} {
                set _lc "$config_root/tech/$tech_name/$tech_version/lib_config_${_lib_tag}.tcl"
                if {[file exists $_lc]} {
                    lappend config_files [list "lib_config" "$_lc"]
                } else {
                    puts "ERROR: lib_config not found: $_lc"
                    puts "ERROR: Generate with: cbflow flow library-manager generate --tech $tech_name --tag $_lib_tag"
                }
            } else {
                puts "WARNING: project(lib_config_tag) not set — no library config loaded"
                puts "WARNING: Set project(lib_config_tag) in project_config (e.g., \"P0\", \"timing_v1\")"
            }
        }

        # 5. Flow Configuration
        lappend config_files [list "flow_config" "$config_root/flow/$flow_config_ver/flow_config.tcl"]
        lappend config_files [list "node_config_${flow_type}" "$config_root/flow/$flow_config_ver/node_configs/${flow_type}_config.tcl"]

        # 6. MMMC Configuration (per project)
        if {$project_name ne ""} {
            set _mmmc_config "$config_root/project/$project_name/$project_version/mmmc_config.tcl"
            if {[file exists $_mmmc_config]} {
                lappend config_files [list "mmmc_config" "$_mmmc_config"]
            }
        }

        # 5. EDA Tool Configuration (if exists)
        set eda_dir "$config_root/eda/$flow_type/$vendor/$tool_name/$tool_version"
        if {[file exists "$eda_dir/tool_config.tcl"]} {
            lappend config_files [list "eda_tool_config" "$eda_dir/tool_config.tcl"]
        }
        if {[file exists "$eda_dir/${node_type_base}_config.tcl"]} {
            lappend config_files [list "eda_stage_config" "$eda_dir/${node_type_base}_config.tcl"]
        }

        # 5b. Tool-specific app variables now merged into node_configs/<FLOW>_<tool>_config.tcl
        #     (previously sourced from cmds/<FLOW>/<vendor>/<tool>/<ver>/<tool>_config.tcl)

        # 6. User Configuration
        lappend config_files [list "user_config" "$run_dir/setup/user_config.tcl"]

        # 6. Override Files (Highest Priority)
        # Look up branch name for this node from runtime_flow_config.tcl
        set _branch_name ""
        set _rtf "$run_dir/setup/runtime_flow_config.tcl"
        if {[file exists $_rtf]} {
            set _rtf_fd [open $_rtf r]
            set _rtf_content [read $_rtf_fd]
            close $_rtf_fd
            # Find branch_key for this node: stages,<node_type>,branch_key <key>
            if {[regexp "stages,${node_type},branch_key\\s+(\\S+)" $_rtf_content _match _bkey]} {
                # Find branch name from: branch_keys,<key>,name "<name>"
                if {[regexp "branch_keys,${_bkey},name\\s+\"(\[^\"\]*)\"" $_rtf_content _match2 _bname]} {
                    set _branch_name $_bname
                }
            }
        }

        set override_patterns [list \
            [list "override_config_global" "$run_dir/setup/override_config.tcl"] \
            [list "override_config_flow" "$run_dir/setup/override_config.$flow_type.tcl"] \
            [list "override_config_stage_${node_type_base}" "$run_dir/setup/override_config.${node_type_base}.tcl"] \
        ]
        if {$_branch_name ne ""} {
            lappend override_patterns [list "override_config_branch_${_branch_name}" "$run_dir/setup/override_config.${_branch_name}.tcl"]
        }
        lappend override_patterns [list "override_config_node_${node_name}" "$run_dir/setup/override_config.${node_name}.tcl"]

        foreach override_entry $override_patterns {
            lassign $override_entry label file_path
            if {[file exists $file_path]} {
                lappend config_files $override_entry
            }
        }

        return $config_files
    }

    # ┌─ Content Separation Functions ────────────────────────────────────────────┐

    proc convert_to_versioned_path {absolute_path flow_dir run_dir} {
        # Convert absolute paths to versioned environment variable expressions

        # For versioned paths, use environment variables
        # Pattern: /core/config/project/v1.0.0/ -> $FLOW_DIR/config/project/$PROJECT_VERSION/
        if {[regexp {^(.*/core)/config/project/v[0-9]+\.[0-9]+\.[0-9]+/(.+)$} $absolute_path -> base_path file_name]} {
            return "\$FLOW_DIR/config/project/\$PROJECT_VERSION/$file_name"
        }

        # Pattern: /core/config/tech/*/v1.0.0/ -> $FLOW_DIR/config/tech/$TECH_NAME/$TECH_VERSION/
        if {[regexp {^(.*/core)/config/tech/([^/]+)/v[0-9]+\.[0-9]+\.[0-9]+/(.+)$} $absolute_path -> base_path tech_name file_name]} {
            return "\$FLOW_DIR/config/tech/\$TECH_NAME/\$TECH_VERSION/$file_name"
        }

        # Pattern: /core/config/flow/v1.0.0/ -> $FLOW_DIR/config/flow/$FLOW_VERSION/
        if {[regexp {^(.*/core)/config/flow/v[0-9]+\.[0-9]+\.[0-9]+/(.+)$} $absolute_path -> base_path file_name]} {
            return "\$FLOW_DIR/config/flow/\$FLOW_VERSION/$file_name"
        }

        # Pattern: /core/config/eda/*/v1.0.0/ -> $FLOW_DIR/config/eda/flow_type/vendor/tool/$TOOL_VERSION/
        if {[regexp {^(.*/core)/config/eda/([^/]+)/([^/]+)/([^/]+)/v[0-9]+\.[0-9]+\.[0-9]+/(.+)$} $absolute_path -> base_path flow_type vendor tool file_name]} {
            return "\$FLOW_DIR/config/eda/$flow_type/$vendor/$tool/\$TOOL_VERSION/$file_name"
        }

        # Replace flow_dir with $FLOW_DIR for any remaining paths
        if {[string match "${flow_dir}*" $absolute_path]} {
            set relative_path [string range $absolute_path [string length $flow_dir] end]
            if {[string index $relative_path 0] eq "/"} {
                set relative_path [string range $relative_path 1 end]
            }
            return "\$FLOW_DIR/$relative_path"
        }

        # Replace run_dir with $RUN_DIR
        if {[string match "${run_dir}*" $absolute_path]} {
            set relative_path [string range $absolute_path [string length $run_dir] end]
            if {[string index $relative_path 0] eq "/"} {
                set relative_path [string range $relative_path 1 end]
            }
            return "\$RUN_DIR/$relative_path"
        }

        # Default: use the absolute path as fallback
        return "$absolute_path"
    }

    proc extract_override_variables {config_content} {
        set variables {}
        set lines [split $config_content "\n"]

        foreach line $lines {
            set trimmed_line [string trim $line]

            # Skip empty lines and comments
            if {$trimmed_line eq "" || [string match "#*" $trimmed_line]} {
                continue
            }

            # Extract array variable assignments: set array_name(key) value
            if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*([^)]+)\s*\)\s+} $trimmed_line -> array_name key]} {
                lappend variables [list "${array_name}($key)" $array_name $key]
            } elseif {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+} $trimmed_line -> var_name]} {
                # Extract simple variable assignments: set var_name value
                lappend variables [list $var_name $var_name ""]
            }
        }

        return $variables
    }

    proc separate_override_content {file_path label} {
        if {![file exists $file_path]} {
            return [list "" ""]
        }

        if {[catch {open $file_path r} fp]} {
            return [list "" ""]
        }

        set content [read $fp]
        close $fp

        set config_lines {}
        set setup_lines {}

        # Split content into lines for processing
        set lines [split $content "\n"]
        set current_section "config"  ;# Default to config section
        set in_flow_proc_block false
        set in_proc_block false
        set brace_depth 0

        foreach line $lines {
            set trimmed_line [string trim $line]

            # Skip empty lines and comments (they go to both)
            if {$trimmed_line eq "" || [string match "#*" $trimmed_line]} {
                lappend config_lines $line
                lappend setup_lines $line
                continue
            }

            # Track brace depth for multi-line blocks
            set open_braces [regexp -all {\{} $line]
            set close_braces [regexp -all {\}} $line]
            set brace_depth [expr {$brace_depth + $open_braces - $close_braces}]

            # Check for flow_proc related commands (prepend, append, replace)
            if {[regexp {^\s*(flow_proc_(prepend|append|replace)|flow_proc\s+(prepend|append|replace))} $trimmed_line]} {
                set current_section "setup"
                set in_flow_proc_block true
                lappend setup_lines $line
            } elseif {[regexp {^\s*(proc\s+)} $trimmed_line]} {
                # Regular proc definitions go to setup
                set current_section "setup"
                set in_proc_block true
                lappend setup_lines $line
            } elseif {[regexp {^\s*(set\s+)} $trimmed_line]} {
                # Variable assignments go to config (unless inside flow_proc block)
                if {!$in_flow_proc_block && !$in_proc_block} {
                    set current_section "config"
                    lappend config_lines $line
                } else {
                    lappend setup_lines $line
                }
            } elseif {[regexp {^\s*(namespace\s+eval|if\s*\{|while\s*\{|for\s*\{|foreach\s*\{)} $trimmed_line]} {
                # Control structures and namespaces follow current section
                if {$current_section eq "setup"} {
                    lappend setup_lines $line
                } else {
                    lappend config_lines $line
                }
            } else {
                # Other content goes to current section
                if {$current_section eq "setup"} {
                    lappend setup_lines $line
                } else {
                    lappend config_lines $line
                }
            }

            # Reset section flags when blocks end
            if {$brace_depth == 0} {
                set in_flow_proc_block false
                set in_proc_block false
                set current_section "config"  ;# Reset to default
            }
        }

        # Convert back to strings with proper headers
        set config_content ""
        set setup_content ""

        if {[llength $config_lines] > 0} {
            # Add header and join lines
            set config_content "# $label - CONFIG VARIABLES - $file_path\n[join $config_lines "\n"]\n"
        }

        if {[llength $setup_lines] > 0} {
            # Add header and join lines
            set setup_content "# $label - FLOW_PROC HOOKS - $file_path\n[join $setup_lines "\n"]\n"
        }

        return [list $config_content $setup_content]
    }

    # ┌─ File Generation Functions ───────────────────────────────────────────────┐

    proc generate_setup_file {flow_dir run_dir flow_type node_type node_name} {
        # Use a list to collect lines, then join them - much cleaner than string escaping
        set lines {}

        # Add header
        lappend lines "#!/usr/bin/env tclsh"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# CBFlow - Setup Hooks for $flow_type $node_type ($node_name)"
        lappend lines "# Generated: [clock format [clock seconds]]"
        lappend lines "# Description: flow_proc hooks only (NO configuration variables)"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        # Add basic environment and logging
        lappend lines "# CBFlow setup file - configuration is loaded separately"
        lappend lines ""

        # Add environment - use environment variables instead of hardcoding
        lappend lines "# Use environment variables from .run.cbflow.env"
        lappend lines "if {\[info exists ::env(FLOW_DIR)\]} {"
        lappend lines "    set FLOW_DIR \$::env(FLOW_DIR)"
        lappend lines "} else {"
        lappend lines "    set FLOW_DIR \"$flow_dir\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(PROJECT_ROOT)\]} {"
        lappend lines "    set ROOT_DIR \$::env(PROJECT_ROOT)"
        lappend lines "} else {"
        lappend lines "    set ROOT_DIR \"\[file dirname \$FLOW_DIR\]\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(RUN_DIR)\]} {"
        lappend lines "    set RUN_DIR \$::env(RUN_DIR)"
        lappend lines "} else {"
        lappend lines "    set RUN_DIR \"$run_dir\""
        lappend lines "}"
        lappend lines ""

        # Global arrays
        if {$flow_type eq "SYNTH"} {
            lappend lines "global synth project tech flow"
        } elseif {$flow_type eq "SYNTH_PNR"} {
            lappend lines "global synth_pnr synth pnr project tech flow"
        } else {
            lappend lines "global pnr project tech flow"
        }
        lappend lines ""

        lappend lines "puts \"INFO: Setup hooks for $flow_type $node_type ($node_name)\""
        lappend lines ""

        # Add flow_proc hook precedence explanation
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# FLOW_PROC HOOK EXECUTION ORDER AND PRECEDENCE"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# This file contains flow_proc hooks that execute in hierarchical order:"
        lappend lines "# 1. Global setup (lowest priority) - applies to ALL nodes in ALL flows"
        lappend lines "# 2. Flow-specific setup - applies to all nodes in this flow type"
        lappend lines "# 3. Tool-specific setup - applies to specific EDA tool"
        lappend lines "# 4. Stage-specific setup - applies to specific flow stage"
        lappend lines "# 5. Override setup (highest priority) - user customizations"
        lappend lines "#"
        lappend lines "# Within each level, hooks execute in order: prepend -> main -> append"
        lappend lines "# Higher priority levels can override lower levels using flow_proc replace"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        # Get setup files and expand them
        set setup_files [get_hierarchical_setup_paths $flow_dir $run_dir $flow_type $node_type $node_name]

        foreach setup_entry $setup_files {
            lassign $setup_entry label file_path

            # Check if this is an override file that needs separation
            if {[string match "*override*" $label]} {
                # Use separation logic for override files
                lassign [separate_override_content $file_path $label] config_part setup_part

                if {$setup_part ne ""} {
                    lappend lines "# ───────────────────────────────────────────────────────────────────────────────"
                    lappend lines "# $label: $file_path (FLOW_PROCS ONLY)"
                    lappend lines "# ───────────────────────────────────────────────────────────────────────────────"
                    # Split setup_part by lines and add each line
                    foreach setup_line [split $setup_part "\n"] {
                        lappend lines $setup_line
                    }
                    lappend lines ""
                } else {
                    lappend lines "# $label: $file_path (NO FLOW_PROCS FOUND - SKIPPED)"
                    lappend lines ""
                }
            } else {
                # Use regular processing for non-override files
                lassign [read_file_content $file_path $label] exists content

                if {$exists} {
                    lappend lines "# ───────────────────────────────────────────────────────────────────────────────"
                    lappend lines "# $label: $file_path"
                    lappend lines "# ───────────────────────────────────────────────────────────────────────────────"
                    # Split content by lines and add each line
                    foreach content_line [split $content "\n"] {
                        lappend lines $content_line
                    }
                    lappend lines ""
                } else {
                    lappend lines "# $label: $file_path (NOT FOUND - SKIPPED)"
                    lappend lines ""
                }
            }
        }

        # Load command file (tool-specific with vendor and version).
        # Resolve the vendor dynamically — `cadence` was hard-coded; that's
        # wrong for synopsys tools (fc, pt, genus -> cadence, fm -> synopsys, etc.).
        # Build a tool→vendor map covering all tools the framework supports.
        set tool_name [get_tool_name $run_dir]
        # Tool→vendor map (kept in sync with cmds/<FLOW>/<vendor>/<tool>/ layout).
        array set _tool_vendor {
            fc            synopsys
            pt            synopsys
            fm            synopsys
            formality     synopsys
            icv           synopsys
            redhawk       synopsys
            vc_lp         synopsys
            power_compiler synopsys
            innovus       cadence
            genus         cadence
            tempus        cadence
            voltus        cadence
            joules        cadence
            conformal     cadence
            conformal_lp  cadence
            calibre       mentor
        }
        set tool_vendor [expr {[info exists _tool_vendor($tool_name)] ? $_tool_vendor($tool_name) : "synopsys"}]
        lappend lines "# Load tool-specific command file with all flow_proc hooks applied"
        lappend lines "set tool_name \"$tool_name\""
        lappend lines "set tool_vendor \"$tool_vendor\""
        # Strip trailing digits from node_type → stage_name (release_data1 → release_data)
        set stage_name [regsub -- {[0-9]+$} $node_type ""]
        lappend lines "# Resolve tool command file across discipline roots."
        lappend lines "# Try PD (\$FLOW_DIR) first, then any sibling disciplines (\$CBFLOW_DFT_DIR, ...)."
        # NOTE: setup.tcl historically emitted a `source $tool_cmd_path`
        # here. That was a bug: the cmd file sources setup.tcl, so
        # re-sourcing the cmd file from inside setup.tcl created an
        # infinite recursion. The subnode handler invokes the cmd file
        # directly (handler_run … $cmd_file …); setup.tcl is purely for
        # config + flow_proc hooks. Do NOT add a cmd-file source here.
        lappend lines "# setup.tcl: config + flow_proc hooks only. Cmd file is"
        lappend lines "# launched by the subnode handler — do NOT source it here."
        lappend lines ""

        return [join $lines "\n"]
    }

    proc generate_config_file {flow_dir run_dir flow_type node_type node_name} {
        # IMPROVED APPROACH: Source main configs, expand only overrides
        set lines {}

        # Add header
        lappend lines "#!/usr/bin/env tclsh"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# CBFlow - Consolidated Config for $flow_type $node_type ($node_name)"
        lappend lines "# Generated: [clock format [clock seconds]]"
        lappend lines "# Description: Main configs sourced, overrides expanded with validation"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        # Add environment setup
        lappend lines "# Environment setup"
        lappend lines "if {\[info exists ::env(FLOW_DIR)\]} {"
        lappend lines "    set FLOW_DIR \$::env(FLOW_DIR)"
        lappend lines "} else {"
        lappend lines "    set FLOW_DIR \"$flow_dir\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(RUN_DIR)\]} {"
        lappend lines "    set RUN_DIR \$::env(RUN_DIR)"
        lappend lines "} else {"
        lappend lines "    set RUN_DIR \"$run_dir\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(PROJECT_VERSION)\]} {"
        lappend lines "    set PROJECT_VERSION \$::env(PROJECT_VERSION)"
        lappend lines "} else {"
        lappend lines "    set PROJECT_VERSION \"v1.0.0\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(FLOW_VERSION)\]} {"
        lappend lines "    set FLOW_VERSION \$::env(FLOW_VERSION)"
        lappend lines "} else {"
        lappend lines "    set FLOW_VERSION \"v1.0.0\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(TECH_VERSION)\]} {"
        lappend lines "    set TECH_VERSION \$::env(TECH_VERSION)"
        lappend lines "} else {"
        lappend lines "    set TECH_VERSION \"v1.0.0\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(TECH_NAME)\]} {"
        lappend lines "    set TECH_NAME \$::env(TECH_NAME)"
        lappend lines "} else {"
        if {![info exists ::env(TECH_NAME)] || $::env(TECH_NAME) eq ""} {
            puts "ERROR: TECH_NAME environment variable not set"
            error "Missing required env: TECH_NAME"
        }
        set _tn $::env(TECH_NAME)
        lappend lines "    set TECH_NAME \"$_tn\""
        lappend lines "}"
        lappend lines "if {\[info exists ::env(TOOL_VERSION)\]} {"
        lappend lines "    set TOOL_VERSION \$::env(TOOL_VERSION)"
        lappend lines "} else {"
        lappend lines "    set TOOL_VERSION \"v1.0.0\""
        lappend lines "}"
        lappend lines ""

        # Global arrays
        if {$flow_type eq "SYNTH"} {
            lappend lines "global synth project tech flow"
        } elseif {$flow_type eq "SYNTH_PNR"} {
            lappend lines "global synth_pnr synth pnr project tech flow"
        } else {
            lappend lines "global pnr project tech flow"
        }
        lappend lines ""

        lappend lines "puts \"INFO: Loading consolidated config for $flow_type $node_type ($node_name)\""
        lappend lines ""

        # Get config files list
        set config_files [get_hierarchical_config_paths $flow_dir $run_dir $flow_type $node_type $node_name]

        # Separate main configs from override configs
        set main_configs {}
        set override_configs {}

        foreach config_entry $config_files {
            lassign $config_entry label file_path
            if {[string match "*override*" $label]} {
                lappend override_configs $config_entry
            } else {
                lappend main_configs $config_entry
            }
        }

        # 1. SOURCE main configuration files (efficient)
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# MAIN CONFIGURATION FILES (SOURCED)"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""

        foreach config_entry $main_configs {
            lassign $config_entry label file_path

            # Convert absolute paths to versioned variable paths
            set versioned_path [convert_to_versioned_path $file_path $flow_dir $run_dir]

            lappend lines "# Source $label"
            lappend lines "if {\[file exists \"$versioned_path\"\]} {"
            lappend lines "    puts \"INFO: Loading $label: $versioned_path\""
            lappend lines "    source \"$versioned_path\""
            lappend lines "} else {"
            lappend lines "    puts \"WARNING: $label not found: $versioned_path\""
            lappend lines "}"
            lappend lines ""
        }

        # 2. EXPAND override configuration files
        if {[llength $override_configs] > 0} {
            lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
            lappend lines "# OVERRIDE CONFIGURATION FILES"
            lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
            lappend lines ""

            foreach config_entry $override_configs {
                lassign $config_entry label file_path

                # Convert to versioned path
                set versioned_path [convert_to_versioned_path $file_path $flow_dir $run_dir]

                lappend lines "# Apply overrides from $label"
                lappend lines "if {\[file exists $versioned_path\]} {"

                # Extract and validate override content
                lassign [separate_override_content $file_path $label] config_part setup_part

                if {$config_part ne ""} {
                    # Extract variables being overridden for validation
                    set override_vars [extract_override_variables $config_part]

                    # Perform validation during generation (not in generated config)
                    set validation_passed true
                    set invalid_vars {}

                    # NOTE: Since we're generating the config before main configs are loaded,
                    # we'll do basic syntax validation here and defer full validation to runtime
                    foreach var $override_vars {
                        lassign $var var_name array_name key
                        # Basic syntax validation - just check for obvious issues
                        if {$array_name eq "" || [string match "*\{*" $array_name] || [string match "*\}*" $array_name]} {
                            lappend invalid_vars $var_name
                            set validation_passed false
                        }
                    }

                    if {$validation_passed} {
                        handle_info "Override validation passed for $label ([llength $override_vars] variables)"

                        # Add clean override application without validation clutter
                        lappend lines "    # Apply overrides from $label"
                        foreach config_line [split $config_part "\n"] {
                            if {[string trim $config_line] ne "" && ![string match "#*" [string trim $config_line]]} {
                                lappend lines "    $config_line"
                            } elseif {[string trim $config_line] ne ""} {
                                lappend lines $config_line
                            }
                        }
                        lappend lines ""
                    } else {
                        handle_error "Override validation failed for $label - invalid variables: $invalid_vars"
                        lappend lines "    # SKIPPED: $label (validation failed during generation)"
                        lappend lines ""
                    }
                } else {
                    lappend lines "    puts \"INFO: No config variables found in $label\""
                }

                lappend lines "}"
                lappend lines ""
            }
        }

        # ── Derived variables (backward compat — set AFTER all configs loaded) ──
        lappend lines ""
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines "# DERIVED VARIABLES (engine-generated from project + tech configs)"
        lappend lines "# ═══════════════════════════════════════════════════════════════════════════════"
        lappend lines ""
        lappend lines "# Active track and VT (from project_config)"
        lappend lines "set tech(track) \$project(track_variant)"
        lappend lines "set tech(vt_flavors_loaded) \$project(vt_flavors)"
        lappend lines ""
        lappend lines "# ── Resolve active metal stack into flat tech() vars ──"
        lappend lines "if {\[info exists project(metal_stack)\] && \$project(metal_stack) ne \"\"} {"
        lappend lines "    set _ms \$project(metal_stack)"
        lappend lines ""
        lappend lines "    # Tech LEF for active metal stack + track"
        lappend lines "    if {\[info exists tech(\$_ms,\$project(track_variant),lef_tech)\]} {"
        lappend lines "        set tech(lef_tech) \$tech(\$_ms,\$project(track_variant),lef_tech)"
        lappend lines "    }"
        lappend lines ""
        lappend lines "    # Metal stack properties"
        lappend lines "    foreach _var {metal_count metal_layers metal_stack_full tech_file min_routing_layer max_routing_layer clock_routing_layer_min clock_routing_layer_max pg_strap_layers pg_strap_secondary pg_ring_layer_h pg_ring_layer_v via_layers metal_fill_min_density metal_fill_max_density tluplus_map gds_layer_map_file antenna_rule_file signal_em_constraint_file stream_files_for_merge} {"
        lappend lines "        if {\[info exists tech(\$_ms,\$_var)\]} {"
        lappend lines "            set tech(\$_var) \$tech(\$_ms,\$_var)"
        lappend lines "        }"
        lappend lines "    }"
        lappend lines ""
        lappend lines "    # RC parasitic flat aliases"
        lappend lines "    foreach _corner {rc_max rc_typ rc_min rc_max_cworst} {"
        lappend lines "        foreach _fmt {tluplus nxtgrd qrc} {"
        lappend lines "            if {\[info exists tech(rcx,\$_ms,\$_corner,\$_fmt)\]} {"
        lappend lines "                set tech(rcx,\$_corner,\$_fmt) \$tech(rcx,\$_ms,\$_corner,\$_fmt)"
        lappend lines "            }"
        lappend lines "        }"
        lappend lines "    }"
        lappend lines "}"
        lappend lines ""
        lappend lines "# tech(lib_root) alias for backward compat with command files"
        lappend lines "if {\[info exists project(lib_root)\]} { set tech(lib_root) \$project(lib_root) }"
        lappend lines ""
        lappend lines "puts \"INFO: Consolidated configuration loading complete for $flow_type $node_type ($node_name)\""

        return [join $lines "\n"]
    }

    # ┌─ Command Line Interface ─────────────────────────────────────────────────┐

    proc show_help {} {
        puts "CBFlow Setup Generation (Refactored v[set [namespace current]::version])"
        puts "Usage: tclsh [info script] <flow_type> <node_type> <node_name> <run_dir>"
        puts ""
        puts "Arguments:"
        puts "  flow_type: SYNTH, PNR, FP, etc."
        puts "  node_type: stage name (synthesis, export_data, etc.)"
        puts "  node_name: unique identifier for this node instance"
        puts "  run_dir:   run directory containing setup files"
        puts ""
        puts "Generates:"
        puts "  <run_dir>/work/<flow_type>/<node_type>/run/setup.tcl (flow_proc hooks)"
        puts "  <run_dir>/work/<flow_type>/<node_type>/run/config.tcl (configuration variables)"
        puts ""
    }

    proc main {argc argv} {
        # Ensure global arrays are accessible
        if {![initialize_global_access]} {
            return 1
        }

        if {$argc != 4} {
            handle_error "Invalid number of arguments"
            show_help
            return 1
        }

        set flow_type [lindex $argv 0]
        set node_type [lindex $argv 1]
        set node_name [lindex $argv 2]
        set run_dir [lindex $argv 3]

        # Load run-specific configuration for flat mode support
        set env_files [list "$run_dir/.run.cbflow.tcl" "$run_dir/.cbflow.tcl"]
        foreach env_file $env_files {
            if {[file exists $env_file]} {
                if {[catch {source $env_file} error] == 0} {
                    handle_info "Loaded run configuration from [file tail $env_file]"
                    break
                } else {
                    handle_warning "Failed to load $env_file: $error"
                }
            }
        }

        # Validate flow_type from flow_config.tcl (not hardcoded)
        # Use fully-qualified global variable access to avoid namespace scoping issues
        set valid_flows {}
        catch {
            if {[info exists ::flow(types)]} {
                set valid_flows $::flow(types)
            }
        }
        if {[catch {llength $valid_flows} _vflen] || $_vflen == 0} {
            set valid_flows {}
            set _fc_ver "v1.0.0"
            catch { set _fc_ver $::env(FLOW_CONFIG_VERSION) }
            set _flow_dir ""
            catch { set _flow_dir $::env(FLOW_DIR) }
            if {$_flow_dir ne ""} {
                set fc_path "$_flow_dir/config/flow/$_fc_ver/flow_config.tcl"
                if {[file exists $fc_path]} {
                    catch {
                        set _fc [open $fc_path r]
                        set _content [read $_fc]
                        close $_fc
                        set _ob [format %c 123]
                        set _cb [format %c 125]
                        set _idx [string first "flow(types)" $_content]
                        if {$_idx >= 0} {
                            set _bstart [string first $_ob $_content $_idx]
                            set _bend [string first $_cb $_content [expr {$_bstart+1}]]
                            if {$_bstart >= 0 && $_bend > $_bstart} {
                                set valid_flows [string range $_content [expr {$_bstart+1}] [expr {$_bend-1}]]
                            }
                        }
                    }
                }
            }
        }
        if {[catch {llength $valid_flows} _vflen]} { set _vflen 0 }
        if {$_vflen > 0 && $flow_type ni $valid_flows} {
            handle_error "Invalid flow_type '$flow_type'. Must be one of: [join $valid_flows {, }]"
            return 1
        }

        # Validate node_type using flow configuration (flat mode aware)
        # Check if we're in flat mode
        set run_type "node"
        if {[info exists ::flow(run_type)]} {
            set run_type $::flow(run_type)
        }

        if {$run_type eq "flat"} {
            # In flat mode, check for merged node names
            set flow_key [string toupper $flow_type]
            set is_valid_merged_node false

            # Check if it's a merged node (ends with "_merged")
            if {[string match "*_merged" $node_type]} {
                # Check against flat_merged_nodes array
                if {[info exists ::flat_merged_nodes($flow_key)] && $::flat_merged_nodes($flow_key) eq $node_type} {
                    set is_valid_merged_node true
                }
            }

            # Get data nodes from flat_data_sequence
            set valid_nodes {}
            if {[info exists ::flat_data_sequence($flow_key)]} {
                set valid_nodes $::flat_data_sequence($flow_key)
            }

            # Add merged node if valid
            if {$is_valid_merged_node && [info exists ::flat_merged_nodes($flow_key)]} {
                lappend valid_nodes $::flat_merged_nodes($flow_key)
            }

            set flow_sequence $valid_nodes
        } else {
            # Regular mode - use base flow sequence
            set flow_sequence [get_base_flow_sequence $flow_type]
        }
        # Check node_type against flow_sequence (handle suffix mismatch:
        # flow_sequence may have suffixed names like inputs1 while node_type is inputs,
        # or node_type may be inputs1 while flow_sequence has inputs)
        set node_valid false
        # Strip numeric suffix from node_type for comparison
        regsub {[0-9]+$} $node_type "" node_type_base
        if {$node_type in $flow_sequence} {
            set node_valid true
        } elseif {$node_type_base in $flow_sequence} {
            set node_valid true
        } else {
            foreach seq_node $flow_sequence {
                regsub {[0-9]+$} $seq_node "" stripped
                if {$stripped eq $node_type || $stripped eq $node_type_base} {
                    set node_valid true
                    break
                }
            }
        }
        if {!$node_valid} {
            handle_error "Invalid node_type '$node_type' for $flow_type flow"
            handle_info "Valid $flow_type nodes: [join $flow_sequence {, }]"
            return 1
        }

        # Validate run directory
        if {![file exists $run_dir]} {
            handle_error "Run directory does not exist: $run_dir"
            return 1
        }

        handle_info "Expanding setup hooks and config variables for $flow_type $node_type ($node_name)..."
        handle_info "Run directory: $run_dir"

        # Create output directory structure
        set output_dir "$run_dir/work/$flow_type/$node_type/run"
        file mkdir $output_dir

        # Generate content - use environment variable for FLOW_DIR
        if {[info exists ::env(FLOW_DIR)]} {
            set flow_dir $::env(FLOW_DIR)
        } else {
            # Fallback: calculate from script location (less robust)
            variable script_dir
            set flow_dir [file dirname [file dirname [file dirname $script_dir]]]
            handle_warning "FLOW_DIR not set in environment, using calculated path: $flow_dir"
        }
        set setup_content [generate_setup_file $flow_dir $run_dir $flow_type $node_type $node_name]
        set config_content [generate_config_file $flow_dir $run_dir $flow_type $node_type $node_name]

        # Write files
        set setup_output_file "$output_dir/setup.tcl"
        set file_handle [open $setup_output_file w]
        puts $file_handle $setup_content
        close $file_handle

        set config_output_file "$output_dir/config.tcl"
        set config_file_handle [open $config_output_file w]
        puts $config_file_handle $config_content
        close $config_file_handle

        handle_info "Setup hooks file generated: $setup_output_file"
        handle_info "Config variables file generated: $config_output_file"

        # Add pause for XTerm display - keep window open so user can see the process
        puts ""
        puts "═══════════════════════════════════════════════════════════════════════════════"
        puts "Setup generation for $flow_type $node_type completed successfully!"
        puts "═══════════════════════════════════════════════════════════════════════════════"
        puts ""
        puts "Window will close automatically in 3 seconds..."
        flush stdout
        after 3000

        return 0
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

# Only run main if this script is executed directly (not sourced)
if {[info script] eq $argv0} {
    exit [::CBFlow::Generation::SetupGenerator::main $argc $argv]
}