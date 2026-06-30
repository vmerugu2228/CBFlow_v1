#!/usr/bin/env tclsh
#===============================================================================
# CBFlow LSF Utilities Framework
#
# Description: Comprehensive LSF management utilities for CBFlow
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - LSF queue management and job submission
# - Resource monitoring and analytics collection
# - Dynamic queue creation and management
# - Cost accounting per job
# - Performance monitoring and reporting
#===============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           NAMESPACE DEFINITION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::Utils {
    variable version "1.0.0"
    variable debug_mode false
    variable cache_expiry 300  ; # 5 minutes cache expiry

    # Cache for LSF data to improve performance
    variable cache
    array set cache {}

    # Statistics tracking
    variable stats
    array set stats {
        jobs_submitted 0
        jobs_completed 0
        jobs_failed 0
        total_cost 0.0
        total_runtime 0.0
    }
}

# Load required configurations and utilities
set script_dir [file dirname [file normalize [info script]]]

# Load error handling utilities
if {[file exists "$script_dir/error_utils.tcl"]} {
    source "$script_dir/error_utils.tcl"
} else {
    # Provide basic fallback procedures
    proc CBFLOW_INFO {msg {category ""}} { puts "INFO: $msg" }
    proc CBFLOW_WARNING {msg {category ""}} { puts "WARNING: $msg" }
    proc CBFLOW_ERROR {msg {category ""}} { puts "ERROR: $msg" }
    proc CBFLOW_DEBUG {msg {category ""}} { if {$::CBFlow::LSF::Utils::debug_mode} { puts "DEBUG: $msg" } }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       CONFIGURATION LOADING UTILITIES                       │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::Utils {

    #===========================================================================
    # CONFIGURATION MANAGEMENT
    #===========================================================================

    proc load_lsf_config {} {
        global lsf project

        # Try to load LSF configuration
        set config_paths {
            "$::env(CONFIG_ROOT)/flow/v1.0.0/lsf_config.tcl"
            "../config/flow/v1.0.0/lsf_config.tcl"
            "../../config/flow/v1.0.0/lsf_config.tcl"
        }

        foreach config_path $config_paths {
            set expanded_path [subst $config_path]
            if {[file exists $expanded_path]} {
                CBFLOW_INFO "Loading LSF configuration from: $expanded_path" "CONFIG"
                if {[catch {source $expanded_path} error]} {
                    CBFLOW_ERROR "Failed to load LSF configuration: $error" "CONFIG"
                    return false
                }
                return true
            }
        }

        CBFLOW_WARNING "LSF configuration not found in standard locations" "CONFIG"
        return false
    }

    proc get_project_lsf_config {key {default ""}} {
        global project

        set full_key "lsf,$key"
        if {[info exists project($full_key)]} {
            return $project($full_key)
        }
        return $default
    }

    proc get_lsf_config {key {default ""}} {
        global lsf

        if {[info exists lsf($key)]} {
            return $lsf($key)
        }
        return $default
    }

    #===========================================================================
    # QUEUE MANAGEMENT UTILITIES
    #===========================================================================

    proc get_available_queues {} {
        return [get_lsf_config "available_queues" {S M L XL ultra}]
    }

    proc get_queue_specifications {queue_type} {
        global lsf

        set specs {}
        foreach attr {memory cpu runtime_limit description priority cost_factor max_concurrent} {
            set key "queue_types,${queue_type},$attr"
            if {[info exists lsf($key)]} {
                dict set specs $attr $lsf($key)
            }
        }

        return $specs
    }

    proc get_recommended_queue_for_node {flow_type stage_name {design_characteristics {}}} {
        global lsf project

        # First check project-specific overrides
        set project_key "node_requirements,${flow_type},${stage_name},queue"
        set project_queue [get_project_lsf_config $project_key ""]

        if {$project_queue ne ""} {
            CBFLOW_DEBUG "Using project-specific queue '$project_queue' for ${flow_type}:${stage_name}" "QUEUE"
            return $project_queue
        }

        # Check flow mapping configuration
        set mapping_key "flow_mapping,${flow_type},${stage_name}"
        set mapped_queue [get_lsf_config $mapping_key ""]

        if {$mapped_queue ne ""} {
            return $mapped_queue
        }

        # Fallback to default queue
        set default_queue [get_lsf_config "default_queue" "M"]
        CBFLOW_DEBUG "Using default queue '$default_queue' for ${flow_type}:${stage_name}" "QUEUE"
        return $default_queue
    }

    proc upgrade_queue {current_queue} {
        set queue_hierarchy {S M L XL ultra}
        set current_index [lsearch $queue_hierarchy $current_queue]

        if {$current_index == -1 || $current_index >= [expr [llength $queue_hierarchy] - 1]} {
            return $current_queue
        }

        return [lindex $queue_hierarchy [expr $current_index + 1]]
    }

    proc downgrade_queue {current_queue} {
        set queue_hierarchy {S M L XL ultra}
        set current_index [lsearch $queue_hierarchy $current_queue]

        if {$current_index <= 0} {
            return $current_queue
        }

        return [lindex $queue_hierarchy [expr $current_index - 1]]
    }

    #===========================================================================
    # JOB SUBMISSION AND MANAGEMENT
    #===========================================================================

    proc submit_lsf_job {queue_type job_name command {options {}}} {
        global env

        # Get queue specifications
        set queue_specs [get_queue_specifications $queue_type]
        if {[dict size $queue_specs] == 0} {
            CBFLOW_ERROR "Invalid queue type: $queue_type" "LSF"
            return ""
        }

        # Build LSF submission command
        set lsf_cmd [build_lsf_submission_command $queue_type $job_name $command $options]

        # Log job submission
        CBFLOW_INFO "Submitting LSF job '$job_name' to queue '$queue_type'" "LSF"
        CBFLOW_DEBUG "LSF command: $lsf_cmd" "LSF"

        # Submit job
        if {[catch {exec {*}$lsf_cmd} job_output]} {
            CBFLOW_ERROR "LSF job submission failed: $job_output" "LSF"
            return ""
        }

        # Extract job ID from output
        set job_id [extract_job_id_from_output $job_output]

        if {$job_id ne ""} {
            # Record job submission
            record_job_submission $job_id $queue_type $job_name
            CBFLOW_INFO "LSF job submitted successfully with ID: $job_id" "LSF"
        }

        return $job_id
    }

    proc build_lsf_submission_command {queue_type job_name command options} {
        set queue_specs [get_queue_specifications $queue_type]

        set lsf_cmd [list "bsub"]

        # Add queue-specific resource requirements
        if {[dict exists $queue_specs memory]} {
            lappend lsf_cmd "-M" [dict get $queue_specs memory]
            lappend lsf_cmd "-R" "rusage[mem=[dict get $queue_specs memory]]"
        }

        if {[dict exists $queue_specs cpu]} {
            lappend lsf_cmd "-n" [dict get $queue_specs cpu]
        }

        if {[dict exists $queue_specs runtime_limit]} {
            lappend lsf_cmd "-W" [dict get $queue_specs runtime_limit]
        }

        # Add job name
        lappend lsf_cmd "-J" $job_name

        # Add queue name (if different from queue_type)
        set lsf_queue_name [get_lsf_config "lsf_integration,queue_prefix" "cbflow_"]$queue_type
        lappend lsf_cmd "-q" $lsf_queue_name

        # Add output and error files
        lappend lsf_cmd "-o" "${job_name}.lsf.out"
        lappend lsf_cmd "-e" "${job_name}.lsf.err"

        # Add additional options
        foreach {key value} $options {
            switch -- $key {
                "-depends" {
                    lappend lsf_cmd "-w" "done($value)"
                }
                "-notify" {
                    lappend lsf_cmd "-N"
                }
                "-exclusive" {
                    lappend lsf_cmd "-x"
                }
                default {
                    lappend lsf_cmd $key $value
                }
            }
        }

        # Add the actual command
        lappend lsf_cmd $command

        return $lsf_cmd
    }

    proc extract_job_id_from_output {lsf_output} {
        # Extract job ID from LSF output like "Job <12345> is submitted to queue <normal>."
        if {[regexp {Job <(\d+)>} $lsf_output match job_id]} {
            return $job_id
        }
        return ""
    }

    proc get_job_status {job_id} {
        variable cache

        # Check cache first
        set cache_key "job_status_$job_id"
        if {[info exists cache($cache_key)]} {
            set cache_data $cache($cache_key)
            set cache_time [dict get $cache_data timestamp]
            if {[expr [clock seconds] - $cache_time] < $::CBFlow::LSF::Utils::cache_expiry} {
                return [dict get $cache_data status]
            }
        }

        # Query LSF for job status
        if {[catch {exec bjobs $job_id} bjobs_output]} {
            CBFLOW_WARNING "Failed to get status for job $job_id: $bjobs_output" "LSF"
            return "UNKNOWN"
        }

        # Parse bjobs output
        set status [parse_bjobs_output $bjobs_output]

        # Cache the result
        set cache($cache_key) [dict create timestamp [clock seconds] status $status]

        return $status
    }

    proc parse_bjobs_output {bjobs_output} {
        # Parse bjobs output to extract job status
        set lines [split $bjobs_output "\n"]
        if {[llength $lines] >= 2} {
            set data_line [lindex $lines 1]
            set fields [split $data_line]
            if {[llength $fields] >= 3} {
                return [lindex $fields 2]  ; # Status is typically the 3rd field
            }
        }
        return "UNKNOWN"
    }

    proc wait_for_job_completion {job_id {timeout 3600}} {
        set start_time [clock seconds]

        while {[expr [clock seconds] - $start_time] < $timeout} {
            set status [get_job_status $job_id]

            switch -- $status {
                "DONE" {
                    CBFLOW_INFO "Job $job_id completed successfully" "LSF"
                    return "DONE"
                }
                "EXIT" {
                    CBFLOW_ERROR "Job $job_id failed" "LSF"
                    return "EXIT"
                }
                "UNKNOWN" {
                    CBFLOW_WARNING "Lost track of job $job_id" "LSF"
                    return "UNKNOWN"
                }
                default {
                    # Job is still running, wait before checking again
                    after 30000  ; # Wait 30 seconds
                }
            }
        }

        CBFLOW_WARNING "Job $job_id timed out after $timeout seconds" "LSF"
        return "TIMEOUT"
    }

    #===========================================================================
    # RESOURCE MONITORING AND ANALYTICS
    #===========================================================================

    proc collect_resource_usage_data {job_id} {
        # Collect resource usage data for completed jobs
        if {[catch {exec bacct -l $job_id} bacct_output]} {
            CBFLOW_WARNING "Failed to collect resource data for job $job_id" "ANALYTICS"
            return {}
        }

        return [parse_bacct_output $bacct_output]
    }

    proc parse_bacct_output {bacct_output} {
        set usage_data {}

        # Parse bacct output for resource usage metrics
        set lines [split $bacct_output "\n"]
        foreach line $lines {
            if {[regexp {CPU time used is (\d+\.\d+) seconds} $line match cpu_time]} {
                dict set usage_data cpu_time $cpu_time
            }
            if {[regexp {Max Memory : (\d+) MB} $line match max_memory]} {
                dict set usage_data max_memory $max_memory
            }
            if {[regexp {Average Memory : (\d+) MB} $line match avg_memory]} {
                dict set usage_data avg_memory $avg_memory
            }
            if {[regexp {Run time is (\d+) seconds} $line match run_time]} {
                dict set usage_data run_time $run_time
            }
        }

        return $usage_data
    }

    proc record_job_submission {job_id queue_type job_name} {
        variable stats

        incr stats(jobs_submitted)

        # Record job details for analytics
        set job_record [dict create \
            job_id $job_id \
            queue_type $queue_type \
            job_name $job_name \
            submit_time [clock seconds] \
            status "SUBMITTED" \
        ]

        # Store job record (this could be enhanced to use a database)
        set job_file "data/lsf_jobs.log"
        if {[file exists [file dirname $job_file]]} {
            set fp [open $job_file a]
            puts $fp [list [clock seconds] $job_record]
            close $fp
        }
    }

    proc update_job_completion_stats {job_id final_status usage_data} {
        variable stats

        switch -- $final_status {
            "DONE" {
                incr stats(jobs_completed)
            }
            "EXIT" {
                incr stats(jobs_failed)
            }
        }

        # Update cost and runtime statistics
        if {[dict exists $usage_data run_time]} {
            set stats(total_runtime) [expr $stats(total_runtime) + [dict get $usage_data run_time]]
        }

        # Calculate and add job cost
        set job_cost [calculate_job_cost_from_usage $usage_data]
        set stats(total_cost) [expr $stats(total_cost) + $job_cost]
    }

    #===========================================================================
    # COST CALCULATION AND OPTIMIZATION
    #===========================================================================

    proc calculate_job_cost_from_usage {usage_data} {
        if {![dict exists $usage_data run_time]} {
            return 0.0
        }

        set run_time_hours [expr [dict get $usage_data run_time] / 3600.0]
        set memory_gb 0
        set cpu_count 1

        if {[dict exists $usage_data max_memory]} {
            set memory_gb [expr [dict get $usage_data max_memory] / 1024.0]
        }

        # Get cost rates from configuration
        set cpu_cost_per_hour [get_lsf_config "cost_optimization,cost_per_cpu_hour" "0.50"]
        set memory_cost_per_gb_hour [get_lsf_config "cost_optimization,cost_per_gb_hour" "0.10"]

        set total_cost [expr $cpu_count * $cpu_cost_per_hour * $run_time_hours + \
                             $memory_gb * $memory_cost_per_gb_hour * $run_time_hours]

        return $total_cost
    }

    proc get_daily_cost_summary {} {
        variable stats

        set today [clock format [clock seconds] -format "%Y-%m-%d"]
        set summary [dict create \
            date $today \
            total_cost $stats(total_cost) \
            jobs_submitted $stats(jobs_submitted) \
            jobs_completed $stats(jobs_completed) \
            jobs_failed $stats(jobs_failed) \
            success_rate [expr $stats(jobs_submitted) > 0 ? \
                double($stats(jobs_completed)) / $stats(jobs_submitted) : 0.0] \
        ]

        return $summary
    }

    #===========================================================================
    # DYNAMIC QUEUE MANAGEMENT
    #===========================================================================

    proc create_dynamic_queue {template_name queue_name} {
        global lsf

        if {![get_lsf_config "dynamic_queues,enabled" "false"]} {
            CBFLOW_WARNING "Dynamic queue creation is disabled" "DYNAMIC"
            return false
        }

        # Get template specifications
        set template_prefix "dynamic_templates,$template_name"
        set memory [get_lsf_config "$template_prefix,memory" ""]
        set cpu [get_lsf_config "$template_prefix,cpu" ""]
        set runtime_limit [get_lsf_config "$template_prefix,runtime_limit" ""]

        if {$memory eq "" || $cpu eq "" || $runtime_limit eq ""} {
            CBFLOW_ERROR "Invalid dynamic queue template: $template_name" "DYNAMIC"
            return false
        }

        # Create LSF queue configuration command
        set queue_cmd [list "bconf" "create" "queue" $queue_name]
        lappend queue_cmd "-mem" $memory
        lappend queue_cmd "-cpu" $cpu
        lappend queue_cmd "-runtime" $runtime_limit

        CBFLOW_INFO "Creating dynamic queue '$queue_name' from template '$template_name'" "DYNAMIC"

        if {[catch {exec {*}$queue_cmd} queue_output]} {
            CBFLOW_ERROR "Failed to create dynamic queue: $queue_output" "DYNAMIC"
            return false
        }

        CBFLOW_INFO "Dynamic queue '$queue_name' created successfully" "DYNAMIC"
        return true
    }

    proc cleanup_idle_dynamic_queues {} {
        set idle_time_threshold [get_lsf_config "dynamic_queues,cleanup_idle_time" "3600"]

        # This is a placeholder - would need to query LSF for actual queue usage
        CBFLOW_DEBUG "Checking for idle dynamic queues (threshold: ${idle_time_threshold}s)" "DYNAMIC"

        # Implementation would query LSF for queues created by this system
        # and remove those that have been idle for longer than the threshold
    }

    #===========================================================================
    # INTEGRATION UTILITIES
    #===========================================================================

    proc generate_lsf_makefile_target {flow_type stage_name target_name command} {
        set queue_type [get_recommended_queue_for_node $flow_type $stage_name]
        set job_name "${flow_type}_${stage_name}_${target_name}"

        set makefile_content ""
        append makefile_content "$target_name:\n"
        append makefile_content "\t@echo \"Submitting $target_name to LSF queue $queue_type\"\n"
        append makefile_content "\t@lsf_job_id=\$(shell tclsh -c 'source \$(UTILS_ROOT)/lsf_utils.tcl; \\\n"
        append makefile_content "\t\tset job_id \[::CBFlow::LSF::Utils::submit_lsf_job \"$queue_type\" \"$job_name\" \"$command\"\]; \\\n"
        append makefile_content "\t\tputs \$job_id'); \\\n"
        append makefile_content "\techo \"Job ID: \$\$lsf_job_id\"; \\\n"
        append makefile_content "\ttclsh -c 'source \$(UTILS_ROOT)/lsf_utils.tcl; \\\n"
        append makefile_content "\t\t::CBFlow::LSF::Utils::wait_for_job_completion \"\$\$lsf_job_id\"'\n"
        append makefile_content "\n"

        return $makefile_content
    }

    proc launch_lsf_xterm {queue_type job_name command {xterm_options {}}} {
        # Integrate LSF job submission with xterm display
        set job_id [submit_lsf_job $queue_type $job_name $command]

        if {$job_id eq ""} {
            CBFLOW_ERROR "Failed to submit LSF job for xterm session" "XTERM"
            return false
        }

        # Launch xterm to monitor the job
        set xterm_cmd [list "xterm"]
        lappend xterm_cmd "-title" "LSF Job $job_id - $job_name"

        # Add custom xterm options
        foreach {key value} $xterm_options {
            lappend xterm_cmd $key $value
        }

        # Command to monitor the job in xterm
        set monitor_cmd "watch -n 10 'bjobs $job_id && echo && bacct $job_id 2>/dev/null | tail -20'"
        lappend xterm_cmd "-e" $monitor_cmd

        CBFLOW_INFO "Launching xterm to monitor LSF job $job_id" "XTERM"

        if {[catch {exec {*}$xterm_cmd &} xterm_error]} {
            CBFLOW_WARNING "Failed to launch xterm for job monitoring: $xterm_error" "XTERM"
        }

        return $job_id
    }

    #===========================================================================
    # REPORTING AND STATISTICS
    #===========================================================================

    proc generate_lsf_usage_report {} {
        variable stats

        set report ""
        append report "CBFlow LSF Usage Report\n"
        append report "========================\n"
        append report "Generated: [clock format [clock seconds]]\n\n"

        append report "Job Statistics:\n"
        append report "  Jobs Submitted: $stats(jobs_submitted)\n"
        append report "  Jobs Completed: $stats(jobs_completed)\n"
        append report "  Jobs Failed: $stats(jobs_failed)\n"

        if {$stats(jobs_submitted) > 0} {
            set success_rate [expr 100.0 * $stats(jobs_completed) / $stats(jobs_submitted)]
            append report "  Success Rate: [format %.1f $success_rate]%\n"
        }

        append report "\nResource Usage:\n"
        append report "  Total Runtime: [format %.1f [expr $stats(total_runtime) / 3600.0]] hours\n"
        append report "  Total Cost: \$[format %.2f $stats(total_cost)]\n"

        if {$stats(jobs_completed) > 0} {
            set avg_cost [expr $stats(total_cost) / $stats(jobs_completed)]
            append report "  Average Cost per Job: \$[format %.2f $avg_cost]\n"
        }

        return $report
    }

    proc print_lsf_status {} {
        puts [generate_lsf_usage_report]
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            PUBLIC INTERFACE                                │
# └─────────────────────────────────────────────────────────────────────────────┘

# Export main procedures to global namespace for easy access
proc lsf_submit_job {queue_type job_name command {options {}}} {
    return [::CBFlow::LSF::Utils::submit_lsf_job $queue_type $job_name $command $options]
}

proc lsf_get_job_status {job_id} {
    return [::CBFlow::LSF::Utils::get_job_status $job_id]
}

proc lsf_wait_for_completion {job_id {timeout 3600}} {
    return [::CBFlow::LSF::Utils::wait_for_job_completion $job_id $timeout]
}

proc lsf_get_recommended_queue {flow_type stage_name {design_characteristics {}}} {
    return [::CBFlow::LSF::Utils::get_recommended_queue_for_node $flow_type $stage_name $design_characteristics]
}

proc lsf_generate_makefile_target {flow_type stage_name target_name command} {
    return [::CBFlow::LSF::Utils::generate_lsf_makefile_target $flow_type $stage_name $target_name $command]
}

proc lsf_launch_xterm {queue_type job_name command {xterm_options {}}} {
    return [::CBFlow::LSF::Utils::launch_lsf_xterm $queue_type $job_name $command $xterm_options]
}

proc lsf_print_status {} {
    ::CBFlow::LSF::Utils::print_lsf_status
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                             INITIALIZATION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

# Load LSF configuration on script load
if {[catch {::CBFlow::LSF::Utils::load_lsf_config} error]} {
    CBFLOW_WARNING "Failed to load LSF configuration: $error" "INIT"
} else {
    CBFLOW_INFO "CBFlow LSF utilities loaded successfully" "INIT"
}

# Enable debug mode if CBFLOW_DEBUG is set
if {[info exists ::env(CBFLOW_DEBUG)] && $::env(CBFLOW_DEBUG) ne "0"} {
    set ::CBFlow::LSF::Utils::debug_mode true
    CBFLOW_DEBUG "LSF utilities debug mode enabled" "INIT"
}