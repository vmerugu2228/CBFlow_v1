#!/usr/bin/env tclsh

# LSF Cost Management and Advanced ML Interface
# Provides TCL interface to advanced ML features and cost management

# Source required modules
source [file join [file dirname [info script]] "lsf_utils.tcl"]
source [file join [file dirname [info script]] "error_utils.tcl"]

namespace eval ::lsf::cost {
    variable config
    variable budget_tracking [dict create]
    variable cost_history [list]

    # Cost management configuration
    array set config {
        enable_cost_tracking true
        enable_budget_alerts true
        cost_per_cpu_hour 0.10
        cost_per_gb_hour 0.05
        default_budget_monthly 1000.0
        alert_threshold 0.8
        advanced_ml_enabled true
    }
}

# Initialize cost management
proc ::lsf::cost::initialize {} {
    variable config

    CBFLOW_INFO "Initializing LSF cost management" "LSF_COST"

    # Check if advanced ML is available
    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]
    if {[file exists $ml_script]} {
        set config(advanced_ml_enabled) true
        CBFLOW_INFO "Advanced ML features available" "LSF_COST"
    } else {
        set config(advanced_ml_enabled) false
        CBFLOW_WARNING "Advanced ML features not available, using basic cost tracking" "LSF_COST"
    }

    # Load existing budget configuration
    load_budget_configuration

    return true
}

# Load budget configuration from project settings
proc ::lsf::cost::load_budget_configuration {} {
    global project
    variable budget_tracking

    # Load budget settings from project configuration if available
    if {[info exists project(lsf,budget,monthly)]} {
        dict set budget_tracking monthly_budget $project(lsf,budget,monthly)
    } else {
        dict set budget_tracking monthly_budget 1000.0
    }

    if {[info exists project(lsf,budget,alert_threshold)]} {
        dict set budget_tracking alert_threshold $project(lsf,budget,alert_threshold)
    } else {
        dict set budget_tracking alert_threshold 0.8
    }

    CBFLOW_INFO "Budget configuration loaded: Monthly budget $[dict get $budget_tracking monthly_budget]" "LSF_COST"
}

# Calculate job cost
proc ::lsf::cost::calculate_job_cost {job_data} {
    variable config

    # Extract job resources
    set memory_gb [dict_get_default $job_data "memory_gb" 8]
    set cpu_count [dict_get_default $job_data "cpu_count" 4]
    set runtime_seconds [dict_get_default $job_data "runtime_seconds" 3600]

    # Calculate runtime in hours
    set runtime_hours [expr {double($runtime_seconds) / 3600.0}]

    # Calculate cost components
    set memory_cost [expr {$memory_gb * $config(cost_per_gb_hour) * $runtime_hours}]
    set cpu_cost [expr {$cpu_count * $config(cost_per_cpu_hour) * $runtime_hours}]
    set total_cost [expr {$memory_cost + $cpu_cost}]

    return [dict create \
        memory_cost $memory_cost \
        cpu_cost $cpu_cost \
        total_cost $total_cost \
        runtime_hours $runtime_hours \
    ]
}

# Track job cost
proc ::lsf::cost::track_job_cost {job_id job_data} {
    variable cost_history
    variable config

    if {!$config(enable_cost_tracking)} {
        return
    }

    # Calculate cost
    set cost_breakdown [calculate_job_cost $job_data]

    # Create cost record
    set cost_record [dict create \
        job_id $job_id \
        timestamp [clock seconds] \
        flow_type [dict_get_default $job_data "flow_type" ""] \
        stage_name [dict_get_default $job_data "stage_name" ""] \
        queue_type [dict_get_default $job_data "queue_type" ""] \
        cost_breakdown $cost_breakdown \
        total_cost [dict get $cost_breakdown total_cost] \
    ]

    # Store in history
    lappend cost_history $cost_record

    # Keep only last 1000 records in memory
    if {[llength $cost_history] > 1000} {
        set cost_history [lrange $cost_history end-999 end]
    }

    # Use advanced ML for tracking if available
    if {$config(advanced_ml_enabled)} {
        track_job_cost_with_ml $job_id $job_data $cost_breakdown
    }

    # Check budget alerts
    check_budget_alerts [dict get $job_data "flow_type"]

    CBFLOW_INFO "Job cost tracked: $job_id - $[format "%.2f" [dict get $cost_breakdown total_cost]]" "LSF_COST"
}

