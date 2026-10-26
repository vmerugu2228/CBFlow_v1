#!/usr/bin/env tclsh

# LSF Integration Layer for CBFlow
# Provides seamless LSF integration with node execution and xterm

# Source required modules
source [file join [file dirname [info script]] "lsf_utils.tcl"]
source [file join [file dirname [info script]] "lsf_dynamic_queues.tcl"]
source [file join [file dirname [info script]] "lsf_optimizer.tcl"]
source [file join [file dirname [info script]] "error_utils.tcl"]

namespace eval ::lsf::integration {
    variable config
    variable active_jobs [dict create]

    # Integration configuration
    array set config {
        enable_lsf_integration true
        auto_optimize_resources true
        enable_xterm_lsf true
        enable_node_lsf true
        fallback_to_local true
        debug_mode false
    }

    # Store original execution commands for fallback
    variable original_commands [dict create]
}

# Initialize LSF integration
proc ::lsf::integration::initialize {} {
    variable config

    CBFLOW_INFO "Initializing LSF integration layer" "LSF_INTEGRATION"

    # Load LSF configuration
    if {[load_lsf_configuration]} {
        CBFLOW_INFO "LSF configuration loaded successfully" "LSF_INTEGRATION"
    } else {
        CBFLOW_WARNING "LSF configuration not available, using fallback mode" "LSF_INTEGRATION"
        set config(enable_lsf_integration) false
    }

    # Override xterm execution if enabled
    if {$config(enable_xterm_lsf)} {
        override_xterm_execution
    }

    # Override node execution if enabled
    if {$config(enable_node_lsf)} {
        override_node_execution
    }

    return $config(enable_lsf_integration)
}

# Load LSF configuration from flow config
proc ::lsf::integration::load_lsf_configuration {} {
    global flow

    # Try to load LSF configuration
    set lsf_config_file ""
    if {[info exists flow(config_root)]} {
        set lsf_config_file [file join $flow(config_root) "flow" "v1.0.0" "lsf_config.tcl"]
    }

    if {$lsf_config_file eq "" || ![file exists $lsf_config_file]} {
        # Try alternative path
        set config_dirs [list \
            "$::env(FLOW_CONFIG)" \
        ]

        foreach config_dir $config_dirs {
            set test_file [file join $config_dir "lsf_config.tcl"]
            if {[file exists $test_file]} {
                set lsf_config_file $test_file
                break
            }
        }
    }

    if {$lsf_config_file eq "" || ![file exists $lsf_config_file]} {
        return false
    }

    if {[catch {source $lsf_config_file} error]} {
        CBFLOW_ERROR "Failed to load LSF configuration: $error" "LSF_INTEGRATION"
        return false
    }

    return true
}

# Override xterm execution to use LSF
proc ::lsf::integration::override_xterm_execution {} {
    variable original_commands

    # Store original exec command if not already stored
    if {![dict exists $original_commands "exec"]} {
        # Use rename to capture the original exec command
        dict set original_commands "exec" [info commands exec]
        rename exec ::lsf::integration::original_exec
    }

    # Create new exec command that intercepts xterm calls
    proc ::exec {args} {
        return [::lsf::integration::lsf_aware_exec {*}$args]
    }

    CBFLOW_INFO "XTerm execution override installed" "LSF_INTEGRATION"
}

# LSF-aware exec command
proc ::lsf::integration::lsf_aware_exec {args} {
    variable config

    # Check if this is an xterm execution
    set is_xterm false
    set xterm_args [list]

    foreach arg $args {
        if {[string match "*xterm*" $arg]} {
            set is_xterm true
            break
        }
        lappend xterm_args $arg
    }

    # If not xterm or LSF integration disabled, use original exec
    if {!$is_xterm || !$config(enable_lsf_integration)} {
        return [original_exec {*}$args]
    }

    # Extract xterm command information
    set xterm_info [parse_xterm_command $args]

    if {[dict size $xterm_info] == 0} {
        CBFLOW_WARNING "Failed to parse xterm command, using original execution" "LSF_INTEGRATION"
        return [original_exec {*}$args]
    }

    # Get current context for LSF allocation
    set context [get_execution_context]

    # Determine optimal LSF allocation
    set lsf_recommendation [get_lsf_recommendation_for_xterm $context $xterm_info]

    if {$lsf_recommendation eq ""} {
        CBFLOW_INFO "No LSF recommendation available, using local execution" "LSF_INTEGRATION"
        return [original_exec {*}$args]
    }

    # Execute xterm through LSF
    return [execute_xterm_with_lsf $xterm_info $lsf_recommendation]
}

