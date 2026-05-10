#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW Release Data Management Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Description: Creates release packages with required files for different 
#              release types (synthesis, pnr_floorplan, pnr_placed, etc.)
#
# IMPORTANT: This script must be run from inside a valid OMNI FLOW run directory
#           (a directory containing .run.status, work/, logs/, reports/, etc.)
#
# Usage: tclsh release_data.tcl <tag_name> <release_type> [options]
#
# Arguments:
#   tag_name      - Release tag (e.g., v1.0, milestone_1, beta_2)
#   release_type  - Type of release (synthesis, pnr_init, pnr_placed, 
#                   pnr_routed, signoff, milestone)
#
# Options:
#   -notes <message>     - Add custom release notes
#   -archive             - Create compressed archive
#   -force               - Overwrite existing release
#   -run_dir <path>      - Specify run directory (default: current)
#   -flow_dir <path>     - Specify flow directory (default: ../flow)
#   -release_dir <path>  - Specify custom release base directory
#
# Examples:
#   tclsh release_data.tcl v1.0 pnr_init -notes "Initial PNR setup complete"
#   tclsh release_data.tcl milestone_1 signoff -archive -force
#
# ═══════════════════════════════════════════════════════════════════════════════

# Global variables
set script_version "1.0.0"
set tag_name ""
set release_type ""
set custom_notes ""
set force_overwrite false
if {[info exists ::env(RUN_DIR)]} {
    set run_dir $::env(RUN_DIR)
} else {
    set run_dir $::env(CBFLOW_RUN_DIR)
    puts "INFO: Using CBFLOW_RUN_DIR from environment: $run_dir"
}
set flow_dir ""
set release_base_dir ""
set node_name ""
set node_directory ""
set verbose true
set exit_milestone ""

# Statistics tracking
set total_files_required 0
set total_files_found 0
set total_files_copied 0
set total_optional_files 0
set total_optional_copied 0

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING AND VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

proc parse_arguments {args} {
    global tag_name release_type custom_notes force_overwrite
    global run_dir flow_dir release_base_dir node_name node_directory exit_milestone
    
    if {[llength $args] < 2} {
        show_usage
        exit 1
    }
    
    set tag_name [lindex $args 0]
    set release_type [lindex $args 1]
    
    # Parse optional arguments
    for {set i 2} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -exact $arg {
            "-notes" {
                incr i
                if {$i < [llength $args]} {
                    set custom_notes [lindex $args $i]
                } else {
                    puts "ERROR: -notes requires a message"
                    exit 1
                }
            }
            "-force" {
                set force_overwrite true
            }
            "-run_dir" {
                incr i
                if {$i < [llength $args]} {
                    set run_dir [lindex $args $i]
                } else {
                    puts "ERROR: -run_dir requires a path"
                    exit 1
                }
            }
            "-flow_dir" {
                incr i
                if {$i < [llength $args]} {
                    set flow_dir [lindex $args $i]
                } else {
                    puts "ERROR: -flow_dir requires a path"
                    exit 1
                }
            }
            "-release_dir" {
                incr i
                if {$i < [llength $args]} {
                    set release_base_dir [lindex $args $i]
                } else {
                    puts "ERROR: -release_dir requires a path"
                    exit 1
                }
            }
            "-node_name" {
                incr i
                if {$i < [llength $args]} {
                    set node_name [lindex $args $i]
                } else {
                    puts "ERROR: -node_name requires a node name"
                    exit 1
                }
            }
            "-directory" {
                incr i
                if {$i < [llength $args]} {
                    set node_directory [lindex $args $i]
                } else {
                    puts "ERROR: -directory requires a directory path"
                    exit 1
                }
            }
            "-m" - "-milestone" {
                incr i
                if {$i < [llength $args]} {
                    set exit_milestone [lindex $args $i]
                } else {
                    puts "ERROR: -m/-milestone requires a milestone name"
                    exit 1
                }
            }
            default {
                puts "ERROR: Unknown option: $arg"
                show_usage
                exit 1
            }
        }
    }
}