# Track job cost using advanced ML
proc ::lsf::cost::track_job_cost_with_ml {job_id job_data cost_breakdown} {
    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

    # Prepare job data for ML tracking
    set ml_job_data [dict create \
        job_id $job_id \
        flow_type [dict_get_default $job_data "flow_type" ""] \
        stage_name [dict_get_default $job_data "stage_name" ""] \
        requested_memory_gb [dict_get_default $job_data "memory_gb" 8] \
        requested_cpu [dict_get_default $job_data "cpu_count" 4] \
        runtime_seconds [dict_get_default $job_data "runtime_seconds" 3600] \
        cost_dollars [dict get $cost_breakdown total_cost] \
        queue_type [dict_get_default $job_data "queue_type" ""] \
    ]

    # Create temporary file for data exchange
    set temp_file "/tmp/ml_cost_data_[clock seconds]_[pid].json"
    set fp [open $temp_file w]
    puts $fp [dict_to_json $ml_job_data]
    close $fp

    # Call ML analytics (asynchronously to avoid blocking)
    if {[catch {exec python3 $ml_script track_job_cost $temp_file &} error]} {
        CBFLOW_WARNING "Failed to track cost with ML: $error" "LSF_COST"
    }

    # Clean up temp file after a delay
    after 5000 [list file delete -force $temp_file]
}

# Get cost report
proc ::lsf::cost::get_cost_report {{days 30}} {
    variable cost_history
    variable config

    # Calculate time threshold
    set threshold_time [expr {[clock seconds] - ($days * 24 * 3600)}]

    # Filter recent costs
    set recent_costs [list]
    foreach cost_record $cost_history {
        if {[dict get $cost_record timestamp] >= $threshold_time} {
            lappend recent_costs $cost_record
        }
    }

    if {[llength $recent_costs] == 0} {
        return [dict create \
            total_cost 0.0 \
            job_count 0 \
            average_cost 0.0 \
            cost_by_flow [dict create] \
            cost_by_queue [dict create] \
            period_days $days \
        ]
    }

    # Calculate summary statistics
    set total_cost 0.0
    set cost_by_flow [dict create]
    set cost_by_queue [dict create]

    foreach cost_record $recent_costs {
        set job_cost [dict get $cost_record total_cost]
        set flow_type [dict get $cost_record flow_type]
        set queue_type [dict get $cost_record queue_type]

        set total_cost [expr {$total_cost + $job_cost}]

        # Track by flow type
        if {![dict exists $cost_by_flow $flow_type]} {
            dict set cost_by_flow $flow_type 0.0
        }
        dict set cost_by_flow $flow_type [expr {[dict get $cost_by_flow $flow_type] + $job_cost}]

        # Track by queue type
        if {![dict exists $cost_by_queue $queue_type]} {
            dict set cost_by_queue $queue_type 0.0
        }
        dict set cost_by_queue $queue_type [expr {[dict get $cost_by_queue $queue_type] + $job_cost}]
    }

    set job_count [llength $recent_costs]
    set average_cost [expr {$job_count > 0 ? $total_cost / $job_count : 0.0}]

    return [dict create \
        total_cost $total_cost \
        job_count $job_count \
        average_cost $average_cost \
        cost_by_flow $cost_by_flow \
        cost_by_queue $cost_by_queue \
        period_days $days \
    ]
}

# Get advanced cost report using ML
proc ::lsf::cost::get_advanced_cost_report {{days 30}} {
    variable config

    if {!$config(advanced_ml_enabled)} {
        return [get_cost_report $days]
    }

    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

    # Create temporary file for results
    set result_file "/tmp/ml_cost_report_[clock seconds]_[pid].json"

    if {[catch {exec python3 $ml_script cost_report $days > $result_file} error]} {
        CBFLOW_WARNING "Failed to get advanced cost report: $error" "LSF_COST"
        return [get_cost_report $days]
    }

    # Read and parse results
    if {[file exists $result_file]} {
        set fp [open $result_file r]
        set json_data [read $fp]
        close $fp
        file delete -force $result_file

        return [json_to_dict $json_data]
    }

    return [get_cost_report $days]
}