# Parse xterm command to extract relevant information
proc ::lsf::integration::parse_xterm_command {args} {
    set xterm_info [dict create \
        title "" \
        geometry "" \
        background "" \
        command "" \
        working_dir $::env(CBFLOW_RUN_DIR) \
        run_in_background false \
    ]

    set i 0
    while {$i < [llength $args]} {
        set arg [lindex $args $i]

        switch -exact $arg {
            "xterm" {
                # Found xterm command
                dict set xterm_info found_xterm true
            }
            "-title" {
                incr i
                if {$i < [llength $args]} {
                    dict set xterm_info title [lindex $args $i]
                }
            }
            "-geometry" {
                incr i
                if {$i < [llength $args]} {
                    dict set xterm_info geometry [lindex $args $i]
                }
            }
            "-bg" {
                incr i
                if {$i < [llength $args]} {
                    dict set xterm_info background [lindex $args $i]
                }
            }
            "-e" {
                incr i
                if {$i < [llength $args]} {
                    dict set xterm_info command [lindex $args $i]
                }
            }
            "&" {
                dict set xterm_info run_in_background true
            }
        }
        incr i
    }

    return $xterm_info
}

# Get execution context for LSF allocation
proc ::lsf::integration::get_execution_context {} {
    global flow project

    set context [dict create \
        flow_type "" \
        stage_name "" \
        design_characteristics [dict create] \
        working_directory $::env(CBFLOW_RUN_DIR) \
    ]

    # Extract flow type
    if {[info exists flow(type)]} {
        dict set context flow_type $flow(type)
    }

    # Try to determine stage name from current directory or environment
    set current_dir [file tail $::env(CBFLOW_RUN_DIR)]
    if {[regexp {(\w+)_(\w+)} $current_dir -> flow_part stage_part]} {
        dict set context stage_name $stage_part
    }

    # Extract design characteristics if available
    if {[info exists project(design_size)]} {
        dict set context design_characteristics design_size $project(design_size)
    }

    return $context
}

# Get LSF recommendation for xterm execution
proc ::lsf::integration::get_lsf_recommendation_for_xterm {context xterm_info} {
    variable config

    if {!$config(auto_optimize_resources)} {
        # Use default queue based on flow type
        return [get_default_lsf_queue_for_context $context]
    }

    # Use optimizer to get recommendation
    set flow_type [dict get $context flow_type]
    set stage_name [dict get $context stage_name]
    set design_characteristics [dict get $context design_characteristics]

    if {$flow_type eq "" || $stage_name eq ""} {
        return [get_default_lsf_queue_for_context $context]
    }

    # Get optimization recommendation
    set optimization_result [::lsf::optimizer::optimize_resource_allocation $flow_type $stage_name $design_characteristics]

    if {[dict exists $optimization_result "queue_recommendation"]} {
        return [dict get $optimization_result "queue_recommendation"]
    }

    return [get_default_lsf_queue_for_context $context]
}

# Get default LSF queue based on context
proc ::lsf::integration::get_default_lsf_queue_for_context {context} {
    global project

    set flow_type [dict get $context flow_type]
    set stage_name [dict get $context stage_name]


    # Fallback based on flow type
    switch $flow_type {
        "PNR" { return "L" }
        "SYNTH" { return "M" }
        "FP" { return "S" }
        default { return "S" }
    }
}

