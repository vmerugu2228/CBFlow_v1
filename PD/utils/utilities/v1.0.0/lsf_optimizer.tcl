#!/usr/bin/env tclsh

# LSF Resource Optimization Engine
# Provides intelligent resource allocation optimization and cost management

# Source required modules
source [file join [file dirname [info script]] "lsf_utils.tcl"]
source [file join [file dirname [info script]] "lsf_dynamic_queues.tcl"]
source [file join [file dirname [info script]] "lsf_data_manager.tcl"]
source [file join [file dirname [info script]] "error_utils.tcl"]

namespace eval ::lsf::optimizer {
    variable optimization_history [list]
    variable cost_tracking [dict create]
    variable efficiency_metrics [dict create]
    variable resource_pools [dict create]

    # Optimization configuration
    variable config
    array set config {
        cost_optimization_weight 0.4
        performance_optimization_weight 0.6
        efficiency_threshold 0.75
        cost_per_cpu_hour 0.10
        cost_per_gb_hour 0.05
        optimization_interval_minutes 30
        resource_utilization_target 0.85
        queue_balancing_factor 0.3
    }
}

# Main optimization entry point
proc ::lsf::optimizer::optimize_resource_allocation {flow_type stage_name design_characteristics} {
    variable config

    CBFLOW_INFO "Starting resource optimization for $flow_type:$stage_name" "LSF_OPTIMIZER"

    # Collect current system state
    set system_state [collect_system_state]

    # Analyze historical performance
    set historical_analysis [analyze_historical_performance $flow_type $stage_name $design_characteristics]

    # Calculate optimization recommendations
    set recommendations [calculate_optimization_recommendations $system_state $historical_analysis $design_characteristics]

    # Apply optimization if beneficial
    set optimization_result [apply_optimization_recommendations $recommendations]

    # Record optimization attempt
    record_optimization_attempt $flow_type $stage_name $optimization_result

    return $optimization_result
}

# Collect current LSF system state
proc ::lsf::optimizer::collect_system_state {} {
    set system_state [dict create]

    # Queue utilization data
    dict set system_state queue_utilization [get_queue_utilization_data]

    # Resource availability
    dict set system_state resource_availability [get_resource_availability]

    # Current job distribution
    dict set system_state job_distribution [get_job_distribution]

    # Cost metrics
    dict set system_state current_costs [get_current_cost_metrics]

    # Performance metrics
    dict set system_state performance_metrics [get_performance_metrics]

    return $system_state
}

# Get queue utilization data
proc ::lsf::optimizer::get_queue_utilization_data {} {
    set utilization_data [dict create]

    # Get standard queue utilization
    foreach queue_type {S M L XL ultra} {
        set queue_stats [get_queue_stats $queue_type]
        dict set utilization_data $queue_type $queue_stats
    }

    # Get dynamic queue utilization
    set dynamic_queues [::lsf::dynamic::get_dynamic_queue_status]
    dict set utilization_data dynamic $dynamic_queues

    return $utilization_data
}

