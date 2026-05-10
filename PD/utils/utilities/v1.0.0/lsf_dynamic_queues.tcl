#!/usr/bin/env tclsh

# LSF Dynamic Queue Management System
# Provides intelligent queue creation and management based on ML analytics

# Source required modules
source [file join [file dirname [info script]] "lsf_utils.tcl"]
source [file join [file dirname [info script]] "lsf_data_manager.tcl"]
source [file join [file dirname [info script]] "error_utils.tcl"]

namespace eval ::lsf::dynamic {
    variable dynamic_queues [dict create]
    variable queue_creation_history [list]
    variable resource_efficiency_cache [dict create]

    # Configuration for dynamic queue creation
    variable config
    array set config {
        min_efficiency_threshold 0.7
        queue_lifetime_hours 24
        max_concurrent_dynamic_queues 10
        resource_buffer_factor 1.2
        cost_optimization_factor 0.85
    }
}

# Create a dynamic queue based on ML predictions and current resource needs
proc ::lsf::dynamic::create_dynamic_queue {flow_type stage_name design_characteristics} {
    variable dynamic_queues
    variable config

    CBFLOW_INFO "Creating dynamic queue for $flow_type:$stage_name" "LSF_DYNAMIC"

    # Get ML prediction for optimal resources
    set ml_prediction [get_ml_resource_prediction $flow_type $stage_name $design_characteristics]

    if {[dict size $ml_prediction] == 0} {
        CBFLOW_WARNING "No ML prediction available, using heuristic approach" "LSF_DYNAMIC"
        set ml_prediction [get_heuristic_resource_prediction $flow_type $stage_name $design_characteristics]
    }

    # Calculate optimal queue parameters
    set queue_spec [calculate_optimal_queue_spec $ml_prediction]

    # Generate unique queue name
    set queue_name [generate_dynamic_queue_name $flow_type $stage_name]

    # Check if similar queue already exists
    set existing_queue [find_similar_existing_queue $queue_spec]
    if {$existing_queue ne ""} {
        CBFLOW_INFO "Using existing similar queue: $existing_queue" "LSF_DYNAMIC"
        return $existing_queue
    }

    # Create the dynamic queue
    set success [create_lsf_queue $queue_name $queue_spec]

    if {$success} {
        # Register the new queue
        dict set dynamic_queues $queue_name [dict create \
            spec $queue_spec \
            created_time [clock seconds] \
            flow_type $flow_type \
            stage_name $stage_name \
            usage_count 0 \
            efficiency_history [list] \
        ]

        CBFLOW_INFO "Successfully created dynamic queue: $queue_name" "LSF_DYNAMIC"
        return $queue_name
    } else {
        CBFLOW_ERROR "Failed to create dynamic queue: $queue_name" "LSF_DYNAMIC"
        return ""
    }
}

# Get ML-based resource prediction
proc ::lsf::dynamic::get_ml_resource_prediction {flow_type stage_name design_characteristics} {
    # Use the ML analytics engine for prediction
    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_ml_analytics.py"]

    # Prepare input data for ML engine
    set input_data [dict create \
        flow_type $flow_type \
        stage_name $stage_name \
        design_characteristics $design_characteristics \
    ]

    # Create temporary file for data exchange
    set temp_file "/tmp/ml_prediction_input_[clock seconds]_[pid].json"
    set fp [open $temp_file w]
    puts $fp [dict_to_json $input_data]
    close $fp

    # Call ML engine
    set result_file "/tmp/ml_prediction_output_[clock seconds]_[pid].json"

    if {[catch {exec python3 $ml_script predict_optimal_queue $temp_file $result_file} ml_output]} {
        CBFLOW_WARNING "ML prediction failed: $ml_output" "LSF_DYNAMIC"
        file delete -force $temp_file
        return [dict create]
    }

    # Parse ML results
    set prediction [dict create]
    if {[file exists $result_file]} {
        set fp [open $result_file r]
        set json_data [read $fp]
        close $fp
        set prediction [json_to_dict $json_data]
        file delete -force $result_file
    }

    file delete -force $temp_file
    return $prediction
}

