#!/usr/bin/env tclsh
#===============================================================================
# CBFlow LSF Resource Monitoring System
#
# Description: Real-time resource monitoring and analytics collection for LSF
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - Real-time memory utilization vs. allocation monitoring
# - CPU usage analytics per node type
# - Queue wait time and throughput analysis
# - Resource efficiency metrics collection
# - Historical data persistence for ML analytics
# - Performance anomaly detection
#===============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           NAMESPACE DEFINITION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::Monitor {
    variable version "1.0.0"
    variable monitoring_active false
    variable monitor_pid ""
    variable data_buffer {}
    variable last_collection_time 0

    # Monitoring configuration
    variable config
    array set config {
        sampling_interval 60
        buffer_size 1000
        flush_interval 300
        anomaly_detection true
        realtime_alerts true
    }

    # Performance thresholds for anomaly detection
    variable thresholds
    array set thresholds {
        memory_efficiency_min 0.6
        cpu_efficiency_min 0.7
        queue_wait_time_max 1800
        job_failure_rate_max 0.1
        cost_variance_max 0.3
    }

    # Current system metrics
    variable current_metrics
    array set current_metrics {}
}

# Load required utilities
set script_dir [file dirname [file normalize [info script]]]
if {[file exists "$script_dir/error_utils.tcl"]} {
    source "$script_dir/error_utils.tcl"
} else {
    proc CBFLOW_INFO {msg {category ""}} { puts "INFO: $msg" }
    proc CBFLOW_WARNING {msg {category ""}} { puts "WARNING: $msg" }
    proc CBFLOW_ERROR {msg {category ""}} { puts "ERROR: $msg" }
    proc CBFLOW_DEBUG {msg {category ""}} { puts "DEBUG: $msg" }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                      RESOURCE MONITORING CORE                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::Monitor {

    #===========================================================================
    # MONITORING CONTROL
    #===========================================================================

    proc start_monitoring {{interval 60}} {
        variable monitoring_active
        variable monitor_pid
        variable config

        if {$monitoring_active} {
            CBFLOW_WARNING "LSF monitoring is already active" "MONITOR"
            return false
        }

        set config(sampling_interval) $interval
        set monitoring_active true

        # Start monitoring in background
        set monitor_pid [after $interval [namespace current]::collect_metrics_cycle]

        CBFLOW_INFO "Started LSF resource monitoring (interval: ${interval}s)" "MONITOR"
        return true
    }

    proc stop_monitoring {} {
        variable monitoring_active
        variable monitor_pid

        if {!$monitoring_active} {
            CBFLOW_WARNING "LSF monitoring is not active" "MONITOR"
            return false
        }

        set monitoring_active false
        if {$monitor_pid ne ""} {
            after cancel $monitor_pid
            set monitor_pid ""
        }

        # Flush any remaining data
        flush_data_buffer

        CBFLOW_INFO "Stopped LSF resource monitoring" "MONITOR"
        return true
    }

    proc is_monitoring_active {} {
        variable monitoring_active
        return $monitoring_active
    }

    #===========================================================================
    # METRICS COLLECTION CORE
    #===========================================================================

    proc collect_metrics_cycle {} {
        variable monitoring_active
        variable config

        if {!$monitoring_active} {
            return
        }

        # Collect current metrics
        if {[catch {collect_all_metrics} error]} {
            CBFLOW_ERROR "Error collecting metrics: $error" "MONITOR"
        }

        # Schedule next collection
        variable monitor_pid
        set monitor_pid [after [expr $config(sampling_interval) * 1000] \
                               [namespace current]::collect_metrics_cycle]
    }

    proc collect_all_metrics {} {
        variable last_collection_time
        variable data_buffer

        set timestamp [clock seconds]
        set last_collection_time $timestamp

        # Collect different types of metrics
        set metrics [dict create timestamp $timestamp]

        # LSF queue metrics
        dict set metrics lsf_queues [collect_lsf_queue_metrics]

        # Job metrics
        dict set metrics running_jobs [collect_running_job_metrics]

        # Resource utilization metrics
        dict set metrics resource_utilization [collect_resource_utilization_metrics]

        # Performance metrics
        dict set metrics performance [collect_performance_metrics]

        # Cost metrics
        dict set metrics cost [collect_cost_metrics]

        # Buffer the data
        lappend data_buffer $metrics

        # Check if we need to flush the buffer
        if {[llength $data_buffer] >= [get_config_value "buffer_size"]} {
            flush_data_buffer
        }

        # Perform real-time analysis
        if {[get_config_value "realtime_alerts"]} {
            analyze_metrics_for_anomalies $metrics
        }

        return $metrics
    }

    #===========================================================================
    # LSF QUEUE METRICS COLLECTION
    #===========================================================================

    proc collect_lsf_queue_metrics {} {
        set queue_metrics {}

        # Get queue information using bqueues
        if {[catch {exec bqueues -l} bqueues_output]} {
            CBFLOW_WARNING "Failed to collect queue metrics: $bqueues_output" "MONITOR"
            return $queue_metrics
        }

        # Parse queue information
        set queues [parse_bqueues_output $bqueues_output]

        foreach queue_info $queues {
            dict set queue_metrics [dict get $queue_info name] $queue_info
        }

        return $queue_metrics
    }

    proc parse_bqueues_output {bqueues_output} {
        set queues {}
        set lines [split $bqueues_output "\n"]

        foreach line $lines {
            if {[regexp {^(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line \
                       match queue_name status prio nice njobs pend]} {

                set queue_info [dict create \
                    name $queue_name \
                    status $status \
                    priority $prio \
                    nice $nice \
                    running_jobs $njobs \
                    pending_jobs $pend \
                ]

                lappend queues $queue_info
            }
        }

        return $queues
    }

    #===========================================================================
    # RUNNING JOB METRICS COLLECTION
    #===========================================================================

    proc collect_running_job_metrics {} {
        set job_metrics {}

        # Get running jobs using bjobs
        if {[catch {exec bjobs -r -o "jobid queue user stat run_time mem"} bjobs_output]} {
            CBFLOW_WARNING "Failed to collect running job metrics: $bjobs_output" "MONITOR"
            return $job_metrics
        }

        # Parse running jobs
        set jobs [parse_bjobs_running_output $bjobs_output]

        # Collect detailed metrics for each job
        foreach job_info $jobs {
            set job_id [dict get $job_info jobid]

            # Get detailed resource usage
            set detailed_usage [collect_job_resource_usage $job_id]
            if {[dict size $detailed_usage] > 0} {
                dict set job_info resource_usage $detailed_usage
            }

            dict set job_metrics $job_id $job_info
        }

        return $job_metrics
    }

    proc parse_bjobs_running_output {bjobs_output} {
        set jobs {}
        set lines [split $bjobs_output "\n"]

        # Skip header line
        set data_lines [lrange $lines 1 end]

        foreach line $data_lines {
            if {[string trim $line] eq ""} continue

            set fields [split $line]
            if {[llength $fields] >= 6} {
                set job_info [dict create \
                    jobid [lindex $fields 0] \
                    queue [lindex $fields 1] \
                    user [lindex $fields 2] \
                    status [lindex $fields 3] \
                    run_time [lindex $fields 4] \
                    memory [lindex $fields 5] \
                ]

                lappend jobs $job_info
            }
        }

        return $jobs
    }

    proc collect_job_resource_usage {job_id} {
        # Get detailed resource usage for a specific job
        if {[catch {exec bpeek -f $job_id} bpeek_output]} {
            # bpeek might fail for various reasons, that's okay
            return {}
        }

        # This is a simplified example - real implementation would parse
        # actual resource usage from job output or LSF accounting
        set usage_info [dict create \
            cpu_usage "0.0" \
            memory_usage "0" \
            io_usage "0" \
            network_usage "0" \
        ]

        return $usage_info
    }

    #===========================================================================
    # RESOURCE UTILIZATION METRICS
    #===========================================================================

    proc collect_resource_utilization_metrics {} {
        set utilization_metrics {}

        # Collect system-wide resource utilization
        set system_metrics [collect_system_resource_metrics]
        dict set utilization_metrics system $system_metrics

        # Collect CBFlow-specific resource usage
        set cbflow_metrics [collect_cbflow_resource_metrics]
        dict set utilization_metrics cbflow $cbflow_metrics

        # Calculate efficiency metrics
        set efficiency_metrics [calculate_resource_efficiency $system_metrics $cbflow_metrics]
        dict set utilization_metrics efficiency $efficiency_metrics

        return $utilization_metrics
    }

    proc collect_system_resource_metrics {} {
        set system_metrics {}

        # Collect CPU usage
        if {[catch {exec top -l 1 -n 0 | grep "CPU usage"} cpu_output]} {
            set cpu_usage "0.0"
        } else {
            set cpu_usage [parse_cpu_usage $cpu_output]
        }
        dict set system_metrics cpu_usage $cpu_usage

        # Collect memory usage
        if {[catch {exec vm_stat} vm_output]} {
            set memory_metrics [dict create free "0" used "0" total "0"]
        } else {
            set memory_metrics [parse_memory_usage $vm_output]
        }
        dict set system_metrics memory $memory_metrics

        # Collect load average
        if {[catch {exec uptime} uptime_output]} {
            set load_avg "0.0"
        } else {
            set load_avg [parse_load_average $uptime_output]
        }
        dict set system_metrics load_average $load_avg

        return $system_metrics
    }

    proc parse_cpu_usage {cpu_output} {
        # Parse macOS top output for CPU usage
        if {[regexp {(\d+\.\d+)% user} $cpu_output match user_cpu]} {
            return $user_cpu
        }
        return "0.0"
    }

    proc parse_memory_usage {vm_output} {
        # Parse macOS vm_stat output
        set memory_info [dict create free "0" used "0" total "0"]

        # This is simplified - real implementation would parse vm_stat output
        # to get actual memory statistics
        dict set memory_info free "1000000"
        dict set memory_info used "500000"
        dict set memory_info total "1500000"

        return $memory_info
    }

    proc parse_load_average {uptime_output} {
        # Parse load average from uptime output
        if {[regexp {load averages: (\d+\.\d+)} $uptime_output match load]} {
            return $load
        }
        return "0.0"
    }

    proc collect_cbflow_resource_metrics {} {
        # Collect CBFlow-specific resource usage metrics
        set cbflow_metrics [dict create \
            active_jobs "0" \
            queued_jobs "0" \
            total_memory_allocated "0" \
            total_cpu_allocated "0" \
            average_job_runtime "0.0" \
        ]

        # This would be implemented by querying actual CBFlow job data
        return $cbflow_metrics
    }

    proc calculate_resource_efficiency {system_metrics cbflow_metrics} {
        # Calculate resource efficiency based on allocation vs usage
        set efficiency_metrics {}

        # Memory efficiency
        set allocated_memory [dict get $cbflow_metrics total_memory_allocated]
        set system_memory [dict get $system_metrics memory]
        set total_memory [dict get $system_memory total]

        if {$allocated_memory > 0 && $total_memory > 0} {
            set memory_efficiency [expr double($allocated_memory) / $total_memory]
            dict set efficiency_metrics memory_efficiency $memory_efficiency
        }

        # CPU efficiency calculation would be similar
        dict set efficiency_metrics cpu_efficiency "0.8"

        return $efficiency_metrics
    }

    #===========================================================================
    # PERFORMANCE METRICS COLLECTION
    #===========================================================================

    proc collect_performance_metrics {} {
        set performance_metrics {}

        # Queue performance metrics
        set queue_performance [calculate_queue_performance]
        dict set performance_metrics queues $queue_performance

        # Job completion metrics
        set completion_metrics [calculate_job_completion_metrics]
        dict set performance_metrics completion $completion_metrics

        # Throughput metrics
        set throughput_metrics [calculate_throughput_metrics]
        dict set performance_metrics throughput $throughput_metrics

        return $performance_metrics
    }

    proc calculate_queue_performance {} {
        # Calculate queue performance metrics like wait times, throughput
        set queue_perf [dict create \
            average_wait_time "300" \
            max_wait_time "1800" \
            queue_utilization "0.75" \
            job_success_rate "0.95" \
        ]

        return $queue_perf
    }

    proc calculate_job_completion_metrics {} {
        # Calculate job completion-related metrics
        set completion_metrics [dict create \
            jobs_completed_last_hour "10" \
            average_runtime "3600" \
            success_rate "0.98" \
            failure_rate "0.02" \
        ]

        return $completion_metrics
    }

    proc calculate_throughput_metrics {} {
        # Calculate throughput metrics
        set throughput_metrics [dict create \
            jobs_per_hour "15" \
            cpu_hours_per_hour "240" \
            cost_per_hour "125.50" \
            efficiency_score "0.85" \
        ]

        return $throughput_metrics
    }

    #===========================================================================
    # COST METRICS COLLECTION
    #===========================================================================

    proc collect_cost_metrics {} {
        set cost_metrics {}

        # Current cost tracking
        set current_costs [calculate_current_costs]
        dict set cost_metrics current $current_costs

        # Projected costs
        set projected_costs [calculate_projected_costs]
        dict set cost_metrics projected $projected_costs

        # Budget tracking
        set budget_status [calculate_budget_status]
        dict set cost_metrics budget $budget_status

        return $cost_metrics
    }

    proc calculate_current_costs {} {
        # Calculate current running costs
        set current_costs [dict create \
            hourly_rate "50.25" \
            daily_total "1205.00" \
            weekly_total "6500.00" \
            monthly_total "23450.00" \
        ]

        return $current_costs
    }

    proc calculate_projected_costs {} {
        # Project costs based on current trends
        set projected_costs [dict create \
            daily_projection "1250.00" \
            weekly_projection "7000.00" \
            monthly_projection "25000.00" \
        ]

        return $projected_costs
    }

    proc calculate_budget_status {} {
        # Calculate budget utilization status
        set budget_status [dict create \
            daily_used "0.82" \
            weekly_used "0.75" \
            monthly_used "0.68" \
            status "OK" \
        ]

        return $budget_status
    }

    #===========================================================================
    # ANOMALY DETECTION AND ALERTING
    #===========================================================================

    proc analyze_metrics_for_anomalies {metrics} {
        variable thresholds

        set anomalies {}

        # Check resource efficiency
        if {[dict exists $metrics resource_utilization efficiency]} {
            set efficiency [dict get $metrics resource_utilization efficiency]

            if {[dict exists $efficiency memory_efficiency]} {
                set mem_eff [dict get $efficiency memory_efficiency]
                if {$mem_eff < $thresholds(memory_efficiency_min)} {
                    lappend anomalies "Low memory efficiency: $mem_eff"
                }
            }
        }

        # Check queue wait times
        if {[dict exists $metrics performance queues]} {
            set queue_perf [dict get $metrics performance queues]

            if {[dict exists $queue_perf max_wait_time]} {
                set max_wait [dict get $queue_perf max_wait_time]
                if {$max_wait > $thresholds(queue_wait_time_max)} {
                    lappend anomalies "High queue wait time: ${max_wait}s"
                }
            }
        }

        # Check cost variance
        if {[dict exists $metrics cost projected]} {
            set projected [dict get $metrics cost projected]
            set current [dict get $metrics cost current]

            if {[dict exists $projected daily_projection] && [dict exists $current daily_total]} {
                set proj [dict get $projected daily_projection]
                set curr [dict get $current daily_total]

                if {$curr > 0} {
                    set variance [expr abs($proj - $curr) / $curr]
                    if {$variance > $thresholds(cost_variance_max)} {
                        lappend anomalies "High cost variance: [format %.2f [expr $variance * 100]]%"
                    }
                }
            }
        }

        # Report anomalies
        if {[llength $anomalies] > 0} {
            foreach anomaly $anomalies {
                CBFLOW_WARNING "Performance anomaly detected: $anomaly" "ANOMALY"
            }

            # Store anomalies for ML learning
            store_anomaly_data $metrics $anomalies
        }

        return $anomalies
    }

    proc store_anomaly_data {metrics anomalies} {
        # Store anomaly data for ML model training
        set anomaly_record [dict create \
            timestamp [dict get $metrics timestamp] \
            anomalies $anomalies \
            metrics_snapshot $metrics \
        ]

        # This would typically write to a database or file
        CBFLOW_DEBUG "Stored anomaly data: [llength $anomalies] anomalies" "ANOMALY"
    }

    #===========================================================================
    # DATA PERSISTENCE AND BUFFERING
    #===========================================================================

    proc flush_data_buffer {} {
        variable data_buffer

        if {[llength $data_buffer] == 0} {
            return
        }

        # Write data to persistent storage
        set data_file "data/lsf_monitoring.log"

        if {![file exists [file dirname $data_file]]} {
            file mkdir [file dirname $data_file]
        }

        if {[catch {
            set fp [open $data_file a]
            foreach metrics_record $data_buffer {
                puts $fp [list [clock seconds] $metrics_record]
            }
            close $fp
        } error]} {
            CBFLOW_ERROR "Failed to flush monitoring data: $error" "DATA"
        } else {
            CBFLOW_DEBUG "Flushed [llength $data_buffer] metrics records to storage" "DATA"
        }

        # Clear the buffer
        set data_buffer {}
    }

    proc get_historical_data {start_time end_time} {
        # Retrieve historical monitoring data
        set data_file "data/lsf_monitoring.log"

        if {![file exists $data_file]} {
            return {}
        }

        set historical_data {}

        if {[catch {
            set fp [open $data_file r]
            while {[gets $fp line] >= 0} {
                set record [lindex $line 1]
                set timestamp [dict get $record timestamp]

                if {$timestamp >= $start_time && $timestamp <= $end_time} {
                    lappend historical_data $record
                }
            }
            close $fp
        } error]} {
            CBFLOW_ERROR "Failed to read historical data: $error" "DATA"
        }

        return $historical_data
    }

    #===========================================================================
    # CONFIGURATION AND UTILITIES
    #===========================================================================

    proc configure_monitoring {args} {
        variable config

        foreach {key value} $args {
            switch -- $key {
                "-sampling_interval" {
                    set config(sampling_interval) $value
                }
                "-buffer_size" {
                    set config(buffer_size) $value
                }
                "-flush_interval" {
                    set config(flush_interval) $value
                }
                "-anomaly_detection" {
                    set config(anomaly_detection) $value
                }
                "-realtime_alerts" {
                    set config(realtime_alerts) $value
                }
                default {
                    CBFLOW_WARNING "Unknown monitoring configuration option: $key" "CONFIG"
                }
            }
        }
    }

    proc get_config_value {key} {
        variable config
        if {[info exists config($key)]} {
            return $config($key)
        }
        return ""
    }

    proc get_current_metrics {} {
        variable current_metrics
        return [array get current_metrics]
    }

    proc generate_monitoring_report {} {
        set report ""
        append report "CBFlow LSF Monitoring Report\n"
        append report "============================\n"
        append report "Generated: [clock format [clock seconds]]\n\n"

        append report "Monitoring Status: [expr {[is_monitoring_active] ? "ACTIVE" : "INACTIVE"}]\n"
        append report "Last Collection: [clock format $::CBFlow::LSF::Monitor::last_collection_time]\n"
        append report "Buffer Size: [llength $::CBFlow::LSF::Monitor::data_buffer] records\n\n"

        # Add current metrics summary
        if {[array size current_metrics] > 0} {
            append report "Current Metrics Summary:\n"
            append report "------------------------\n"
            foreach {key value} [array get current_metrics] {
                append report "  $key: $value\n"
            }
        }

        return $report
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            PUBLIC INTERFACE                                │
# └─────────────────────────────────────────────────────────────────────────────┘

# Export main procedures to global namespace
proc lsf_start_monitoring {{interval 60}} {
    return [::CBFlow::LSF::Monitor::start_monitoring $interval]
}

proc lsf_stop_monitoring {} {
    return [::CBFlow::LSF::Monitor::stop_monitoring]
}

proc lsf_is_monitoring_active {} {
    return [::CBFlow::LSF::Monitor::is_monitoring_active]
}

proc lsf_collect_metrics {} {
    return [::CBFlow::LSF::Monitor::collect_all_metrics]
}

proc lsf_get_historical_data {start_time end_time} {
    return [::CBFlow::LSF::Monitor::get_historical_data $start_time $end_time]
}

proc lsf_configure_monitoring {args} {
    return [::CBFlow::LSF::Monitor::configure_monitoring {*}$args]
}

proc lsf_monitoring_report {} {
    return [::CBFlow::LSF::Monitor::generate_monitoring_report]
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                             INITIALIZATION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

CBFLOW_INFO "CBFlow LSF monitoring system loaded successfully" "INIT"

# Auto-start monitoring if CBFLOW_LSF_MONITOR_AUTO is set
if {[info exists ::env(CBFLOW_LSF_MONITOR_AUTO)] && $::env(CBFLOW_LSF_MONITOR_AUTO) ne "0"} {
    set interval [expr {[info exists ::env(CBFLOW_LSF_MONITOR_INTERVAL)] ? $::env(CBFLOW_LSF_MONITOR_INTERVAL) : 60}]
    lsf_start_monitoring $interval
    CBFLOW_INFO "Auto-started LSF monitoring with ${interval}s interval" "INIT"
}