# Get individual queue statistics
proc ::lsf::optimizer::get_queue_stats {queue_type} {
    set stats [dict create \
        running_jobs 0 \
        pending_jobs 0 \
        total_slots 0 \
        used_slots 0 \
        efficiency 0.0 \
    ]

    if {[catch {exec bqueues $queue_type} queue_output]} {
        CBFLOW_WARNING "Failed to get stats for queue $queue_type" "LSF_OPTIMIZER"
        return $stats
    }

    # Parse queue statistics from LSF output
    if {[regexp {(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $queue_output -> max_slots pend run total]} {
        dict set stats total_slots $max_slots
        dict set stats pending_jobs $pend
        dict set stats running_jobs $run
        dict set stats used_slots [expr {$run}]

        if {$max_slots > 0} {
            dict set stats efficiency [expr {double($run) / $max_slots}]
        }
    }

    return $stats
}

# Get overall resource availability
proc ::lsf::optimizer::get_resource_availability {} {
    set availability [dict create]

    if {[catch {exec bhosts} hosts_output]} {
        CBFLOW_WARNING "Failed to get host information" "LSF_OPTIMIZER"
        return $availability
    }

    # Parse host information
    set total_cpu 0
    set used_cpu 0
    set total_memory 0
    set used_memory 0

    foreach line [split $hosts_output "\n"] {
        if {[regexp {(\S+)\s+ok\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> host total_cpu_host used_cpu_host total_mem_host used_mem_host]} {
            incr total_cpu $total_cpu_host
            incr used_cpu $used_cpu_host
            incr total_memory $total_mem_host
            incr used_memory $used_mem_host
        }
    }

    dict set availability total_cpu $total_cpu
    dict set availability used_cpu $used_cpu
    dict set availability available_cpu [expr {$total_cpu - $used_cpu}]
    dict set availability cpu_utilization [expr {$total_cpu > 0 ? double($used_cpu) / $total_cpu : 0}]

    dict set availability total_memory $total_memory
    dict set availability used_memory $used_memory
    dict set availability available_memory [expr {$total_memory - $used_memory}]
    dict set availability memory_utilization [expr {$total_memory > 0 ? double($used_memory) / $total_memory : 0}]

    return $availability
}

# Get current job distribution across queues
proc ::lsf::optimizer::get_job_distribution {} {
    set distribution [dict create]

    if {[catch {exec bjobs -a} jobs_output]} {
        return $distribution
    }

    # Count jobs by queue
    foreach line [split $jobs_output "\n"] {
        if {[regexp {\S+\s+\S+\s+(\S+)\s+\S+\s+(\S+)} $line -> queue status]} {
            if {![dict exists $distribution $queue]} {
                dict set distribution $queue [dict create total 0 running 0 pending 0]
            }
            dict incr distribution $queue total
            if {$status eq "RUN"} {
                dict incr distribution $queue running
            } elseif {$status eq "PEND"} {
                dict incr distribution $queue pending
            }
        }
    }

    return $distribution
}

# Get current cost metrics
proc ::lsf::optimizer::get_current_cost_metrics {} {
    variable config

    set costs [dict create \
        hourly_cpu_cost 0.0 \
        hourly_memory_cost 0.0 \
        total_hourly_cost 0.0 \
        daily_cost_estimate 0.0 \
    ]

    # Calculate costs based on current resource usage
    set availability [get_resource_availability]
    set used_cpu [dict get $availability used_cpu]
    set used_memory [dict get $availability used_memory]

    set hourly_cpu_cost [expr {$used_cpu * $config(cost_per_cpu_hour)}]
    set hourly_memory_cost [expr {$used_memory * $config(cost_per_gb_hour) / 1024.0}]
    set total_hourly_cost [expr {$hourly_cpu_cost + $hourly_memory_cost}]

    dict set costs hourly_cpu_cost $hourly_cpu_cost
    dict set costs hourly_memory_cost $hourly_memory_cost
    dict set costs total_hourly_cost $total_hourly_cost
    dict set costs daily_cost_estimate [expr {$total_hourly_cost * 24}]

    return $costs
}

# Get performance metrics
proc ::lsf::optimizer::get_performance_metrics {} {
    set metrics [dict create \
        average_queue_time 0.0 \
        average_runtime 0.0 \
        job_success_rate 0.0 \
        throughput_jobs_per_hour 0.0 \
    ]

    # Use data manager to get recent performance data
    if {[catch {::lsf::data::get_recent_performance_metrics 24} recent_metrics]} {
        CBFLOW_WARNING "Failed to get recent performance metrics" "LSF_OPTIMIZER"
        return $metrics
    }

    return $recent_metrics
}

# Analyze historical performance for specific flow/stage
proc ::lsf::optimizer::analyze_historical_performance {flow_type stage_name design_characteristics} {
    set analysis [dict create \
        average_memory_usage 0.0 \
        average_cpu_utilization 0.0 \
        average_runtime 0.0 \
        success_rate 0.0 \
        cost_efficiency 0.0 \
        optimal_queue_recommendation "" \
    ]

    # Get historical data from data manager
    if {[catch {::lsf::data::get_historical_job_data $flow_type $stage_name 100} historical_data]} {
        CBFLOW_WARNING "Failed to get historical data for $flow_type:$stage_name" "LSF_OPTIMIZER"
        return $analysis
    }

    if {[llength $historical_data] == 0} {
        return $analysis
    }

    # Analyze historical patterns
    set total_jobs [llength $historical_data]
    set memory_sum 0.0
    set cpu_sum 0.0
    set runtime_sum 0.0
    set successful_jobs 0
    set cost_sum 0.0

    foreach job_data $historical_data {
        if {[dict exists $job_data "max_memory_used"]} {
            set memory_sum [expr {$memory_sum + [dict get $job_data "max_memory_used"]}]
        }
        if {[dict exists $job_data "avg_cpu_utilization"]} {
            set cpu_sum [expr {$cpu_sum + [dict get $job_data "avg_cpu_utilization"]}]
        }
        if {[dict exists $job_data "runtime_seconds"]} {
            set runtime_sum [expr {$runtime_sum + [dict get $job_data "runtime_seconds"]}]
        }
        if {[dict get $job_data "exit_status"] == "0"} {
            incr successful_jobs
        }
        if {[dict exists $job_data "total_cost"]} {
            set cost_sum [expr {$cost_sum + [dict get $job_data "total_cost"]}]
        }
    }

    # Calculate averages
    if {$total_jobs > 0} {
        dict set analysis average_memory_usage [expr {$memory_sum / $total_jobs}]
        dict set analysis average_cpu_utilization [expr {$cpu_sum / $total_jobs}]
        dict set analysis average_runtime [expr {$runtime_sum / $total_jobs}]
        dict set analysis success_rate [expr {double($successful_jobs) / $total_jobs}]
        dict set analysis cost_efficiency [expr {$cost_sum > 0 ? $successful_jobs / $cost_sum : 0}]
    }

    # Determine optimal queue recommendation
    set avg_memory [dict get $analysis average_memory_usage]
    set avg_cpu_util [dict get $analysis average_cpu_utilization]

    set optimal_queue [determine_optimal_queue $avg_memory $avg_cpu_util]
    dict set analysis optimal_queue_recommendation $optimal_queue

    return $analysis
}

# Determine optimal queue based on resource usage patterns
proc ::lsf::optimizer::determine_optimal_queue {avg_memory_gb avg_cpu_utilization} {
    # Decision matrix based on memory and CPU utilization
    if {$avg_memory_gb >= 100} {
        return "ultra"
    } elseif {$avg_memory_gb >= 50} {
        return "XL"
    } elseif {$avg_memory_gb >= 25} {
        return "L"
    } elseif {$avg_memory_gb >= 12} {
        return "M"
    } else {
        return "S"
    }
}

# Calculate optimization recommendations
proc ::lsf::optimizer::calculate_optimization_recommendations {system_state historical_analysis design_characteristics} {
    variable config

    set recommendations [dict create \
        queue_recommendation "" \
        resource_adjustment [dict create] \
        cost_optimization [dict create] \
        performance_optimization [dict create] \
        confidence_score 0.0 \
    ]

    # Get current resource availability
    set availability [dict get $system_state resource_availability]
    set cpu_utilization [dict get $availability cpu_utilization]
    set memory_utilization [dict get $availability memory_utilization]

    # Historical insights
    set historical_queue [dict get $historical_analysis optimal_queue_recommendation]
    set historical_success_rate [dict get $historical_analysis success_rate]

    # Queue recommendation based on current load and historical data
    set queue_recommendation [calculate_queue_recommendation $system_state $historical_analysis $design_characteristics]
    dict set recommendations queue_recommendation $queue_recommendation

    # Resource adjustment recommendations
    set resource_adjustment [calculate_resource_adjustments $cpu_utilization $memory_utilization]
    dict set recommendations resource_adjustment $resource_adjustment

    # Cost optimization recommendations
    set cost_optimization [calculate_cost_optimizations $system_state]
    dict set recommendations cost_optimization $cost_optimization

    # Performance optimization recommendations
    set performance_optimization [calculate_performance_optimizations $system_state $historical_analysis]
    dict set recommendations performance_optimization $performance_optimization

    # Calculate confidence score
    set confidence_score [calculate_confidence_score $historical_analysis $system_state]
    dict set recommendations confidence_score $confidence_score

    return $recommendations
}

# Calculate queue recommendation
proc ::lsf::optimizer::calculate_queue_recommendation {system_state historical_analysis design_characteristics} {
    # Get queue utilization data
    set queue_utilization [dict get $system_state queue_utilization]

    # Find least utilized queue that meets requirements
    set historical_queue [dict get $historical_analysis optimal_queue_recommendation]

    # Check if historical queue is available and not overloaded
    if {[dict exists $queue_utilization $historical_queue]} {
        set queue_stats [dict get $queue_utilization $historical_queue]
        set efficiency [dict get $queue_stats efficiency]

        if {$efficiency < 0.9} {  # Queue not overloaded
            return $historical_queue
        }
    }

    # Find alternative queue with good availability
    set queue_candidates [list]
    foreach queue_type {S M L XL ultra} {
        if {[dict exists $queue_utilization $queue_type]} {
            set stats [dict get $queue_utilization $queue_type]
            set efficiency [dict get $stats efficiency]
            lappend queue_candidates [list $queue_type $efficiency]
        }
    }

    # Sort by efficiency (ascending - prefer less loaded queues)
    set sorted_candidates [lsort -real -index 1 $queue_candidates]

    # Return the least loaded queue that meets minimum requirements
    foreach candidate $sorted_candidates {
        set queue_type [lindex $candidate 0]
        set efficiency [lindex $candidate 1]

        if {$efficiency < 0.85} {  # Reasonable load
            return $queue_type
        }
    }

    # Fallback to historical recommendation
    return $historical_queue
}

# Calculate resource adjustments
proc ::lsf::optimizer::calculate_resource_adjustments {cpu_utilization memory_utilization} {
    variable config

    set adjustments [dict create \
        cpu_scaling_factor 1.0 \
        memory_scaling_factor 1.0 \
        recommendation "" \
    ]

    # CPU scaling recommendations
    if {$cpu_utilization > $config(resource_utilization_target)} {
        set cpu_scaling [expr {1.0 + ($cpu_utilization - $config(resource_utilization_target))}]
        dict set adjustments cpu_scaling_factor $cpu_scaling
        dict set adjustments recommendation "Increase CPU allocation"
    } elseif {$cpu_utilization < 0.5} {
        set cpu_scaling [expr {max(0.7, $cpu_utilization + 0.2)}]
        dict set adjustments cpu_scaling_factor $cpu_scaling
        dict set adjustments recommendation "Consider reducing CPU allocation"
    }

    # Memory scaling recommendations
    if {$memory_utilization > $config(resource_utilization_target)} {
        set memory_scaling [expr {1.0 + ($memory_utilization - $config(resource_utilization_target))}]
        dict set adjustments memory_scaling_factor $memory_scaling
        dict set adjustments recommendation "Increase memory allocation"
    } elseif {$memory_utilization < 0.5} {
        set memory_scaling [expr {max(0.7, $memory_utilization + 0.2)}]
        dict set adjustments memory_scaling_factor $memory_scaling
        dict set adjustments recommendation "Consider reducing memory allocation"
    }

    return $adjustments
}

# Calculate cost optimizations
proc ::lsf::optimizer::calculate_cost_optimizations {system_state} {
    variable config

    set optimizations [dict create \
        potential_savings 0.0 \
        recommendations [list] \
        priority "medium" \
    ]

    set current_costs [dict get $system_state current_costs]
    set total_hourly_cost [dict get $current_costs total_hourly_cost]

    # Analyze queue distribution for cost optimization
    set job_distribution [dict get $system_state job_distribution]
    set recommendations [list]

    # Check for overprovisioning
    set availability [dict get $system_state resource_availability]
    set cpu_utilization [dict get $availability cpu_utilization]
    set memory_utilization [dict get $availability memory_utilization]

    if {$cpu_utilization < 0.6 && $memory_utilization < 0.6} {
        set potential_savings [expr {$total_hourly_cost * 0.3}]
        dict set optimizations potential_savings $potential_savings
        lappend recommendations "Consider rightsizing resources - current utilization is low"
        dict set optimizations priority "high"
    }

    # Check for queue imbalances
    dict for {queue queue_data} $job_distribution {
        set total_jobs [dict get $queue_data total]
        set running_jobs [dict get $queue_data running]

        if {$total_jobs > 0 && $running_jobs == 0} {
            lappend recommendations "Queue $queue has pending jobs - consider load balancing"
        }
    }

    dict set optimizations recommendations $recommendations
    return $optimizations
}

# Calculate performance optimizations
proc ::lsf::optimizer::calculate_performance_optimizations {system_state historical_analysis} {
    set optimizations [dict create \
        recommendations [list] \
        expected_improvement 0.0 \
        priority "medium" \
    ]

    set performance_metrics [dict get $system_state performance_metrics]
    set success_rate [dict get $historical_analysis success_rate]
    set recommendations [list]

    # Check job success rate
    if {$success_rate < 0.9} {
        lappend recommendations "Job success rate is low ($success_rate) - investigate job failures"
        dict set optimizations priority "high"
    }

    # Check queue times
    if {[dict exists $performance_metrics "average_queue_time"]} {
        set avg_queue_time [dict get $performance_metrics "average_queue_time"]
        if {$avg_queue_time > 3600} {  # More than 1 hour
            lappend recommendations "Average queue time is high - consider queue rebalancing"
            dict set optimizations expected_improvement 0.2
        }
    }

    dict set optimizations recommendations $recommendations
    return $optimizations
}

# Calculate confidence score for recommendations
proc ::lsf::optimizer::calculate_confidence_score {historical_analysis system_state} {
    set base_confidence 0.5

    # Increase confidence based on historical data quality
    set success_rate [dict get $historical_analysis success_rate]
    if {$success_rate > 0.9} {
        set base_confidence [expr {$base_confidence + 0.2}]
    }

    # Increase confidence based on system stability
    set availability [dict get $system_state resource_availability]
    set cpu_utilization [dict get $availability cpu_utilization]
    if {$cpu_utilization > 0.2 && $cpu_utilization < 0.9} {
        set base_confidence [expr {$base_confidence + 0.2}]
    }

    return [expr {min(1.0, $base_confidence)}]
}

# Apply optimization recommendations
proc ::lsf::optimizer::apply_optimization_recommendations {recommendations} {
    set result [dict create \
        applied_optimizations [list] \
        failed_optimizations [list] \
        overall_success 1 \
    ]

    set queue_recommendation [dict get $recommendations queue_recommendation]
    set confidence_score [dict get $recommendations confidence_score]

    # Only apply high-confidence recommendations
    if {$confidence_score > 0.7} {
        # Apply queue recommendation
        if {$queue_recommendation ne ""} {
            set optimization_result [apply_queue_optimization $queue_recommendation]
            if {$optimization_result} {
                lappend [dict get $result applied_optimizations] "queue_optimization:$queue_recommendation"
            } else {
                lappend [dict get $result failed_optimizations] "queue_optimization:$queue_recommendation"
                dict set result overall_success 0
            }
        }

        # Apply cost optimizations if available
        set cost_optimization [dict get $recommendations cost_optimization]
        if {[dict get $cost_optimization potential_savings] > 0} {
            set cost_result [apply_cost_optimizations $cost_optimization]
            if {$cost_result} {
                lappend [dict get $result applied_optimizations] "cost_optimization"
            } else {
                lappend [dict get $result failed_optimizations] "cost_optimization"
            }
        }
    } else {
        CBFLOW_INFO "Low confidence score ($confidence_score), skipping optimization application" "LSF_OPTIMIZER"
    }

    return $result
}

# Apply queue optimization
proc ::lsf::optimizer::apply_queue_optimization {queue_recommendation} {
    # This would integrate with actual LSF queue management
    CBFLOW_INFO "Applying queue optimization: $queue_recommendation" "LSF_OPTIMIZER"

    # In a real implementation, this would:
    # 1. Adjust queue priorities
    # 2. Modify resource allocations
    # 3. Rebalance job distribution

    return 1  # Success
}

# Apply cost optimizations
proc ::lsf::optimizer::apply_cost_optimizations {cost_optimization} {
    set recommendations [dict get $cost_optimization recommendations]

    foreach recommendation $recommendations {
        CBFLOW_INFO "Cost optimization recommendation: $recommendation" "LSF_OPTIMIZER"
    }

    return 1  # Success
}

# Record optimization attempt
proc ::lsf::optimizer::record_optimization_attempt {flow_type stage_name optimization_result} {
    variable optimization_history

    set record [dict create \
        timestamp [clock seconds] \
        flow_type $flow_type \
        stage_name $stage_name \
        result $optimization_result \
    ]

    lappend optimization_history $record

    # Keep only last 100 optimization records
    if {[llength $optimization_history] > 100} {
        set optimization_history [lrange $optimization_history end-99 end]
    }
}

# Get optimization statistics
proc ::lsf::optimizer::get_optimization_statistics {} {
    variable optimization_history

    set stats [dict create \
        total_optimizations [llength $optimization_history] \
        successful_optimizations 0 \
        recent_optimization_rate 0.0 \
    ]

    foreach record $optimization_history {
        set result [dict get $record result]
        if {[dict get $result overall_success]} {
            dict incr stats successful_optimizations
        }
    }

    if {[llength $optimization_history] > 0} {
        set success_rate [expr {double([dict get $stats successful_optimizations]) / [llength $optimization_history]}]
        dict set stats recent_optimization_rate $success_rate
    }

    return $stats
}