# Fallback heuristic resource prediction when ML is unavailable
proc ::lsf::dynamic::get_heuristic_resource_prediction {flow_type stage_name design_characteristics} {
    set prediction [dict create]

    # Extract design characteristics
    set gate_count [dict_get_default $design_characteristics "gate_count" 100000]
    set design_size [dict_get_default $design_characteristics "design_size" "medium"]

    # Heuristic rules based on flow type and stage
    switch $flow_type {
        "SYNTH" {
            switch $stage_name {
                "synthesis" {
                    if {$gate_count > 1000000} {
                        dict set prediction memory_gb 32
                        dict set prediction cpu_count 16
                        dict set prediction predicted_queue "L"
                    } else {
                        dict set prediction memory_gb 16
                        dict set prediction cpu_count 8
                        dict set prediction predicted_queue "M"
                    }
                }
                "optimization" {
                    dict set prediction memory_gb [expr {$gate_count / 50000 + 8}]
                    dict set prediction cpu_count [expr {min(16, max(4, $gate_count / 100000))}]
                    dict set prediction predicted_queue "M"
                }
            }
        }
        "PNR" {
            switch $stage_name {
                "route" -
                "route_opt" {
                    if {$gate_count > 2000000} {
                        dict set prediction memory_gb 128
                        dict set prediction cpu_count 64
                        dict set prediction predicted_queue "ultra"
                    } elseif {$gate_count > 1000000} {
                        dict set prediction memory_gb 64
                        dict set prediction cpu_count 32
                        dict set prediction predicted_queue "XL"
                    } else {
                        dict set prediction memory_gb 32
                        dict set prediction cpu_count 16
                        dict set prediction predicted_queue "L"
                    }
                }
                "floorplan" -
                "placement" {
                    dict set prediction memory_gb [expr {max(16, $gate_count / 40000)}]
                    dict set prediction cpu_count [expr {min(32, max(8, $gate_count / 80000))}]
                    dict set prediction predicted_queue "L"
                }
            }
        }
        "FP" {
            dict set prediction memory_gb 16
            dict set prediction cpu_count 8
            dict set prediction predicted_queue "M"
        }
        default {
            dict set prediction memory_gb 8
            dict set prediction cpu_count 4
            dict set prediction predicted_queue "S"
        }
    }

    dict set prediction confidence 0.6
    dict set prediction source "heuristic"

    return $prediction
}

# Calculate optimal queue specification based on prediction
proc ::lsf::dynamic::calculate_optimal_queue_spec {ml_prediction} {
    variable config

    # Extract predicted resources
    set base_memory [dict_get_default $ml_prediction "memory_gb" 8]
    set base_cpu [dict_get_default $ml_prediction "cpu_count" 4]
    set confidence [dict_get_default $ml_prediction "confidence" 0.5]

    # Apply buffer factor based on confidence
    set buffer_factor $config(resource_buffer_factor)
    if {$confidence < 0.7} {
        set buffer_factor [expr {$buffer_factor * 1.3}]
    }

    # Calculate final specifications
    set memory_gb [expr {int($base_memory * $buffer_factor)}]
    set cpu_count [expr {int($base_cpu * $buffer_factor)}]

    # Ensure minimum viable resources
    set memory_gb [expr {max(8, $memory_gb)}]
    set cpu_count [expr {max(4, $cpu_count)}]

    # Calculate runtime limit based on resource allocation
    set runtime_hours [calculate_runtime_estimate $memory_gb $cpu_count]

    return [dict create \
        memory "${memory_gb}GB" \
        cpu $cpu_count \
        runtime_limit "${runtime_hours}:00" \
        priority "medium" \
        queue_type "dynamic" \
    ]
}

# Generate unique dynamic queue name
proc ::lsf::dynamic::generate_dynamic_queue_name {flow_type stage_name} {
    set timestamp [clock seconds]
    set short_timestamp [string range $timestamp end-5 end]
    return "dyn_${flow_type}_${stage_name}_${short_timestamp}"
}

# Find existing queue with similar specifications
proc ::lsf::dynamic::find_similar_existing_queue {target_spec} {
    variable dynamic_queues

    set target_memory [dict get $target_spec memory]
    set target_cpu [dict get $target_spec cpu]

    # Parse target memory (remove GB suffix)
    regexp {(\d+)GB} $target_memory -> target_mem_val

    dict for {queue_name queue_info} $dynamic_queues {
        set spec [dict get $queue_info spec]
        set existing_memory [dict get $spec memory]
        set existing_cpu [dict get $spec cpu]

        # Parse existing memory
        regexp {(\d+)GB} $existing_memory -> existing_mem_val

        # Check if specifications are within 20% tolerance
        set mem_ratio [expr {double($existing_mem_val) / $target_mem_val}]
        set cpu_ratio [expr {double($existing_cpu) / $target_cpu}]

        if {$mem_ratio >= 0.8 && $mem_ratio <= 1.2 &&
            $cpu_ratio >= 0.8 && $cpu_ratio <= 1.2} {
            # Check if queue is still active
            if {[is_queue_active $queue_name]} {
                return $queue_name
            }
        }
    }

    return ""
}