# Set budget for flow type
proc ::lsf::cost::set_budget {flow_type budget_amount {period "monthly"}} {
    variable budget_tracking
    variable config

    dict set budget_tracking budgets $flow_type $period $budget_amount

    # Use advanced ML for budget management if available
    if {$config(advanced_ml_enabled)} {
        set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

        if {[catch {exec python3 $ml_script set_budget $flow_type $budget_amount $period} error]} {
            CBFLOW_WARNING "Failed to set budget in ML system: $error" "LSF_COST"
        }
    }

    CBFLOW_INFO "Budget set for $flow_type: $[format "%.2f" $budget_amount] ($period)" "LSF_COST"
}

# Check budget alerts
proc ::lsf::cost::check_budget_alerts {flow_type} {
    variable budget_tracking
    variable config

    if {!$config(enable_budget_alerts)} {
        return
    }

    # Get current spend for flow type
    set cost_report [get_cost_report 30]  # Current month approximation
    set cost_by_flow [dict get $cost_report cost_by_flow]

    if {![dict exists $cost_by_flow $flow_type]} {
        return  # No spending for this flow type
    }

    set current_spend [dict get $cost_by_flow $flow_type]

    # Check if budget is set
    if {![dict exists $budget_tracking budgets $flow_type monthly]} {
        return  # No budget set
    }

    set budget [dict get $budget_tracking budgets $flow_type monthly]
    set utilization [expr {$budget > 0 ? $current_spend / $budget : 0}]
    set threshold [dict get $budget_tracking alert_threshold]

    if {$utilization >= 1.0} {
        CBFLOW_ERROR "BUDGET EXCEEDED: $flow_type has spent $[format "%.2f" $current_spend] of $[format "%.2f" $budget] budget" "LSF_COST"
    } elseif {$utilization >= $threshold} {
        CBFLOW_WARNING "Budget Alert: $flow_type has used [format "%.1f" [expr {$utilization * 100}]]% of monthly budget" "LSF_COST"
    }
}

# Get budget status
proc ::lsf::cost::get_budget_status {flow_type} {
    variable budget_tracking
    variable config

    # Get current spend
    set cost_report [get_cost_report 30]
    set cost_by_flow [dict get $cost_report cost_by_flow]

    set current_spend 0.0
    if {[dict exists $cost_by_flow $flow_type]} {
        set current_spend [dict get $cost_by_flow $flow_type]
    }

    # Get budget
    set budget 0.0
    if {[dict exists $budget_tracking budgets $flow_type monthly]} {
        set budget [dict get $budget_tracking budgets $flow_type monthly]
    }

    set utilization [expr {$budget > 0 ? $current_spend / $budget : 0}]
    set remaining [expr {$budget - $current_spend}]

    # Determine status
    set status "ok"
    if {$utilization >= 1.0} {
        set status "over_budget"
    } elseif {$utilization >= [dict get $budget_tracking alert_threshold]} {
        set status "warning"
    }

    # Use advanced ML for budget status if available
    set advanced_status [dict create]
    if {$config(advanced_ml_enabled)} {
        set advanced_status [get_advanced_budget_status $flow_type]
    }

    return [dict create \
        flow_type $flow_type \
        allocated_budget $budget \
        current_spend $current_spend \
        remaining_budget $remaining \
        budget_utilization $utilization \
        status $status \
        advanced_analysis $advanced_status \
    ]
}

# Get advanced budget status using ML
proc ::lsf::cost::get_advanced_budget_status {flow_type} {
    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

    set result_file "/tmp/ml_budget_status_[clock seconds]_[pid].json"

    if {[catch {exec python3 $ml_script budget_status $flow_type > $result_file} error]} {
        CBFLOW_WARNING "Failed to get advanced budget status: $error" "LSF_COST"
        return [dict create]
    }

    if {[file exists $result_file]} {
        set fp [open $result_file r]
        set json_data [read $fp]
        close $fp
        file delete -force $result_file

        return [json_to_dict $json_data]
    }

    return [dict create]
}