# Execute xterm with LSF
proc ::lsf::integration::execute_xterm_with_lsf {xterm_info lsf_queue} {
    variable active_jobs

    set title [dict get $xterm_info title]
    set command [dict get $xterm_info command]
    set geometry [dict get $xterm_info geometry]
    set background [dict get $xterm_info background]

    CBFLOW_INFO "Executing xterm through LSF queue: $lsf_queue" "LSF_INTEGRATION"

    # Create LSF-wrapped xterm command
    set lsf_xterm_script [create_lsf_xterm_script $xterm_info]

    # Submit LSF job for xterm
    set job_name "cbflow_xterm_[clock seconds]"
    set lsf_job_id [::lsf::utils::submit_lsf_job $lsf_queue $job_name $lsf_xterm_script]

    if {$lsf_job_id eq ""} {
        CBFLOW_ERROR "Failed to submit xterm job to LSF, falling back to local execution" "LSF_INTEGRATION"
        return [original_exec xterm -title $title -geometry $geometry -bg $background -e $command &]
    }

    # Track the LSF job
    dict set active_jobs $lsf_job_id [dict create \
        type "xterm" \
        queue $lsf_queue \
        submit_time [clock seconds] \
        title $title \
    ]

    CBFLOW_INFO "XTerm job submitted to LSF with job ID: $lsf_job_id" "LSF_INTEGRATION"
    return $lsf_job_id
}

# Create LSF xterm script
proc ::lsf::integration::create_lsf_xterm_script {xterm_info} {
    set title [dict get $xterm_info title]
    set command [dict get $xterm_info command]
    set geometry [dict_get_default $xterm_info geometry "120x40"]
    set background [dict_get_default $xterm_info background "#ecfdf5"]

    # Create temporary script for LSF execution
    set script_file "/tmp/lsf_xterm_[clock seconds]_[pid].sh"

    set fp [open $script_file w]
    puts $fp "#!/bin/bash"
    puts $fp "# LSF XTerm execution script"
    puts $fp "set -e"
    puts $fp ""

    # Set up environment
    puts $fp "# Set up CBFlow environment"
    puts $fp "cd $::env(CBFLOW_RUN_DIR)"
    puts $fp ""

    # Check if DISPLAY is available for X11 forwarding
    puts $fp "# Check for X11 display"
    puts $fp "if \[ -z \"\$DISPLAY\" \]; then"
    puts $fp "    echo \"Warning: No DISPLAY environment variable set\""
    puts $fp "    echo \"XTerm may not display properly without X11 forwarding\""
    puts $fp "fi"
    puts $fp ""

    # Execute xterm command
    puts $fp "# Execute xterm command"
    puts $fp "exec xterm -title \"$title\" \\"
    puts $fp "           -geometry \"$geometry\" \\"
    puts $fp "           -bg \"$background\" \\"
    puts $fp "           -e \"$command\""

    close $fp

    # Make script executable
    file attributes $script_file -permissions 0755

    return $script_file
}

# Override node execution to use LSF
proc ::lsf::integration::override_node_execution {} {
    CBFLOW_INFO "Node execution LSF integration enabled" "LSF_INTEGRATION"

    # This would integrate with the node management system
    # For now, we provide utility functions that can be called by node handlers
}

# Submit node execution to LSF
proc ::lsf::integration::submit_node_to_lsf {flow_type stage_name command {options {}}} {
    variable active_jobs

    # Get LSF recommendation for this node
    set context [dict create \
        flow_type $flow_type \
        stage_name $stage_name \
        design_characteristics [dict create] \
    ]

    set lsf_queue [get_lsf_recommendation_for_node $context]

    if {$lsf_queue eq ""} {
        CBFLOW_WARNING "No LSF queue available for $flow_type:$stage_name" "LSF_INTEGRATION"
        return ""
    }

    # Create node execution script
    set node_script [create_node_execution_script $flow_type $stage_name $command $options]

    # Submit to LSF
    set job_name "cbflow_${flow_type}_${stage_name}_[clock seconds]"
    set lsf_job_id [::lsf::utils::submit_lsf_job $lsf_queue $job_name $node_script]

    if {$lsf_job_id ne ""} {
        dict set active_jobs $lsf_job_id [dict create \
            type "node" \
            flow_type $flow_type \
            stage_name $stage_name \
            queue $lsf_queue \
            submit_time [clock seconds] \
        ]

        CBFLOW_INFO "Node $flow_type:$stage_name submitted to LSF with job ID: $lsf_job_id" "LSF_INTEGRATION"
    }

    return $lsf_job_id
}

# Get LSF recommendation for node execution
proc ::lsf::integration::get_lsf_recommendation_for_node {context} {
    global project

    set flow_type [dict get $context flow_type]
    set stage_name [dict get $context stage_name]


    # Use optimizer if available
    if {[dict exists $context "design_characteristics"]} {
        set design_characteristics [dict get $context design_characteristics]
        set optimization_result [::lsf::optimizer::optimize_resource_allocation $flow_type $stage_name $design_characteristics]

        if {[dict exists $optimization_result "queue_recommendation"]} {
            return [dict get $optimization_result "queue_recommendation"]
        }
    }

    # Fallback to default
    return [get_default_lsf_queue_for_context $context]
}