# Create LSF queue with specified parameters
proc ::lsf::dynamic::create_lsf_queue {queue_name queue_spec} {
    set memory [dict get $queue_spec memory]
    set cpu [dict get $queue_spec cpu]
    set runtime_limit [dict get $queue_spec runtime_limit]

    # Build LSF queue creation command
    set lsf_cmd [list bsub \
        -q $queue_name \
        -M $memory \
        -n $cpu \
        -W $runtime_limit \
        -J "queue_creator" \
        "sleep 1" \
    ]

    # Execute queue creation
    if {[catch {exec {*}$lsf_cmd} output]} {
        CBFLOW_ERROR "Queue creation failed: $output" "LSF_DYNAMIC"
        return 0
    }

    # Verify queue was created successfully
    after 2000  ;# Wait 2 seconds for queue to be registered

    if {[catch {exec bqueues $queue_name} queue_info]} {
        CBFLOW_ERROR "Queue verification failed: $queue_info" "LSF_DYNAMIC"
        return 0
    }

    return 1
}

# Check if a queue is still active
proc ::lsf::dynamic::is_queue_active {queue_name} {
    if {[catch {exec bqueues $queue_name} output]} {
        return 0
    }

    # Parse queue status from output
    if {[regexp {Open:Active} $output]} {
        return 1
    }

    return 0
}

# Calculate runtime estimate based on resources
proc ::lsf::dynamic::calculate_runtime_estimate {memory_gb cpu_count} {
    # Base runtime calculation heuristic
    set base_hours 4

    # Adjust based on resource allocation
    if {$memory_gb >= 64} {
        set base_hours 12
    } elseif {$memory_gb >= 32} {
        set base_hours 8
    } elseif {$memory_gb >= 16} {
        set base_hours 6
    }

    # CPU factor adjustment
    if {$cpu_count >= 32} {
        set base_hours [expr {int($base_hours * 1.5)}]
    } elseif {$cpu_count >= 16} {
        set base_hours [expr {int($base_hours * 1.2)}]
    }

    return [expr {min(24, max(2, $base_hours))}]
}

# Cleanup expired dynamic queues
proc ::lsf::dynamic::cleanup_expired_queues {} {
    variable dynamic_queues
    variable config

    set current_time [clock seconds]
    set expiry_time [expr {$config(queue_lifetime_hours) * 3600}]

    set cleanup_count 0
    dict for {queue_name queue_info} $dynamic_queues {
        set created_time [dict get $queue_info created_time]
        set age [expr {$current_time - $created_time}]

        if {$age > $expiry_time} {
            if {[cleanup_dynamic_queue $queue_name]} {
                dict unset dynamic_queues $queue_name
                incr cleanup_count
            }
        }
    }

    CBFLOW_INFO "Cleaned up $cleanup_count expired dynamic queues" "LSF_DYNAMIC"
    return $cleanup_count
}

# Cleanup a specific dynamic queue
proc ::lsf::dynamic::cleanup_dynamic_queue {queue_name} {
    # Check if queue has any running jobs
    if {[catch {exec bjobs -q $queue_name} job_output]} {
        # No jobs running, safe to delete
        if {[catch {exec bqdel $queue_name} delete_output]} {
            CBFLOW_WARNING "Failed to delete queue $queue_name: $delete_output" "LSF_DYNAMIC"
            return 0
        }
        return 1
    } else {
        CBFLOW_INFO "Queue $queue_name has running jobs, deferring cleanup" "LSF_DYNAMIC"
        return 0
    }
}

# Get current dynamic queue status
proc ::lsf::dynamic::get_dynamic_queue_status {} {
    variable dynamic_queues

    set status [dict create \
        total_queues [dict size $dynamic_queues] \
        active_queues 0 \
        total_usage 0 \
    ]

    dict for {queue_name queue_info} $dynamic_queues {
        if {[is_queue_active $queue_name]} {
            dict incr status active_queues
        }
        dict incr status total_usage [dict get $queue_info usage_count]
    }

    return $status
}

# Utility function to convert dict to JSON
proc ::lsf::dynamic::dict_to_json {dict_data} {
    set json "{"
    set first 1
    dict for {key value} $dict_data {
        if {!$first} {
            append json ","
        }
        append json "\"$key\": "
        if {[string is integer $value] || [string is double $value]} {
            append json "$value"
        } else {
            append json "\"$value\""
        }
        set first 0
    }
    append json "}"
    return $json
}

# Utility function to convert JSON to dict
proc ::lsf::dynamic::json_to_dict {json_data} {
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

# Utility function to safely get dict value with default
proc ::lsf::dynamic::dict_get_default {dict_data key default_value} {
    if {[dict exists $dict_data $key]} {
        return [dict get $dict_data $key]
    } else {
        return $default_value
    }
}