# Optimize resources using advanced ML
proc ::lsf::cost::optimize_resources {flow_type stage_name design_characteristics} {
    variable config

    if {!$config(advanced_ml_enabled)} {
        return [dict create \
            status "fallback" \
            memory_gb 16 \
            cpu_count 8 \
            estimated_cost 5.0 \
            confidence 0.5 \
        ]
    }

    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

    # Prepare input data
    set input_data [dict create \
        flow_type $flow_type \
        stage_name $stage_name \
        design_characteristics $design_characteristics \
    ]

    set input_file "/tmp/ml_optimize_input_[clock seconds]_[pid].json"
    set result_file "/tmp/ml_optimize_output_[clock seconds]_[pid].json"

    # Write input data
    set fp [open $input_file w]
    puts $fp [dict_to_json $input_data]
    close $fp

    # Call ML optimization
    if {[catch {exec python3 $ml_script predict_resources $flow_type $stage_name [dict_to_json $design_characteristics] > $result_file} error]} {
        CBFLOW_WARNING "Failed to get ML optimization: $error" "LSF_COST"
        file delete -force $input_file
        return [dict create status "error"]
    }

    # Parse results
    set optimization_result [dict create]
    if {[file exists $result_file]} {
        set fp [open $result_file r]
        set json_data [read $fp]
        close $fp
        set optimization_result [json_to_dict $json_data]
        file delete -force $result_file
    }

    file delete -force $input_file
    return $optimization_result
}

# Train ML models
proc ::lsf::cost::train_ml_models {} {
    variable config

    if {!$config(advanced_ml_enabled)} {
        CBFLOW_WARNING "Advanced ML not available" "LSF_COST"
        return false
    }

    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]

    CBFLOW_INFO "Training advanced ML models..." "LSF_COST"

    if {[catch {exec python3 $ml_script train_models} output]} {
        CBFLOW_ERROR "Failed to train ML models: $output" "LSF_COST"
        return false
    }

    CBFLOW_INFO "ML model training completed" "LSF_COST"
    return true
}

# Get cost optimization recommendations
proc ::lsf::cost::get_cost_optimization_recommendations {} {
    variable cost_history

    set recommendations [list]

    # Analyze recent cost patterns
    set recent_costs [lrange $cost_history end-99 end]  # Last 100 jobs

    if {[llength $recent_costs] < 10} {
        return $recommendations
    }

    # Calculate average costs by queue type
    set queue_costs [dict create]
    set queue_counts [dict create]

    foreach cost_record $recent_costs {
        set queue_type [dict get $cost_record queue_type]
        set total_cost [dict get $cost_record total_cost]

        if {![dict exists $queue_costs $queue_type]} {
            dict set queue_costs $queue_type 0.0
            dict set queue_counts $queue_type 0
        }

        dict set queue_costs $queue_type [expr {[dict get $queue_costs $queue_type] + $total_cost}]
        dict incr queue_counts $queue_type
    }

    # Generate recommendations
    dict for {queue_type total_cost} $queue_costs {
        set count [dict get $queue_counts $queue_type]
        set avg_cost [expr {$total_cost / $count}]

        if {$avg_cost > 20.0} {  # High cost threshold
            lappend recommendations [dict create \
                type "high_cost_queue" \
                queue_type $queue_type \
                average_cost $avg_cost \
                recommendation "Consider optimizing resource allocation for queue $queue_type" \
                potential_savings [expr {$avg_cost * 0.2}] \
            ]
        }
    }

    return $recommendations
}

# Utility functions
proc ::lsf::cost::dict_get_default {dict_data key default_value} {
    if {[dict exists $dict_data $key]} {
        return [dict get $dict_data $key]
    } else {
        return $default_value
    }
}

proc ::lsf::cost::dict_to_json {dict_data} {
    set json "{"
    set first 1
    dict for {key value} $dict_data {
        if {!$first} {
            append json ","
        }
        append json "\"$key\": "
        if {[string is integer $value] || [string is double $value]} {
            append json "$value"
        } elseif {[string is dict $value]} {
            append json [dict_to_json $value]
        } else {
            append json "\"$value\""
        }
        set first 0
    }
    append json "}"
    return $json
}

proc ::lsf::cost::json_to_dict {json_data} {
    # Simple JSON parser for basic structures
    set dict_data [dict create]

    # Remove braces and split by commas
    set json_data [string trim $json_data "{}"]
    set pairs [split $json_data ","]

    foreach pair $pairs {
        if {[regexp {"([^"]+)":\s*"?([^"]+)"?} $pair -> key value]} {
            set value [string trim $value "\""]
            dict set dict_data $key $value
        }
    }

    return $dict_data
}

# Public interface
proc ::lsf::cost::enable {} {
    variable config
    set config(enable_cost_tracking) true
    set config(enable_budget_alerts) true
    initialize
}

proc ::lsf::cost::disable {} {
    variable config
    set config(enable_cost_tracking) false
    set config(enable_budget_alerts) false
}

proc ::lsf::cost::is_enabled {} {
    variable config
    return $config(enable_cost_tracking)
}

# Auto-initialize
::lsf::cost::initialize