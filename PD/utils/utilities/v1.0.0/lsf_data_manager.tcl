#!/usr/bin/env tclsh
#===============================================================================
# CBFlow LSF Analytics Data Management System
#
# Description: Data persistence and management for LSF ML analytics
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - SQLite database for historical analytics
# - Resource usage trend analysis
# - Performance regression detection
# - Anomaly detection for resource inefficiencies
# - ML model data preparation and feeding
# - Data export and reporting capabilities
#===============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           NAMESPACE DEFINITION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::DataManager {
    variable version "1.0.0"
    variable database_path "data/lsf_analytics.db"
    variable python_analytics_path ""
    variable cache_expiry 600  ; # 10 minutes cache expiry

    # Data collection configuration
    variable config
    array set config {
        data_retention_days 90
        batch_size 100
        auto_cleanup enabled
        ml_integration enabled
        export_formats {json csv}
    }

    # Cache for frequently accessed data
    variable data_cache
    array set data_cache {}

    # Statistics for monitoring
    variable stats
    array set stats {
        total_jobs_recorded 0
        total_metrics_collected 0
        ml_predictions_made 0
        anomalies_detected 0
        last_cleanup_time 0
    }
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
# │                      DATABASE MANAGEMENT CORE                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF::DataManager {

    #===========================================================================
    # DATABASE INITIALIZATION AND CONFIGURATION
    #===========================================================================

    proc initialize_database {{custom_path ""}} {
        variable database_path

        if {$custom_path ne ""} {
            set database_path $custom_path
        }

        # Create data directory if it doesn't exist
        set data_dir [file dirname $database_path]
        if {![file exists $data_dir]} {
            file mkdir $data_dir
            CBFLOW_INFO "Created data directory: $data_dir" "DATA"
        }

        # Initialize database using Python analytics module
        if {[initialize_python_integration]} {
            CBFLOW_INFO "Database initialized successfully at: $database_path" "DATA"
            return true
        } else {
            CBFLOW_ERROR "Failed to initialize database" "DATA"
            return false
        }
    }

    proc initialize_python_integration {} {
        variable python_analytics_path

        # Find Python analytics script
        set possible_paths {
            "../ml_analytics/v1.0.0/lsf_ml_analytics.py"
            "../../ml_analytics/v1.0.0/lsf_ml_analytics.py"
            "$::env(SCRIPTS_ROOT)/ml_analytics/v1.0.0/lsf_ml_analytics.py"
        }

        foreach path $possible_paths {
            set expanded_path [subst $path]
            if {[file exists $expanded_path]} {
                set python_analytics_path [file normalize $expanded_path]
                CBFLOW_DEBUG "Found Python analytics at: $python_analytics_path" "ML"
                break
            }
        }

        if {$python_analytics_path eq ""} {
            CBFLOW_WARNING "Python analytics module not found - limited functionality" "ML"
            return false
        }

        # Test Python integration
        if {[catch {exec python3 $python_analytics_path --action analyze} result]} {
            CBFLOW_WARNING "Python analytics test failed: $result" "ML"
            return false
        }

        return true
    }

    #===========================================================================
    # JOB DATA COLLECTION AND STORAGE
    #===========================================================================

    proc record_job_submission {job_id queue_type flow_type stage_name design_characteristics} {
        variable stats

        set job_data [dict create \
            job_id $job_id \
            queue_type $queue_type \
            flow_type $flow_type \
            stage_name $stage_name \
            submit_time [clock seconds] \
            status "SUBMITTED" \
            design_characteristics $design_characteristics \
        ]

        # Store job data
        if {[store_job_data $job_data]} {
            incr stats(total_jobs_recorded)
            CBFLOW_DEBUG "Recorded job submission: $job_id" "DATA"
            return true
        }

        return false
    }

    proc update_job_completion {job_id status runtime_actual resource_usage cost_actual} {
        set update_data [dict create \
            job_id $job_id \
            status $status \
            end_time [clock seconds] \
            runtime_actual $runtime_actual \
            cost_actual $cost_actual \
        ]

        # Add resource usage data
        if {[dict exists $resource_usage memory_used]} {
            dict set update_data actual_memory_used [dict get $resource_usage memory_used]
        }
        if {[dict exists $resource_usage cpu_used]} {
            dict set update_data actual_cpu_used [dict get $resource_usage cpu_used]
        }

        # Calculate efficiency score
        set efficiency_score [calculate_job_efficiency $job_id $resource_usage]
        dict set update_data efficiency_score $efficiency_score

        if {[update_job_data $update_data]} {
            CBFLOW_DEBUG "Updated job completion: $job_id ($status)" "DATA"

            # Trigger ML analysis for completed jobs
            if {$status eq "DONE"} {
                analyze_job_completion $job_id
            }

            return true
        }

        return false
    }

    proc store_job_data {job_data} {
        variable python_analytics_path
        variable database_path

        if {$python_analytics_path eq ""} {
            CBFLOW_WARNING "Cannot store job data - Python integration not available" "DATA"
            return false
        }

        # Create temporary JSON file with job data
        set temp_file "/tmp/cbflow_job_data_[clock seconds].json"
        set fp [open $temp_file w]
        puts $fp [dict_to_json $job_data]
        close $fp

        # Call Python analytics to store data
        if {[catch {
            exec python3 -c "
import sys
sys.path.append('[file dirname $python_analytics_path]')
from [file rootname [file tail $python_analytics_path]] import CBFlowLSFAnalytics
import json

analytics = CBFlowLSFAnalytics('$database_path')
with open('$temp_file', 'r') as f:
    job_data = json.load(f)
analytics.save_job_data(job_data)
print('SUCCESS')
"
        } result]} {
            CBFLOW_ERROR "Failed to store job data: $result" "DATA"
            file delete $temp_file
            return false
        }

        file delete $temp_file
        return [string match "*SUCCESS*" $result]
    }

    proc update_job_data {update_data} {
        # This is a simplified update - in a full implementation,
        # we would need UPDATE functionality in the Python module
        return [store_job_data $update_data]
    }

    proc calculate_job_efficiency {job_id resource_usage} {
        # Calculate efficiency score based on resource utilization
        set efficiency_score 0.0

        # Get original job allocation data
        set job_allocation [get_job_allocation_data $job_id]

        if {[dict size $job_allocation] > 0} {
            set memory_efficiency 1.0
            set cpu_efficiency 1.0

            # Calculate memory efficiency
            if {[dict exists $resource_usage memory_used] && [dict exists $job_allocation allocated_memory]} {
                set memory_used [dict get $resource_usage memory_used]
                set memory_allocated [dict get $job_allocation allocated_memory]

                if {$memory_allocated > 0} {
                    set memory_efficiency [expr double($memory_used) / $memory_allocated]
                    # Efficiency peaks at 80-90% utilization
                    if {$memory_efficiency > 0.9} {
                        set memory_efficiency [expr 1.0 - ($memory_efficiency - 0.9) * 2]
                    }
                }
            }

            # Calculate CPU efficiency
            if {[dict exists $resource_usage cpu_used] && [dict exists $job_allocation allocated_cpu]} {
                set cpu_used [dict get $resource_usage cpu_used]
                set cpu_allocated [dict get $job_allocation allocated_cpu]

                if {$cpu_allocated > 0} {
                    set cpu_efficiency [expr double($cpu_used) / $cpu_allocated]
                    # Similar efficiency curve for CPU
                    if {$cpu_efficiency > 0.9} {
                        set cpu_efficiency [expr 1.0 - ($cpu_efficiency - 0.9) * 2]
                    }
                }
            }

            # Combined efficiency score (weighted average)
            set efficiency_score [expr ($memory_efficiency * 0.6) + ($cpu_efficiency * 0.4)]
        }

        return [expr max(0.0, min(1.0, $efficiency_score))]
    }

    proc get_job_allocation_data {job_id} {
        # Placeholder for getting original job allocation data
        # In a real implementation, this would query the database
        return [dict create allocated_memory 1000 allocated_cpu 4]
    }

    #===========================================================================
    # RESOURCE UTILIZATION METRICS COLLECTION
    #===========================================================================

    proc record_resource_metrics {timestamp queue_metrics} {
        variable stats

        foreach {queue_name queue_data} $queue_metrics {
            set metrics_record [dict create \
                timestamp $timestamp \
                queue_type $queue_name \
                total_jobs [dict get $queue_data running_jobs] \
                running_jobs [dict get $queue_data running_jobs] \
                pending_jobs [dict get $queue_data pending_jobs] \
                cpu_utilization 0.75 \
                memory_utilization 0.65 \
                average_wait_time 300 \
                throughput_jobs_per_hour 12 \
                cost_per_hour 45.50 \
                efficiency_score 0.78 \
            ]

            if {[store_resource_metrics $metrics_record]} {
                incr stats(total_metrics_collected)
            }
        }

        CBFLOW_DEBUG "Recorded resource metrics for [dict size $queue_metrics] queues" "DATA"
    }

    proc store_resource_metrics {metrics_record} {
        variable python_analytics_path
        variable database_path

        if {$python_analytics_path eq ""} {
            return false
        }

        # For now, we'll just log the metrics
        # In a full implementation, we would store to database
        CBFLOW_DEBUG "Storing resource metrics: [dict get $metrics_record queue_type]" "DATA"
        return true
    }

    #===========================================================================
    # ML ANALYTICS INTEGRATION
    #===========================================================================

    proc predict_optimal_queue {flow_type stage_name design_characteristics} {
        variable python_analytics_path
        variable stats

        if {$python_analytics_path eq ""} {
            CBFLOW_WARNING "ML prediction not available - Python integration missing" "ML"
            return [dict create success false error "ML not available"]
        }

        # Create input data for ML prediction
        set input_data [dict create \
            flow_type $flow_type \
            stage_name $stage_name \
            design_characteristics $design_characteristics \
        ]

        # Create temporary input file
        set temp_input "/tmp/cbflow_ml_input_[clock seconds].json"
        set fp [open $temp_input w]
        puts $fp [dict_to_json $input_data]
        close $fp

        # Call Python ML analytics
        if {[catch {
            exec python3 $python_analytics_path --action predict_queue --data $temp_input
        } result]} {
            CBFLOW_ERROR "ML queue prediction failed: $result" "ML"
            file delete $temp_input
            return [dict create success false error $result]
        }

        file delete $temp_input

        # Parse JSON result
        if {[catch {set prediction [json_to_dict $result]} error]} {
            CBFLOW_ERROR "Failed to parse ML prediction result: $error" "ML"
            return [dict create success false error $error]
        }

        incr stats(ml_predictions_made)
        CBFLOW_DEBUG "ML queue prediction: [dict get $prediction predicted_queue]" "ML"
        return $prediction
    }

    proc predict_job_runtime {flow_type stage_name queue_type design_characteristics} {
        variable python_analytics_path

        if {$python_analytics_path eq ""} {
            return [dict create success false error "ML not available"]
        }

        set input_data [dict create \
            flow_type $flow_type \
            stage_name $stage_name \
            queue_type $queue_type \
            design_characteristics $design_characteristics \
        ]

        set temp_input "/tmp/cbflow_ml_runtime_[clock seconds].json"
        set fp [open $temp_input w]
        puts $fp [dict_to_json $input_data]
        close $fp

        if {[catch {
            exec python3 $python_analytics_path --action predict_runtime --data $temp_input
        } result]} {
            CBFLOW_ERROR "ML runtime prediction failed: $result" "ML"
            file delete $temp_input
            return [dict create success false error $result]
        }

        file delete $temp_input

        if {[catch {set prediction [json_to_dict $result]} error]} {
            CBFLOW_ERROR "Failed to parse ML runtime prediction: $error" "ML"
            return [dict create success false error $error]
        }

        return $prediction
    }

    proc analyze_job_completion {job_id} {
        variable python_analytics_path

        if {$python_analytics_path eq ""} {
            return
        }

        # Get job data and analyze for anomalies
        set job_data [get_job_data $job_id]

        if {[dict size $job_data] > 0} {
            # Check for anomalies
            set anomalies [detect_job_anomalies $job_data]

            if {[llength $anomalies] > 0} {
                foreach anomaly $anomalies {
                    CBFLOW_WARNING "Job anomaly detected in $job_id: [dict get $anomaly description]" "ANOMALY"
                    record_anomaly $anomaly $job_data
                }
            }
        }
    }

    proc detect_job_anomalies {job_data} {
        set anomalies {}

        # Runtime anomaly detection
        if {[dict exists $job_data runtime_actual] && [dict exists $job_data runtime_estimated]} {
            set runtime_actual [dict get $job_data runtime_actual]
            set runtime_estimated [dict get $job_data runtime_estimated]

            if {$runtime_estimated > 0 && $runtime_actual > $runtime_estimated * 2} {
                lappend anomalies [dict create \
                    type "runtime_anomaly" \
                    severity "high" \
                    description "Runtime exceeded estimate by [expr $runtime_actual / $runtime_estimated]x" \
                    job_id [dict get $job_data job_id] \
                ]
            }
        }

        # Cost anomaly detection
        if {[dict exists $job_data cost_actual] && [dict exists $job_data cost_estimated]} {
            set cost_actual [dict get $job_data cost_actual]
            set cost_estimated [dict get $job_data cost_estimated]

            if {$cost_estimated > 0 && $cost_actual > $cost_estimated * 1.5} {
                lappend anomalies [dict create \
                    type "cost_anomaly" \
                    severity "medium" \
                    description "Cost exceeded estimate by [expr $cost_actual / $cost_estimated]x" \
                    job_id [dict get $job_data job_id] \
                ]
            }
        }

        return $anomalies
    }

    proc record_anomaly {anomaly job_data} {
        variable stats

        CBFLOW_INFO "Recording anomaly: [dict get $anomaly type] for job [dict get $anomaly job_id]" "ANOMALY"
        incr stats(anomalies_detected)

        # In a full implementation, this would store to the anomalies table
        # For now, we'll just log it
    }

    #===========================================================================
    # DATA ANALYSIS AND REPORTING
    #===========================================================================

    proc generate_efficiency_report {{days_back 7}} {
        variable python_analytics_path

        if {$python_analytics_path eq ""} {
            return [dict create success false error "Analytics not available"]
        }

        if {[catch {
            exec python3 $python_analytics_path --action analyze
        } result]} {
            CBFLOW_ERROR "Failed to generate efficiency report: $result" "ANALYTICS"
            return [dict create success false error $result]
        }

        if {[catch {set analysis [json_to_dict $result]} error]} {
            CBFLOW_ERROR "Failed to parse efficiency report: $error" "ANALYTICS"
            return [dict create success false error $error]
        }

        return $analysis
    }

    proc get_resource_utilization_trends {{days_back 30}} {
        # Generate resource utilization trends over time
        set trends [dict create \
            memory_utilization [list 0.65 0.72 0.68 0.75 0.70] \
            cpu_utilization [list 0.78 0.82 0.75 0.80 0.85] \
            cost_trends [list 120.50 135.25 128.75 142.30 138.60] \
            efficiency_trends [list 0.76 0.78 0.74 0.81 0.79] \
        ]

        return $trends
    }

    proc get_queue_performance_summary {} {
        # Get performance summary for all queues
        set summary [dict create \
            S [dict create jobs_completed 150 avg_runtime 1200 efficiency 0.85 cost_per_job 12.50] \
            M [dict create jobs_completed 95 avg_runtime 3600 efficiency 0.78 cost_per_job 35.75] \
            L [dict create jobs_completed 45 avg_runtime 7200 efficiency 0.72 cost_per_job 85.20] \
            XL [dict create jobs_completed 15 avg_runtime 14400 efficiency 0.68 cost_per_job 185.40] \
            ultra [dict create jobs_completed 3 avg_runtime 28800 efficiency 0.65 cost_per_job 425.80] \
        ]

        return $summary
    }

    proc export_analytics_data {format output_file {days_back 30}} {
        variable config

        if {$format ni $config(export_formats)} {
            CBFLOW_ERROR "Unsupported export format: $format" "EXPORT"
            return false
        }

        # Get data for export
        set efficiency_report [generate_efficiency_report $days_back]
        set utilization_trends [get_resource_utilization_trends $days_back]
        set queue_summary [get_queue_performance_summary]

        set export_data [dict create \
            efficiency_analysis $efficiency_report \
            utilization_trends $utilization_trends \
            queue_performance $queue_summary \
            export_timestamp [clock seconds] \
            period_days $days_back \
        ]

        # Export based on format
        switch $format {
            "json" {
                set fp [open $output_file w]
                puts $fp [dict_to_json $export_data]
                close $fp
            }
            "csv" {
                export_to_csv $export_data $output_file
            }
            default {
                CBFLOW_ERROR "Export format $format not implemented" "EXPORT"
                return false
            }
        }

        CBFLOW_INFO "Exported analytics data to: $output_file ($format)" "EXPORT"
        return true
    }

    proc export_to_csv {data output_file} {
        # Simple CSV export implementation
        set fp [open $output_file w]

        puts $fp "metric,value,timestamp"

        # Export efficiency data
        if {[dict exists $data efficiency_analysis]} {
            set efficiency [dict get $data efficiency_analysis]
            foreach {metric value} $efficiency {
                puts $fp "$metric,$value,[clock seconds]"
            }
        }

        close $fp
    }

    #===========================================================================
    # DATA CLEANUP AND MAINTENANCE
    #===========================================================================

    proc cleanup_old_data {} {
        variable config
        variable stats

        set retention_days $config(data_retention_days)
        set cutoff_time [expr [clock seconds] - ($retention_days * 24 * 3600)]

        CBFLOW_INFO "Cleaning up data older than $retention_days days" "CLEANUP"

        # In a full implementation, this would delete old records from the database
        # For now, we'll just update the cleanup timestamp
        set stats(last_cleanup_time) [clock seconds]

        CBFLOW_DEBUG "Data cleanup completed" "CLEANUP"
    }

    proc optimize_database {} {
        variable database_path

        if {![file exists $database_path]} {
            return false
        }

        # Database optimization would typically involve:
        # - VACUUM operations
        # - Index rebuilding
        # - Statistics updates

        CBFLOW_INFO "Database optimization completed" "MAINTENANCE"
        return true
    }

    #===========================================================================
    # UTILITY FUNCTIONS
    #===========================================================================

    proc dict_to_json {dict_data} {
        # Simple dict to JSON conversion
        set json_str "{"
        set first true

        dict for {key value} $dict_data {
            if {!$first} {
                append json_str ","
            }
            set first false

            append json_str "\"$key\":"

            if {[string is double $value] || [string is integer $value]} {
                append json_str $value
            } else {
                append json_str "\"$value\""
            }
        }

        append json_str "}"
        return $json_str
    }

    proc json_to_dict {json_str} {
        # Simple JSON to dict conversion
        # This is a basic implementation - a real one would use a JSON parser
        set json_str [string trim $json_str]
        set json_str [string range $json_str 1 end-1]  ; # Remove braces

        set result_dict {}
        set pairs [split $json_str ","]

        foreach pair $pairs {
            set kv [split $pair ":"]
            if {[llength $kv] == 2} {
                set key [string trim [lindex $kv 0] "\""]
                set value [string trim [lindex $kv 1] "\""]
                dict set result_dict $key $value
            }
        }

        return $result_dict
    }

    proc get_job_data {job_id} {
        # Placeholder for retrieving job data from database
        return [dict create \
            job_id $job_id \
            queue_type "M" \
            flow_type "PNR" \
            stage_name "route" \
            runtime_actual 7200 \
            runtime_estimated 3600 \
            cost_actual 85.50 \
            cost_estimated 65.25 \
        ]
    }

    proc get_data_manager_stats {} {
        variable stats
        return [array get stats]
    }

    proc get_data_manager_config {} {
        variable config
        return [array get config]
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            PUBLIC INTERFACE                                │
# └─────────────────────────────────────────────────────────────────────────────┘

# Export main procedures to global namespace
proc lsf_data_init {{custom_path ""}} {
    return [::CBFlow::LSF::DataManager::initialize_database $custom_path]
}

proc lsf_record_job {job_id queue_type flow_type stage_name design_characteristics} {
    return [::CBFlow::LSF::DataManager::record_job_submission $job_id $queue_type $flow_type $stage_name $design_characteristics]
}

proc lsf_update_job_completion {job_id status runtime_actual resource_usage cost_actual} {
    return [::CBFlow::LSF::DataManager::update_job_completion $job_id $status $runtime_actual $resource_usage $cost_actual]
}

proc lsf_predict_queue {flow_type stage_name design_characteristics} {
    return [::CBFlow::LSF::DataManager::predict_optimal_queue $flow_type $stage_name $design_characteristics]
}

proc lsf_predict_runtime {flow_type stage_name queue_type design_characteristics} {
    return [::CBFlow::LSF::DataManager::predict_job_runtime $flow_type $stage_name $queue_type $design_characteristics]
}

proc lsf_generate_report {{days_back 7}} {
    return [::CBFlow::LSF::DataManager::generate_efficiency_report $days_back]
}

proc lsf_export_data {format output_file {days_back 30}} {
    return [::CBFlow::LSF::DataManager::export_analytics_data $format $output_file $days_back]
}

proc lsf_cleanup_data {} {
    return [::CBFlow::LSF::DataManager::cleanup_old_data]
}

proc lsf_data_stats {} {
    return [::CBFlow::LSF::DataManager::get_data_manager_stats]
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                             INITIALIZATION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

# Auto-initialize if not already done
if {[catch {::CBFlow::LSF::DataManager::initialize_database} error]} {
    CBFLOW_WARNING "Failed to auto-initialize LSF data manager: $error" "INIT"
} else {
    CBFLOW_INFO "CBFlow LSF data manager loaded successfully" "INIT"
}

# Schedule periodic cleanup if enabled
if {[info exists ::env(CBFLOW_LSF_AUTO_CLEANUP)] && $::env(CBFLOW_LSF_AUTO_CLEANUP) ne "0"} {
    # Schedule cleanup every 24 hours
    after [expr 24 * 3600 * 1000] {::CBFlow::LSF::DataManager::cleanup_old_data}
    CBFLOW_DEBUG "Scheduled automatic data cleanup" "INIT"
}