# Create node execution script
proc ::lsf::integration::create_node_execution_script {flow_type stage_name command options} {
    set script_file "/tmp/lsf_node_${flow_type}_${stage_name}_[clock seconds]_[pid].sh"

    set fp [open $script_file w]
    puts $fp "#!/bin/bash"
    puts $fp "# LSF Node execution script for $flow_type:$stage_name"
    puts $fp "set -e"
    puts $fp ""

    # Set up environment
    puts $fp "# Set up CBFlow environment"
    puts $fp "cd $::env(CBFLOW_RUN_DIR)"
    puts $fp ""

    # Source environment files if available
    if {[file exists ".run.cbflow.env"]} {
        puts $fp "# Source CBFlow environment"
        puts $fp "if \[ -f \".run.cbflow.env\" \]; then"
        puts $fp "    source .run.cbflow.env"
        puts $fp "fi"
        puts $fp ""
    }

    # Execute the command
    puts $fp "# Execute node command"
    puts $fp "echo \"Starting $flow_type:$stage_name execution at \$(date)\""
    puts $fp "$command"
    puts $fp "echo \"Completed $flow_type:$stage_name execution at \$(date)\""

    close $fp

    # Make script executable
    file attributes $script_file -permissions 0755

    return $script_file
}

# Monitor LSF jobs
proc ::lsf::integration::monitor_active_jobs {} {
    variable active_jobs

    set completed_jobs [list]

    dict for {job_id job_info} $active_jobs {
        set job_status [::lsf::utils::get_job_status $job_id]

        if {$job_status eq "DONE" || $job_status eq "EXIT"} {
            lappend completed_jobs $job_id

            set job_type [dict get $job_info type]
            CBFLOW_INFO "LSF job $job_id ($job_type) completed with status: $job_status" "LSF_INTEGRATION"

            # Clean up temporary files if any
            cleanup_job_files $job_id $job_info
        }
    }

    # Remove completed jobs from tracking
    foreach job_id $completed_jobs {
        dict unset active_jobs $job_id
    }

    return [dict size $active_jobs]
}

# Clean up job-related files
proc ::lsf::integration::cleanup_job_files {job_id job_info} {
    # Clean up any temporary scripts or files created for this job
    set temp_files [glob -nocomplain "/tmp/lsf_*${job_id}*"]
    foreach temp_file $temp_files {
        if {[file exists $temp_file]} {
            file delete -force $temp_file
        }
    }
}

# Get integration status
proc ::lsf::integration::get_integration_status {} {
    variable config
    variable active_jobs

    return [dict create \
        lsf_enabled $config(enable_lsf_integration) \
        xterm_integration $config(enable_xterm_lsf) \
        node_integration $config(enable_node_lsf) \
        active_jobs_count [dict size $active_jobs] \
        auto_optimization $config(auto_optimize_resources) \
    ]
}

# Utility functions
proc ::lsf::integration::dict_get_default {dict_data key default_value} {
    if {[dict exists $dict_data $key]} {
        return [dict get $dict_data $key]
    } else {
        return $default_value
    }
}

# Public interface functions
proc ::lsf::integration::enable {} {
    variable config
    set config(enable_lsf_integration) true
    initialize
}

proc ::lsf::integration::disable {} {
    variable config
    set config(enable_lsf_integration) false
    CBFLOW_INFO "LSF integration disabled" "LSF_INTEGRATION"
}

proc ::lsf::integration::is_enabled {} {
    variable config
    return $config(enable_lsf_integration)
}

# Cleanup function
proc ::lsf::integration::cleanup {} {
    variable active_jobs

    # Cancel any active LSF jobs
    dict for {job_id job_info} $active_jobs {
        ::lsf::utils::cancel_job $job_id
    }

    # Clear active jobs
    set active_jobs [dict create]

    CBFLOW_INFO "LSF integration cleanup completed" "LSF_INTEGRATION"
}

# Auto-initialize if sourced
if {[info exists ::auto_initialize_lsf] && $::auto_initialize_lsf} {
    ::lsf::integration::initialize
}