proc show_usage {} {
    global RELEASE_TYPES
    
    puts "Usage: tclsh release_data.tcl <tag_name> <release_type> \[options\]"
    puts ""
    puts "IMPORTANT: This script must be run from inside a valid OMNI FLOW run directory"
    puts ""
    puts "Arguments:"
    puts "  tag_name      - Release tag (e.g., v1.0, milestone_1, beta_2)"
    puts "  release_type  - Type of release:"
    
    # Load configuration to get release types
    if {![info exists RELEASE_TYPES]} {
        # Try to load flow config for release types
        set flow_dir "../flow"
        if {![file exists "$flow_dir/config/flow_config.tcl"]} {
            set flow_dir "flow"
        }
        if {[file exists "$flow_dir/config/flow_config.tcl"]} {
            source "$flow_dir/config/flow_config.tcl"
        }
    }
    
    if {[info exists RELEASE_TYPES]} {
        foreach release_type [lsort [array names RELEASE_TYPES]] {
            if {[dict exists $RELEASE_TYPES($release_type) description]} {
                set desc [dict get $RELEASE_TYPES($release_type) description]
                puts "                  $release_type - $desc"
            } else {
                puts "                  $release_type"
            }
        }
    } else {
        puts "                  synthesis    - Synthesis deliverables"
        puts "                  pnr_floorplan - PNR floorplan deliverables"
        puts "                  pnr_placed   - PNR placed design deliverables"
        puts "                  pnr_cts      - PNR clock tree synthesis deliverables"
        puts "                  pnr_postroute - PNR post-route deliverables"
        puts "                  pnr_signoff  - PNR signoff deliverables"
        puts "                  signoff      - Final signoff deliverables"
    }
    
    puts ""
    puts "Options:"
    puts "  -notes <message>     - Add custom release notes"
    puts "  -force               - Overwrite existing release"
    puts "  -m/-milestone <name> - Exit milestone (FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO)"
    puts "  -node_name <name>    - Specify node name for multi-node stages (e.g., floorplan1)"
    puts "  -directory <path>    - Specify node directory path (relative or absolute)"
    puts "  -run_dir <path>      - Specify run directory (default: current)"
    puts "  -flow_dir <path>     - Specify flow directory"
    puts "  -release_dir <path>  - Specify custom release base directory"
    puts ""
    puts "Multi-Node Examples:"
    puts "  tclsh release_data.tcl v1.0 pnr_floorplan -node_name floorplan1"
    puts "  tclsh release_data.tcl v1.0 pnr_floorplan -directory work/PNR/floorplan_custom"
    puts "  tclsh release_data.tcl v1.0 pnr_floorplan -directory /absolute/path/to/node"
    puts ""
    puts "Standard Examples:"
    puts "  tclsh release_data.tcl v1.0 pnr_floorplan -notes \"Floorplan complete\""
    puts "  tclsh release_data.tcl milestone_1 signoff -force"
    puts ""
    puts "Milestone Examples:"
    puts "  tclsh release_data.tcl v1.0 pnr_floorplan -m FP_EXIT"
    puts "  tclsh release_data.tcl v2.0 pnr_postroute -m PRO_EXIT -notes \"Post-route optimization complete\""
    puts "  tclsh release_data.tcl tapeout signoff -m BTO -force"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION LOADING
# ═══════════════════════════════════════════════════════════════════════════════

proc validate_run_directory {} {
    global run_dir
    
    # Check if we're in a valid run directory
    if {![file exists "$run_dir/.run.status"]} {
        puts "ERROR: This script must be run from inside a valid OMNI FLOW run directory"
        puts "ERROR: Missing required file: .run.status"
        puts ""
        puts "Current directory: [file normalize $run_dir]"
        puts ""
        puts "Expected run directory structure:"
        puts "  run_directory/"
        puts "  ├── .run.status           (run status file)"
        puts "  ├── .config.tcl           (consolidated configuration)"
        puts "  ├── work/                 (stage work directories)"
        puts "  ├── logs/                 (log files)"
        puts "  ├── reports/              (report files)"
        puts "  └── results/              (result files)"
        puts ""
        
        # Try to detect if we're in a flow directory or parent directory
        if {[file exists "$run_dir/flow"] && [file exists "$run_dir/flow/scripts"]} {
            puts "HINT: You appear to be in the project root directory."
            puts "      Please navigate to a run directory (e.g., run_PNR_run_001/)"
            puts ""
            puts "Available run directories:"
            set run_dirs [glob -nocomplain -type d "$run_dir/run_*"]
            if {[llength $run_dirs] > 0} {
                foreach dir $run_dirs {
                    set dirname [file tail $dir]
                    if {[file exists "$dir/.run.status"]} {
                        puts "  ✓ $dirname (valid run directory)"
                    } else {
                        puts "  ✗ $dirname (incomplete run directory)"
                    }
                }
            } else {
                puts "  No run directories found."
            }
        } elseif {[file exists "$run_dir/scripts"] && [file exists "$run_dir/config"]} {
            puts "HINT: You appear to be in the flow directory."
            puts "      Please navigate to a run directory."
        }
        
        puts ""
        puts "Please navigate to a valid run directory before executing this script."
        exit 1
    }
    
    # Check for other essential run directory components
    set required_dirs {"work" "logs" "reports" "results"}
    set missing_dirs {}
    
    foreach dir $required_dirs {
        if {![file exists "$run_dir/$dir"] || ![file isdirectory "$run_dir/$dir"]} {
            lappend missing_dirs $dir
        }
    }
    
    if {[llength $missing_dirs] > 0} {
        puts "WARNING: Some expected run directory components are missing:"
        foreach dir $missing_dirs {
            puts "  - $dir/"
        }
        puts ""
        puts "This may be a partial or incomplete run directory."
        puts "Continuing with release creation, but some files may not be found."
        puts ""
    }
    
    # Check if we have a valid configuration
    if {![file exists "$run_dir/.config.tcl"] && ![file exists "$run_dir/user_config.tcl"]} {
        puts "WARNING: No configuration file found (.config.tcl or user_config.tcl)"
        puts "This may indicate an incomplete run directory setup."
        puts ""
    }
    
    log_info "Validated run directory: $run_dir"
}

proc validate_and_resolve_node_directory {release_type} {
    global run_dir node_name node_directory
    
    # If user specified a directory, validate it exists
    if {$node_directory ne ""} {
        # Handle both absolute and relative paths
        if {[file pathtype $node_directory] eq "absolute"} {
            # For absolute paths, use directly
            if {![file exists $node_directory]} {
                puts "ERROR: Specified absolute node directory does not exist: $node_directory"
                exit 1
            }
            if {![file isdirectory $node_directory]} {
                puts "ERROR: Specified absolute path is not a directory: $node_directory"
                exit 1
            }
            # Convert absolute path to relative path from run_dir for consistency
            set relative_path [get_relative_path $run_dir $node_directory]
            log_info "Using specified absolute node directory: $node_directory (relative: $relative_path)"
            return $relative_path
        } else {
            # For relative paths, combine with run_dir
            if {![file exists "$run_dir/$node_directory"]} {
                puts "ERROR: Specified node directory does not exist: $node_directory"
                puts "Current run directory: $run_dir"
                exit 1
            }
            if {![file isdirectory "$run_dir/$node_directory"]} {
                puts "ERROR: Specified path is not a directory: $node_directory"
                exit 1
            }
            log_info "Using specified node directory: $node_directory"
            return $node_directory
        }
    }
    
    # Determine the base stage directory from release type
    set stage_map [dict create \
        "synthesis" "SYNTH/synthesis" \
        "pnr_floorplan" "PNR/floorplan" \
        "pnr_placed" "PNR/placement" \
        "pnr_cts" "PNR/cts" \
        "pnr_postroute" "PNR/post_route" \
        "pnr_signoff" "PNR/signoff" \
    ]
    
    if {![dict exists $stage_map $release_type]} {
        puts "ERROR: Unknown release type for node detection: $release_type"
        exit 1
    }
    
    set base_stage_path [dict get $stage_map $release_type]
    
    # If user specified a node name, use it
    if {$node_name ne ""} {
        set node_path "work/$base_stage_path"
        # Replace the default stage name with the specified node name
        set path_parts [split $base_stage_path "/"]
        set flow_type [lindex $path_parts 0]
        set node_path "work/$flow_type/$node_name"
        
        if {![file exists "$run_dir/$node_path"]} {
            puts "ERROR: Node directory does not exist: $node_path"
            puts "Available nodes for $flow_type:"
            list_available_nodes $flow_type
            exit 1
        }
        log_info "Using specified node: $node_name (path: $node_path)"
        return $node_path
    }
    
    # Auto-detect: look for default stage directory or list available options
    set default_path "work/$base_stage_path"
    if {[file exists "$run_dir/$default_path"]} {
        log_info "Using default stage directory: $default_path"
        return $default_path
    }
    
    # Look for alternative nodes
    set flow_type [lindex [split $base_stage_path "/"] 0]
    set available_nodes [find_available_nodes $flow_type [lindex [split $base_stage_path "/"] 1]]
    
    if {[llength $available_nodes] == 0} {
        puts "ERROR: No nodes found for release type: $release_type"
        puts "Expected directory: $default_path"
        list_available_nodes $flow_type
        exit 1
    } elseif {[llength $available_nodes] == 1} {
        set selected_node [lindex $available_nodes 0]
        log_info "Auto-selected single available node: $selected_node"
        return $selected_node
    } else {
        puts "ERROR: Multiple nodes found for release type: $release_type"
        puts "Please specify which node to use with -node_name or -directory option:"
        puts ""
        foreach node $available_nodes {
            set node_name_only [file tail $node]
            puts "  -node_name $node_name_only"
            puts "  -directory $node"
            puts ""
        }
        exit 1
    }
}

proc find_available_nodes {flow_type stage_pattern} {
    global run_dir
    
    set work_flow_dir "$run_dir/work/$flow_type"
    if {![file exists $work_flow_dir]} {
        return {}
    }
    
    set nodes {}
    set stage_dirs [glob -nocomplain -type d "$work_flow_dir/*"]
    foreach dir $stage_dirs {
        set dirname [file tail $dir]
        # Match stage pattern (e.g., "floorplan" matches "floorplan1", "floorplan_custom", etc.)
        if {[string match "*$stage_pattern*" $dirname]} {
            set relative_path "work/$flow_type/$dirname"
            lappend nodes $relative_path
        }
    }
    return [lsort $nodes]
}

proc list_available_nodes {flow_type} {
    global run_dir
    
    set work_flow_dir "$run_dir/work/$flow_type"
    if {![file exists $work_flow_dir]} {
        puts "  No work directory found: work/$flow_type"
        return
    }
    
    set stage_dirs [glob -nocomplain -type d "$work_flow_dir/*"]
    if {[llength $stage_dirs] == 0} {
        puts "  No stage directories found in: work/$flow_type"
        return
    }
    
    puts "  Available nodes in work/$flow_type:"
    foreach dir [lsort $stage_dirs] {
        set dirname [file tail $dir]
        puts "    $dirname"
    }
}

proc load_configuration {} {
    global run_dir flow_dir release_base_dir
    global project RELEASE_TYPES
    
    # Validate that we're in a proper run directory
    validate_run_directory
    
    # Auto-detect flow directory if not specified
    if {$flow_dir eq ""} {
        set flow_dir "../flow"
        if {![file exists "$flow_dir/utils/utils.tcl"]} {
            set flow_dir "flow"
            if {![file exists "$flow_dir/utils/utils.tcl"]} {
                puts "ERROR: Cannot find flow directory. Please specify with -flow_dir"
                exit 1
            }
        }
    }
    
    # Load utilities
    if {[file exists "$flow_dir/utils/utils.tcl"]} {
        source "$flow_dir/utils/utils.tcl"
    } else {
        puts "ERROR: Cannot find flow utilities at $flow_dir/utils/utils.tcl"
        exit 1
    }
    
    # Load consolidated configuration if available
    if {[file exists "$run_dir/.config.tcl"]} {
        source "$run_dir/.config.tcl"
        log_info "Loaded consolidated configuration from $run_dir/.config.tcl"
    }
    
    # Always load flow_config.tcl to ensure RELEASE_TYPES array is available
    if {[file exists "$flow_dir/config/flow_config.tcl"]} {
        source "$flow_dir/config/flow_config.tcl"
        log_info "Loaded flow configuration for release types"
    } else {
        puts "ERROR: Cannot find flow configuration at $flow_dir/config/flow_config.tcl"
        exit 1
    }
    
    # Load project configuration if not already loaded
    if {![info exists project(name)] && [file exists "$flow_dir/config/phoenix_config.tcl"]} {
        source "$flow_dir/config/phoenix_config.tcl"
        log_info "Loaded project configuration"
    }
    
    # Set release base directory from project configuration
    if {$release_base_dir eq ""} {
        if {[info exists project(release,base_dir)]} {
            set release_base_dir $project(release,base_dir)
        } else {
            set release_base_dir "releases"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE VALIDATION AND PREPARATION
# ═══════════════════════════════════════════════════════════════════════════════

proc validate_release_type {type} {
    global RELEASE_TYPES
    
    if {![info exists RELEASE_TYPES($type)]} {
        puts "ERROR: Unknown release type: $type"
        puts "Available release types:"
        foreach available_type [array names RELEASE_TYPES] {
            if {[dict exists $RELEASE_TYPES($available_type) description]} {
                set desc [dict get $RELEASE_TYPES($available_type) description]
                puts "  $available_type - $desc"
            } else {
                puts "  $available_type"
            }
        }
        exit 1
    }
    return true
}

proc get_release_type_for_milestone {milestone} {
    # Map milestone to appropriate release type
    array set milestone_to_release {
        FP_EXIT "pnr_floorplan"
        PLACE_EXIT "pnr_placed"
        CTS_EXIT "pnr_cts"
        PRO_EXIT "pnr_postroute"
        BTO "pnr_signoff"
        MTO "signoff"
    }
    
    if {[info exists milestone_to_release($milestone)]} {
        return $milestone_to_release($milestone)
    } else {
        puts "ERROR: Unknown milestone: $milestone"
        puts "Available milestones: FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO"
        exit 1
    }
}

proc process_milestone_release {milestone} {
    global flow_dir exit_milestone RELEASE_TYPES
    
    # Load milestone configuration
    set milestone_config_file "$flow_dir/config/exit/current/${milestone}_config.tcl"
    
    if {![file exists $milestone_config_file]} {
        puts "ERROR: Milestone configuration not found: $milestone_config_file"
        puts "Available milestones: FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO"
        exit 1
    }
    
    log_info "Loading milestone configuration: $milestone"
    source $milestone_config_file
    
    # Skip checks - release should only validate files, not run performance checks
    if {[info exists mandatory_checks]} {
        log_info "Milestone defines [array size mandatory_checks] mandatory checks (skipped for release)"
    }
    
    if {[info exists optional_checks]} {
        log_info "Milestone defines [array size optional_checks] optional checks (skipped for release)"
    }
    
    # Verify mandatory files exist and are not empty
    if {[info exists mandatory_files]} {
        log_info "Verifying mandatory milestone files..."
        set missing_files {}
        set empty_files {}
        
        foreach file $mandatory_files {
            if {![file exists $file]} {
                lappend missing_files $file
                log_error "  Missing: $file"
            } else {
                # Check if file is empty (size = 0)
                set file_size [file size $file]
                if {$file_size == 0} {
                    lappend empty_files $file
                    log_error "  Empty file (0 bytes): $file"
                } else {
                    # Convert size to human readable format
                    if {$file_size < 1024} {
                        set size_str "${file_size} bytes"
                    } elseif {$file_size < 1048576} {
                        set size_str "[format %.2f [expr {$file_size / 1024.0}]] KB"
                    } else {
                        set size_str "[format %.2f [expr {$file_size / 1048576.0}]] MB"
                    }
                    log_info "  Found: $file ($size_str)"
                }
            }
        }
        
        if {[llength $missing_files] > 0} {
            puts ""
            puts "ERROR: Missing mandatory files for milestone $milestone:"
            foreach file $missing_files {
                puts "  - $file"
            }
            return false
        }
        
        if {[llength $empty_files] > 0} {
            puts ""
            puts "ERROR: Empty files detected for milestone $milestone:"
            foreach file $empty_files {
                puts "  - $file (0 bytes)"
            }
            puts ""
            puts "Please ensure all files have valid content before creating release."
            return false
        }
    }
    
    # Process deliverables and add to existing release type
    set base_release_type [get_release_type_for_milestone $milestone]
    
    if {[info exists deliverables]} {
        log_info "Processing milestone deliverables..."
        
        # Add milestone deliverables to the base release type
        if {![info exists RELEASE_TYPES($base_release_type)]} {
            set RELEASE_TYPES($base_release_type) [dict create]
            dict set RELEASE_TYPES($base_release_type) description "Milestone $milestone deliverables"
            dict set RELEASE_TYPES($base_release_type) files [dict create]
        }
        
        # Get existing files if any
        set existing_files {}
        if {[dict exists $RELEASE_TYPES($base_release_type) files]} {
            set existing_files [dict get $RELEASE_TYPES($base_release_type) files]
        }
        
        # Add milestone-specific deliverables with validation
        set deliverable_issues {}
        foreach deliverable [array names deliverables] {
            set del_info $deliverables($deliverable)
            set source_file [lindex $del_info 0]
            set target_file [lindex $del_info 1]
            set file_type [lindex $del_info 2]
            
            # Check if deliverable source file exists and is not empty
            if {[file exists $source_file]} {
                set file_size [file size $source_file]
                if {$file_size == 0} {
                    lappend deliverable_issues "Empty: $source_file"
                    log_warning "  Deliverable '$deliverable' source is empty: $source_file"
                } else {
                    # Add to release files
                    dict set existing_files $source_file $target_file
                    if {$file_size < 1024} {
                        set size_str "${file_size}B"
                    } elseif {$file_size < 1048576} {
                        set size_str "[format %.1f [expr {$file_size / 1024.0}]]KB"
                    } else {
                        set size_str "[format %.1f [expr {$file_size / 1048576.0}]]MB"
                    }
                    log_info "  Added deliverable: $deliverable ($file_type, $size_str)"
                }
            } else {
                lappend deliverable_issues "Missing: $source_file"
                log_warning "  Deliverable '$deliverable' source not found: $source_file"
            }
        }
        
        # Update the release type with combined files
        dict set RELEASE_TYPES($base_release_type) files $existing_files
        
        if {[llength $deliverable_issues] > 0} {
            log_warning "Some deliverables have issues but continuing with available files"
        }
    }
    
    log_info "Milestone $milestone processing complete"
    return true
}

proc validate_required_files {type} {
    global RELEASE_TYPES run_dir total_files_required total_files_found
    global total_optional_files
    
    # Resolve the node directory first
    set node_path [validate_and_resolve_node_directory $type]
    
    set release_config $RELEASE_TYPES($type)
    set files_dict [dict get $release_config files]
    set missing_files {}
    set found_files {}
    
    # Check required files
    set empty_files {}
    dict for {source_file dest_file} $files_dict {
        incr total_files_required
        # Use resolved node path for file location
        set resolved_source_file [resolve_file_path $source_file $node_path]
        set full_source_path "$run_dir/$resolved_source_file"
        
        if {[file exists $full_source_path]} {
            # Check file size
            set file_size [file size $full_source_path]
            if {$file_size == 0} {
                lappend empty_files $resolved_source_file
                log_error "✗ Empty file (0 bytes): $resolved_source_file"
            } else {
                incr total_files_found
                lappend found_files $resolved_source_file
                # Format size for display
                if {$file_size < 1024} {
                    set size_str "${file_size}B"
                } elseif {$file_size < 1048576} {
                    set size_str "[format %.1f [expr {$file_size / 1024.0}]]KB"
                } else {
                    set size_str "[format %.1f [expr {$file_size / 1048576.0}]]MB"
                }
                log_info "✓ Found required file: $resolved_source_file ($size_str)"
            }
        } else {
            lappend missing_files $resolved_source_file
            log_error "✗ Missing required file: $resolved_source_file"
        }
    }
    
    # Check optional files
    if {[dict exists $release_config optional_files]} {
        set optional_dict [dict get $release_config optional_files]
        dict for {source_file dest_file} $optional_dict {
            incr total_optional_files
            # Use resolved node path for optional files too
            set resolved_source_file [resolve_file_path $source_file $node_path]
            set full_source_path "$run_dir/$resolved_source_file"
            
            if {[file exists $full_source_path]} {
                log_info "✓ Found optional file: $resolved_source_file"
            } else {
                log_warning "⚠ Optional file not found: $resolved_source_file"
            }
        }
    }
    
    # Report errors for missing or empty files
    set has_errors false
    
    if {[llength $missing_files] > 0} {
        puts ""
        puts "ERROR: Missing required files for release type '$type':"
        foreach file $missing_files {
            puts "  - $file"
        }
        set has_errors true
    }
    
    if {[llength $empty_files] > 0} {
        puts ""
        puts "ERROR: Empty files detected for release type '$type':"
        foreach file $empty_files {
            puts "  - $file (0 bytes)"
        }
        set has_errors true
    }
    
    if {$has_errors} {
        puts ""
        puts "Node directory used: $node_path"
        puts "Please ensure all required files are generated with valid content before creating release."
        return false
    }
    
    return true
}

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE CREATION
# ═══════════════════════════════════════════════════════════════════════════════

proc create_release_directory {tag} {
    global release_base_dir project force_overwrite
    
    # Get block name from project configuration
    set block_name "unknown_block"
    if {[info exists project(name)]} {
        set block_name $project(name)
    } elseif {[info exists project(top_module)]} {
        set block_name $project(top_module)
    }
    
    set release_path "$release_base_dir/$block_name/$tag"
    
    # Check if release already exists
    if {[file exists $release_path]} {
        if {!$force_overwrite} {
            puts "ERROR: Release directory already exists: $release_path"
            puts "Use -force to overwrite existing release"
            exit 1
        } else {
            log_warning "Overwriting existing release: $release_path"
            file delete -force $release_path
        }
    }
    
    # Create release directory structure
    file mkdir $release_path
    
    # Create subdirectories from project structure
    if {[info exists project(release,structure)]} {
        foreach subdir $project(release,structure) {
            file mkdir "$release_path/$subdir"
            log_info "Created directory: $release_path/$subdir"
        }
    }
    
    return $release_path
}

proc copy_release_files {type release_path} {
    global RELEASE_TYPES run_dir total_files_copied total_optional_copied
    
    # Resolve the node directory first
    set node_path [validate_and_resolve_node_directory $type]
    
    set release_config $RELEASE_TYPES($type)
    set files_dict [dict get $release_config files]
    
    # Copy required files
    dict for {source_file dest_file} $files_dict {
        # Use resolved node path for file location
        set resolved_source_file [resolve_file_path $source_file $node_path]
        set full_source_path "$run_dir/$resolved_source_file"
        set full_dest_path "$release_path/$dest_file"
        
        if {[file exists $full_source_path]} {
            # Ensure destination directory exists
            file mkdir [file dirname $full_dest_path]
            
            # Copy file
            file copy $full_source_path $full_dest_path
            incr total_files_copied
            log_info "Copied: $resolved_source_file → $dest_file"
        }
    }
    
    # Copy optional files if they exist
    if {[dict exists $release_config optional_files]} {
        set optional_dict [dict get $release_config optional_files]
        dict for {source_file dest_file} $optional_dict {
            # Use resolved node path for optional files too
            set resolved_source_file [resolve_file_path $source_file $node_path]
            set full_source_path "$run_dir/$resolved_source_file"
            
            # Handle wildcard patterns
            if {[string match "*\\**" $resolved_source_file]} {
                set matching_files [glob -nocomplain "$run_dir/$resolved_source_file"]
                foreach match $matching_files {
                    set relative_match [string range $match [string length "$run_dir/"] end]
                    set dest_name [file tail $match]
                    set full_dest_path "$release_path/$dest_file/$dest_name"
                    
                    file mkdir [file dirname $full_dest_path]
                    file copy $match $full_dest_path
                    incr total_optional_copied
                    log_info "Copied optional: $relative_match → $dest_file/$dest_name"
                }
            } else {
                if {[file exists $full_source_path]} {
                    set full_dest_path "$release_path/$dest_file"
                    file mkdir [file dirname $full_dest_path]
                    file copy $full_source_path $full_dest_path
                    incr total_optional_copied
                    log_info "Copied optional: $resolved_source_file → $dest_file"
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# README GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

proc generate_readme {type tag release_path} {
    global RELEASE_TYPES project custom_notes total_files_copied total_optional_copied
    global total_files_required total_optional_files run_dir
    
    # Get block name
    set block_name "unknown_block"
    if {[info exists project(name)]} {
        set block_name $project(name)
    } elseif {[info exists project(top_module)]} {
        set block_name $project(top_module)
    }
    
    set readme_path "$release_path/README.md"
    set fp [open $readme_path w]
    
    # Header
    puts $fp "# OMNI FLOW Release Package"
    puts $fp ""
    puts $fp "## Release Information"
    puts $fp ""
    puts $fp "| Field | Value |"
    puts $fp "|-------|--------|"
    puts $fp "| **Block Name** | $block_name |"
    puts $fp "| **Release Tag** | $tag |"
    puts $fp "| **Release Type** | $type |"
    
    if {[dict exists $RELEASE_TYPES($type) description]} {
        set description [dict get $RELEASE_TYPES($type) description]
        puts $fp "| **Description** | $description |"
    }
    
    puts $fp "| **Creation Date** | [clock format [clock seconds]] |"
    puts $fp "| **Run Directory** | $run_dir |"
    puts $fp "| **Release Directory** | [file normalize $release_path] |"
    
    if {[info exists project(name)]} {
        puts $fp "| **Project** | $project(name) |"
    }
    if {[info exists project(release,author)]} {
        puts $fp "| **Author** | $project(release,author) |"
    }
    if {[info exists project(release,organization)]} {
        puts $fp "| **Organization** | $project(release,organization) |"
    }
    
    puts $fp ""
    
    # Release statistics
    puts $fp "## Release Statistics"
    puts $fp ""
    puts $fp "| Metric | Count |"
    puts $fp "|--------|--------|"
    puts $fp "| **Required Files** | $total_files_copied / $total_files_required |"
    puts $fp "| **Optional Files** | $total_optional_copied / $total_optional_files |"
    puts $fp "| **Total Files Copied** | [expr $total_files_copied + $total_optional_copied] |"
    puts $fp ""
    
    # Custom notes
    if {$custom_notes ne ""} {
        puts $fp "## Release Notes"
        puts $fp ""
        puts $fp "$custom_notes"
        puts $fp ""
    }
    
    # File listings
    puts $fp "## Files Included"
    puts $fp ""
    
    # List all files in release
    set all_files [exec find $release_path -type f ! -name "README.md" | sort]
    foreach file $all_files {
        set relative_file [string range $file [string length "$release_path/"] end]
        set file_size [file size $file]
        set formatted_size [format_file_size $file_size]
        puts $fp "- \`$relative_file\` ($formatted_size)"
    }
    
    puts $fp ""
    puts $fp "## Directory Structure"
    puts $fp ""
    puts $fp "\`\`\`"
    puts $fp "$tag/"
    
    # Generate directory tree
    generate_directory_tree $release_path $fp "├── " "│   "
    
    puts $fp "\`\`\`"
    puts $fp ""
    
    # Footer
    puts $fp "---"
    puts $fp "*Generated by OMNI FLOW Release Management System v$::script_version*"
    
    close $fp
    log_info "Generated release documentation: README.md"
}

proc generate_directory_tree {path fp prefix next_prefix} {
    set items [glob -nocomplain -directory $path *]
    set items [lsort $items]
    
    for {set i 0} {$i < [llength $items]} {incr i} {
        set item [lindex $items $i]
        set basename [file tail $item]
        set is_last [expr {$i == [llength $items] - 1}]
        
        if {$basename eq "README.md"} {
            continue
        }
        
        if {[file isdirectory $item]} {
            puts $fp "${prefix}${basename}/"
            if {$is_last} {
                generate_directory_tree $item $fp "${next_prefix}└── " "${next_prefix}    "
            } else {
                generate_directory_tree $item $fp "${next_prefix}├── " "${next_prefix}│   "
            }
        } else {
            puts $fp "${prefix}${basename}"
        }
    }
}

proc format_file_size {size_bytes} {
    if {$size_bytes < 1024} {
        return "${size_bytes}B"
    } elseif {$size_bytes < 1048576} {
        return "[format "%.1f" [expr {$size_bytes / 1024.0}]]KB"
    } elseif {$size_bytes < 1073741824} {
        return "[format "%.1f" [expr {$size_bytes / 1048576.0}]]MB"
    } else {
        return "[format "%.1f" [expr {$size_bytes / 1073741824.0}]]GB"
    }
}


# ═══════════════════════════════════════════════════════════════════════════════
# LOGGING UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

proc log_info {message} {
    puts "\[INFO\] $message"
}

proc log_warning {message} {
    puts "\[WARNING\] $message"
}

proc log_error {message} {
    puts "\[ERROR\] $message"
}

# ═══════════════════════════════════════════════════════════════════════════════
# FILE PATH RESOLUTION UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

proc get_relative_path {base_dir target_dir} {
    # Convert both paths to normalized absolute paths
    set base_norm [file normalize $base_dir]
    set target_norm [file normalize $target_dir]
    
    # Split paths into components
    set base_parts [file split $base_norm]
    set target_parts [file split $target_norm]
    
    # Find common prefix
    set common_len 0
    set min_len [expr {min([llength $base_parts], [llength $target_parts])}]
    for {set i 0} {$i < $min_len} {incr i} {
        if {[lindex $base_parts $i] eq [lindex $target_parts $i]} {
            incr common_len
        } else {
            break
        }
    }
    
    # Build relative path
    set up_dirs [expr {[llength $base_parts] - $common_len}]
    set result_parts {}
    
    # Add "../" for each directory to go up
    for {set i 0} {$i < $up_dirs} {incr i} {
        lappend result_parts ".."
    }
    
    # Add remaining target path components
    set remaining_parts [lrange $target_parts $common_len end]
    set result_parts [concat $result_parts $remaining_parts]
    
    # Join with file separator
    if {[llength $result_parts] == 0} {
        return "."
    } else {
        return [join $result_parts "/"]
    }
}

proc resolve_file_path {source_file node_path} {
    # This function resolves file paths based on the node directory
    # It handles cases where the source file path needs to be adjusted
    # to use the resolved node path instead of default stage paths
    
    # If the source file starts with "work/", replace the stage path with node path
    if {[string match "work/*" $source_file]} {
        # Extract the relative path after the stage directory
        # For example: "work/PNR/floorplan/data/file.def" -> "data/file.def"
        set path_parts [split $source_file "/"]
        if {[llength $path_parts] >= 4} {
            # Skip "work", flow type (PNR/SYNTH), and stage name, keep the rest
            set relative_path [join [lrange $path_parts 3 end] "/"]
            return "$node_path/$relative_path"
        }
    }
    
    # For non-work paths (like logs/, reports/, etc.), return as-is
    # These are usually at the run directory level and don't depend on node
    return $source_file
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

proc main {args} {
    global tag_name release_type total_files_copied total_optional_copied
    global total_files_required total_optional_files
    
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts "OMNI FLOW Release Data Management"
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts ""
    
    # Parse command line arguments
    parse_arguments {*}$args
    
    # Load configuration
    log_info "Loading configuration..."
    load_configuration
    
    # Handle milestone-based release if specified
    global exit_milestone
    if {$exit_milestone ne ""} {
        # Get the appropriate release type for this milestone
        set milestone_release_type [get_release_type_for_milestone $exit_milestone]
        
        # Update release type if not already set correctly
        if {$release_type ne $milestone_release_type} {
            log_info "Release type set to '$milestone_release_type' for milestone $exit_milestone"
            set release_type $milestone_release_type
        }
        
        log_info "Processing milestone release: $exit_milestone"
        set result [process_milestone_release $exit_milestone]
        if {!$result} {
            puts "ERROR: Milestone processing failed"
            exit 1
        }
    }
    
    # Validate release type
    log_info "Validating release type: $release_type"
    validate_release_type $release_type
    
    # Validate required files
    log_info "Validating required files for release type '$release_type'..."
    if {![validate_required_files $release_type]} {
        exit 1
    }
    
    # Create release directory
    log_info "Creating release directory for tag: $tag_name"
    set release_path [create_release_directory $tag_name]
    
    # Copy files
    log_info "Copying files to release directory..."
    copy_release_files $release_type $release_path
    
    # Generate README
    log_info "Generating release documentation..."
    generate_readme $release_type $tag_name $release_path
    
    # Final summary
    puts ""
    # Get block name for display (same logic as create_release_directory)
    global project
    set block_name "unknown_block"
    if {[info exists project(name)]} {
        set block_name $project(name)
    } elseif {[info exists project(top_module)]} {
        set block_name $project(top_module)
    }
    
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts "RELEASE CREATION COMPLETED"
    puts "═══════════════════════════════════════════════════════════════════════════════"
    puts "Block Name:       $block_name"
    puts "Release Tag:      $tag_name"
    puts "Release Type:     $release_type"
    puts "Release Path:     $release_path"
    puts "Full Release Path: [file normalize $release_path]"
    puts "Files Copied:     $total_files_copied required + $total_optional_copied optional"
    puts "Total Files:      [expr $total_files_copied + $total_optional_copied]"
    
    puts ""
    puts "✓ Release creation successful!"
}

# Execute main function if script is run directly
if {[info exists argv0] && [file tail [info script]] eq [file tail $argv0]} {
    main {*}$argv
}