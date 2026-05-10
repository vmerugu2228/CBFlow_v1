#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          CBFlow LSF Management Configuration                  ║
# ║                    Intelligent Resource Allocation System                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Description: Comprehensive LSF configuration with ML-based resource optimization
# Version: 1.0.0
# Author: CBFlow LSF Management System
# Date: 2025-10-08
#
# Features:
# - Intelligent LSF queue definitions (XS, S, M, L, XL, ultra)
# - ML analytics configuration for resource optimization
# - Dynamic queue creation policies
# - Cost optimization and performance tuning
# - Node-specific resource allocation strategies

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           NAMESPACE DEFINITION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF {
    variable version "1.0.0"
    variable config_date "2025-10-08"
    variable debug_mode false
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        LSF QUEUE DEFINITIONS                               │
# └─────────────────────────────────────────────────────────────────────────────┘

# Main LSF queue configuration array
array set lsf {
    # ═══════════════════════════════════════════════════════════════════════════
    # CORE LSF QUEUE TYPES
    # ═══════════════════════════════════════════════════════════════════════════

    # Extra Small Queue - Interactive viewing, gvim, large text file browsing
    queue_types,XS,memory "4GB"
    queue_types,XS,cpu "2"
    queue_types,XS,runtime_limit "1:00"
    queue_types,XS,description "Extra small jobs - gvim sessions, large text file viewing, interactive log browsing"
    queue_types,XS,priority "60"
    queue_types,XS,cost_factor "0.5"
    queue_types,XS,typical_nodes "gvim text_view log_browse interactive_edit"
    queue_types,XS,max_concurrent "30"

    # Small Queue - Light workloads, fast turnaround
    queue_types,S,memory "8GB"
    queue_types,S,cpu "4"
    queue_types,S,runtime_limit "2:00"
    queue_types,S,description "Small jobs - synthesis inputs, validation, quick checks"
    queue_types,S,priority "50"
    queue_types,S,cost_factor "1.0"
    queue_types,S,typical_nodes "inputs validate setup finish"
    queue_types,S,max_concurrent "20"

    # Medium Queue - Standard workloads, balanced resources
    queue_types,M,memory "16GB"
    queue_types,M,cpu "8"
    queue_types,M,runtime_limit "4:00"
    queue_types,M,description "Medium jobs - synthesis, floorplan, basic PNR stages"
    queue_types,M,priority "40"
    queue_types,M,cost_factor "2.0"
    queue_types,M,typical_nodes "synthesis floorplan powerplan cts"
    queue_types,M,max_concurrent "15"

    # Large Queue - Heavy workloads, high memory requirements
    queue_types,L,memory "32GB"
    queue_types,L,cpu "16"
    queue_types,L,runtime_limit "8:00"
    queue_types,L,description "Large jobs - placement, routing, timing optimization"
    queue_types,L,priority "30"
    queue_types,L,cost_factor "4.0"
    queue_types,L,typical_nodes "placement route route_opt signoff"
    queue_types,L,max_concurrent "10"

    # Extra Large Queue - Very heavy workloads, complex designs
    queue_types,XL,memory "64GB"
    queue_types,XL,cpu "32"
    queue_types,XL,runtime_limit "12:00"
    queue_types,XL,description "Extra large jobs - full chip integration, complex hierarchical flows"
    queue_types,XL,priority "20"
    queue_types,XL,cost_factor "8.0"
    queue_types,XL,typical_nodes "hierarchical_integration full_chip_route eco_optimization"
    queue_types,XL,max_concurrent "5"

    # Ultra Queue - Massive workloads, extreme requirements
    queue_types,ultra,memory "128GB"
    queue_types,ultra,cpu "64"
    queue_types,ultra,runtime_limit "24:00"
    queue_types,ultra,description "Ultra large jobs - full chip signoff, massive designs"
    queue_types,ultra,priority "10"
    queue_types,ultra,cost_factor "16.0"
    queue_types,ultra,typical_nodes "full_chip_signoff massive_eco final_integration"
    queue_types,ultra,max_concurrent "2"

    # ═══════════════════════════════════════════════════════════════════════════
    # QUEUE MANAGEMENT POLICIES
    # ═══════════════════════════════════════════════════════════════════════════

    # Available queue types list
    available_queues "XS S M L XL ultra"
    default_queue "M"
    emergency_queue "ultra"

    # Queue selection strategies
    selection_strategy "ml_optimized"  ; # Options: static, load_balanced, ml_optimized, cost_optimized
    fallback_strategy "next_larger"    ; # Options: next_larger, best_available, fail

    # Resource scaling policies
    auto_scaling_enabled "true"
    scale_up_threshold "0.8"          ; # Scale up when utilization > 80%
    scale_down_threshold "0.3"        ; # Scale down when utilization < 30%
    scaling_cooldown "300"             ; # 5 minutes between scaling operations

    # ═══════════════════════════════════════════════════════════════════════════
    # FLOW-SPECIFIC QUEUE MAPPINGS
    # ═══════════════════════════════════════════════════════════════════════════

    # SYNTH Flow Queue Preferences (stages: inputs1, mmmc_setup1, synthesis1, export_data1, release_data1)
    flow_mapping,SYNTH,inputs "S"
    flow_mapping,SYNTH,inputs1 "S"
    flow_mapping,SYNTH,mmmc_setup "S"
    flow_mapping,SYNTH,mmmc_setup1 "S"
    flow_mapping,SYNTH,synthesis "M"
    flow_mapping,SYNTH,synthesis1 "M"
    flow_mapping,SYNTH,export_data "S"
    flow_mapping,SYNTH,export_data1 "S"
    flow_mapping,SYNTH,release_data "S"
    flow_mapping,SYNTH,release_data1 "S"

    # FP Flow Queue Preferences (stages: inputs , import_design, floorplan, powerplan, export_data, release_data)
    flow_mapping,FP,inputs "S"
    flow_mapping,FP,import_design "M"
    flow_mapping,FP,floorplan "M"
    flow_mapping,FP,powerplan "L"
    flow_mapping,FP,post_floorplan "M"
    flow_mapping,FP,export_data "S"
    flow_mapping,FP,release_data "S"

    # PNR Flow Queue Preferences (stages: inputs 1, place1, cts1, cts_opt1, route1, pro1, signoff1, export_data1, release_data1)
    flow_mapping,PNR,inputs "S"
    flow_mapping,PNR,inputs1 "S"
    flow_mapping,PNR,place "L"
    flow_mapping,PNR,place1 "L"
    flow_mapping,PNR,cts "L"
    flow_mapping,PNR,cts1 "L"
    flow_mapping,PNR,cts_opt "L"
    flow_mapping,PNR,cts_opt1 "L"
    flow_mapping,PNR,route "XL"
    flow_mapping,PNR,route1 "XL"
    flow_mapping,PNR,pro "L"
    flow_mapping,PNR,pro1 "L"
    flow_mapping,PNR,signoff "L"
    flow_mapping,PNR,signoff1 "L"
    flow_mapping,PNR,export_data "M"
    flow_mapping,PNR,export_data1 "M"
    flow_mapping,PNR,release_data "S"
    flow_mapping,PNR,release_data1 "S"

    # SYNTH_PNR Flow Queue Preferences
    flow_mapping,SYNTH_PNR,inputs "S"
    flow_mapping,SYNTH_PNR,inputs1 "S"
    flow_mapping,SYNTH_PNR,init_design "S"
    flow_mapping,SYNTH_PNR,init_design1 "S"
    flow_mapping,SYNTH_PNR,synthesis "M"
    flow_mapping,SYNTH_PNR,synthesis1 "M"
    flow_mapping,SYNTH_PNR,place "L"
    flow_mapping,SYNTH_PNR,place1 "L"
    flow_mapping,SYNTH_PNR,cts "L"
    flow_mapping,SYNTH_PNR,cts1 "L"
    flow_mapping,SYNTH_PNR,cts_opt "L"
    flow_mapping,SYNTH_PNR,cts_opt1 "L"
    flow_mapping,SYNTH_PNR,route "XL"
    flow_mapping,SYNTH_PNR,route1 "XL"
    flow_mapping,SYNTH_PNR,pro "L"
    flow_mapping,SYNTH_PNR,pro1 "L"
    flow_mapping,SYNTH_PNR,signoff "M"
    flow_mapping,SYNTH_PNR,signoff1 "M"
    flow_mapping,SYNTH_PNR,export_data "S"
    flow_mapping,SYNTH_PNR,export_data1 "S"
    flow_mapping,SYNTH_PNR,release_data "S"
    flow_mapping,SYNTH_PNR,release_data1 "S"

    # STA Flow Queue Preferences (8 stages: inputs, mmmc_setup, extraction, timing_setup, timing_hold, reporting, export_data, release_data)
    flow_mapping,STA,inputs "S"
    flow_mapping,STA,inputs1 "S"
    flow_mapping,STA,mmmc_setup "S"
    flow_mapping,STA,mmmc_setup1 "S"
    flow_mapping,STA,extraction "L"
    flow_mapping,STA,extraction1 "L"
    flow_mapping,STA,timing "L"
    flow_mapping,STA,timing1 "L"
    flow_mapping,STA,reporting "M"
    flow_mapping,STA,reporting1 "M"
    flow_mapping,STA,export_data "S"
    flow_mapping,STA,export_data1 "S"
    flow_mapping,STA,release_data "S"
    flow_mapping,STA,release_data1 "S"

    # LEC Flow Queue Preferences (stages: inputs , setup, compare, analyze)
    flow_mapping,LEC,inputs "S"
    flow_mapping,LEC,setup "M"
    flow_mapping,LEC,compare "M"
    flow_mapping,LEC,analyze "S"

    # EMIR Flow Queue Preferences (stages: inputs , power_analysis, ir_drop, thermal_analysis)
    flow_mapping,EMIR,inputs "S"
    flow_mapping,EMIR,power_analysis "L"
    flow_mapping,EMIR,ir_drop "L"
    flow_mapping,EMIR,thermal_analysis "XL"

    # PV Flow Queue Preferences (stages: inputs , drc, lvs, erc, perc, merge_data, release_data)
    flow_mapping,PV,inputs "S"
    flow_mapping,PV,drc "L"
    flow_mapping,PV,lvs "L"
    flow_mapping,PV,erc "M"
    flow_mapping,PV,perc "M"
    flow_mapping,PV,merge_data "S"
    flow_mapping,PV,release_data "S"

    # ECO Flow Queue Preferences (stages: inputs , eco, export_db)
    flow_mapping,ECO,inputs "S"
    flow_mapping,ECO,eco "L"
    flow_mapping,ECO,export_db "M"

    # CLP Flow Queue Preferences (stages: inputs , clp, export_data, release_data)
    flow_mapping,CLP,inputs "S"
    flow_mapping,CLP,clp "M"
    flow_mapping,CLP,export_data "S"
    flow_mapping,CLP,release_data "S"

    # POPT Flow Queue Preferences (stages: inputs , merge_timing, power_opt, post_merge, release_data)
    flow_mapping,POPT,inputs "S"
    flow_mapping,POPT,merge_timing "M"
    flow_mapping,POPT,power_opt "L"
    flow_mapping,POPT,post_merge "M"
    flow_mapping,POPT,release_data "S"

    # FCFP Flow Queue Preferences (stages: inputs , fc_floorplan, fc_powerplan, fc_post_floorplan, export_data, release_data)
    flow_mapping,FCFP,inputs "S"
    flow_mapping,FCFP,fc_floorplan "L"
    flow_mapping,FCFP,fc_powerplan "L"
    flow_mapping,FCFP,fc_post_floorplan "M"
    flow_mapping,FCFP,export_data "S"
    flow_mapping,FCFP,release_data "S"

    # ═══════════════════════════════════════════════════════════════════════════
    # ML ANALYTICS CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════════

    # ML Analytics Settings
    ml_analytics,enabled "true"
    ml_analytics,data_retention_days "90"
    ml_analytics,model_update_frequency "weekly"
    ml_analytics,prediction_confidence_threshold "0.8"
    ml_analytics,learning_rate "0.01"

    # Data Collection Configuration
    data_collection,metrics {
        "memory_utilization" "cpu_utilization" "runtime_actual"
        "queue_wait_time" "resource_efficiency" "cost_per_hour"
        "job_completion_rate" "error_rate" "restart_count"
    }
    data_collection,sampling_interval "60"  ; # seconds
    data_collection,database_path "data/lsf_analytics.db"
    data_collection,log_retention "30"      ; # days

    # ML Model Configuration
    ml_models,queue_prediction,type "random_forest"
    ml_models,queue_prediction,features {
        "design_size" "flow_type" "stage_type" "historical_memory_usage"
        "cpu_requirements" "runtime_estimate" "complexity_score"
    }
    ml_models,queue_prediction,target "optimal_queue_type"

    ml_models,resource_optimization,type "neural_network"
    ml_models,resource_optimization,features {
        "current_utilization" "pending_jobs" "time_of_day" "project_priority"
        "cost_constraints" "deadline_pressure" "resource_availability"
    }
    ml_models,resource_optimization,target "resource_allocation_strategy"

    # ═══════════════════════════════════════════════════════════════════════════
    # DYNAMIC QUEUE MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════════════

    # Dynamic Queue Creation
    dynamic_queues,enabled "true"
    dynamic_queues,auto_create_threshold "0.9"  ; # Create when existing queues > 90% utilized
    dynamic_queues,max_dynamic_queues "5"
    dynamic_queues,cleanup_idle_time "3600"     ; # Remove after 1 hour idle

    # Custom Queue Templates
    dynamic_templates,high_memory,memory "256GB"
    dynamic_templates,high_memory,cpu "32"
    dynamic_templates,high_memory,runtime_limit "48:00"
    dynamic_templates,high_memory,description "Dynamic high-memory queue for complex designs"
    dynamic_templates,high_memory,cost_factor "32.0"

    dynamic_templates,high_cpu,memory "64GB"
    dynamic_templates,high_cpu,cpu "128"
    dynamic_templates,high_cpu,runtime_limit "12:00"
    dynamic_templates,high_cpu,description "Dynamic high-CPU queue for parallel processing"
    dynamic_templates,high_cpu,cost_factor "24.0"

    dynamic_templates,emergency,memory "512GB"
    dynamic_templates,emergency,cpu "128"
    dynamic_templates,emergency,runtime_limit "72:00"
    dynamic_templates,emergency,description "Emergency queue for critical deadlines"
    dynamic_templates,emergency,cost_factor "64.0"
    dynamic_templates,emergency,priority "5"

    # ═══════════════════════════════════════════════════════════════════════════
    # COST OPTIMIZATION CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════════

    # Cost Management
    cost_optimization,enabled "true"
    cost_optimization,budget_tracking "true"
    cost_optimization,cost_per_cpu_hour "0.50"   ; # USD
    cost_optimization,cost_per_gb_hour "0.10"    ; # USD
    cost_optimization,budget_alerts "true"
    cost_optimization,budget_threshold_warning "0.8"  ; # 80% of budget
    cost_optimization,budget_threshold_critical "0.95" ; # 95% of budget

    # Resource Efficiency Targets
    efficiency_targets,memory_utilization "0.85"  ; # Target 85% memory utilization
    efficiency_targets,cpu_utilization "0.90"     ; # Target 90% CPU utilization
    efficiency_targets,queue_wait_time "300"      ; # Max 5 minutes wait time
    efficiency_targets,job_completion_rate "0.98" ; # 98% successful completion

    # ═══════════════════════════════════════════════════════════════════════════
    # MONITORING AND ALERTING
    # ═══════════════════════════════════════════════════════════════════════════

    # Monitoring Configuration
    monitoring,enabled "true"
    monitoring,dashboard_update_interval "30"    ; # seconds
    monitoring,alert_check_interval "60"         ; # seconds
    monitoring,health_check_interval "300"       ; # seconds

    # Alert Thresholds
    alerts,high_memory_usage "0.95"
    alerts,high_cpu_usage "0.95"
    alerts,long_queue_wait "1800"               ; # 30 minutes
    alerts,job_failure_rate "0.1"               ; # 10% failure rate
    alerts,cost_overrun "1.2"                   ; # 20% over budget

    # Notification Settings
    notifications,email_enabled "true"
    notifications,slack_enabled "false"
    notifications,dashboard_enabled "true"
    notifications,log_level "INFO"

    # ═══════════════════════════════════════════════════════════════════════════
    # INTEGRATION SETTINGS
    # ═══════════════════════════════════════════════════════════════════════════

    # LSF Integration
    lsf_integration,submit_command "bsub"
    lsf_integration,query_command "bjobs"
    lsf_integration,kill_command "bkill"
    lsf_integration,queue_info_command "bqueues"
    lsf_integration,host_info_command "bhosts"

    # CBFlow Integration
    cbflow_integration,makefile_integration "true"
    cbflow_integration,xterm_integration "true"
    cbflow_integration,error_handling_integration "true"
    cbflow_integration,status_reporting_integration "true"

    # External Tool Integration
    external_tools,python_path "/usr/bin/python3"
    external_tools,sqlite_path "/usr/bin/sqlite3"
    external_tools,ml_library "scikit-learn"
    external_tools,plotting_library "matplotlib"

    # ═══════════════════════════════════════════════════════════════════════════
    # SECURITY AND PERMISSIONS
    # ═══════════════════════════════════════════════════════════════════════════

    # Security Settings
    security,user_authentication "true"
    security,resource_quotas "true"
    security,audit_logging "true"
    security,access_control "project_based"

    # Resource Limits
    limits,max_jobs_per_user "50"
    limits,max_cpu_hours_per_project "10000"
    limits,max_memory_gb_hours_per_project "50000"
    limits,max_concurrent_jobs "100"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     LSF CONFIGURATION PROCEDURES                           │
# └─────────────────────────────────────────────────────────────────────────────┘

namespace eval ::CBFlow::LSF {

    #===========================================================================
    # QUEUE MANAGEMENT PROCEDURES
    #===========================================================================

    proc get_queue_info {queue_type} {
        global lsf

        if {![info exists lsf(queue_types,$queue_type,memory)]} {
            return {}
        }

        return [list \
            memory $lsf(queue_types,$queue_type,memory) \
            cpu $lsf(queue_types,$queue_type,cpu) \
            runtime_limit $lsf(queue_types,$queue_type,runtime_limit) \
            description $lsf(queue_types,$queue_type,description) \
            priority $lsf(queue_types,$queue_type,priority) \
            cost_factor $lsf(queue_types,$queue_type,cost_factor) \
        ]
    }

    proc get_available_queues {} {
        global lsf
        return $lsf(available_queues)
    }

    proc get_recommended_queue {flow_type stage_name} {
        global lsf

        set mapping_key "flow_mapping,${flow_type},${stage_name}"
        if {[info exists lsf($mapping_key)]} {
            return $lsf($mapping_key)
        }

        # Fallback to default queue
        return $lsf(default_queue)
    }

    #===========================================================================
    # ML ANALYTICS INTERFACE PROCEDURES
    #===========================================================================

    proc is_ml_analytics_enabled {} {
        global lsf
        return [expr {$lsf(ml_analytics,enabled) eq "true"}]
    }

    proc get_ml_model_config {model_name} {
        global lsf

        set config {}
        foreach key [array names lsf "ml_models,${model_name},*"] {
            set param [lindex [split $key ","] 2]
            lappend config $param $lsf($key)
        }

        return $config
    }

    proc get_data_collection_config {} {
        global lsf

        return [list \
            metrics $lsf(data_collection,metrics) \
            sampling_interval $lsf(data_collection,sampling_interval) \
            database_path $lsf(data_collection,database_path) \
            log_retention $lsf(data_collection,log_retention) \
        ]
    }

    #===========================================================================
    # COST OPTIMIZATION PROCEDURES
    #===========================================================================

    proc calculate_job_cost {queue_type runtime_hours} {
        global lsf

        if {![info exists lsf(queue_types,$queue_type,memory)]} {
            return 0.0
        }

        set memory_gb [string map {"GB" ""} $lsf(queue_types,$queue_type,memory)]
        set cpu_count $lsf(queue_types,$queue_type,cpu)
        set cost_factor $lsf(queue_types,$queue_type,cost_factor)

        set cpu_cost [expr {$cpu_count * $lsf(cost_optimization,cost_per_cpu_hour) * $runtime_hours}]
        set memory_cost [expr {$memory_gb * $lsf(cost_optimization,cost_per_gb_hour) * $runtime_hours}]

        return [expr {($cpu_cost + $memory_cost) * $cost_factor}]
    }

    proc is_cost_optimization_enabled {} {
        global lsf
        return [expr {$lsf(cost_optimization,enabled) eq "true"}]
    }

    #===========================================================================
    # VALIDATION PROCEDURES
    #===========================================================================

    proc validate_lsf_config {} {
        global lsf

        set validation_errors {}

        # Validate required queues exist
        foreach queue $lsf(available_queues) {
            if {![info exists lsf(queue_types,$queue,memory)]} {
                lappend validation_errors "Queue type '$queue' missing memory specification"
            }
            if {![info exists lsf(queue_types,$queue,cpu)]} {
                lappend validation_errors "Queue type '$queue' missing CPU specification"
            }
        }

        # Validate default queue exists
        if {$lsf(default_queue) ni $lsf(available_queues)} {
            lappend validation_errors "Default queue '$lsf(default_queue)' not in available queues"
        }

        # Validate ML analytics configuration
        if {[is_ml_analytics_enabled]} {
            if {![info exists lsf(data_collection,database_path)]} {
                lappend validation_errors "ML analytics enabled but database path not specified"
            }
        }

        return $validation_errors
    }

    #===========================================================================
    # CONFIGURATION REPORTING
    #===========================================================================

    proc print_lsf_config_summary {} {
        global lsf

        puts "═══════════════════════════════════════════════════════════════════════════"
        puts "CBFlow LSF Configuration Summary"
        puts "═══════════════════════════════════════════════════════════════════════════"
        puts "Version: $::CBFlow::LSF::version"
        puts "Date: $::CBFlow::LSF::config_date"
        puts ""

        puts "Available Queues:"
        foreach queue $lsf(available_queues) {
            set info [get_queue_info $queue]
            puts "  $queue: [dict get $info memory] RAM, [dict get $info cpu] CPUs"
            puts "      Description: [dict get $info description]"
            puts "      Cost Factor: [dict get $info cost_factor]x"
        }
        puts ""

        puts "ML Analytics: [expr {[is_ml_analytics_enabled] ? \"Enabled\" : \"Disabled\"}]"
        puts "Cost Optimization: [expr {[is_cost_optimization_enabled] ? \"Enabled\" : \"Disabled\"}]"
        puts "Dynamic Queues: [expr {$lsf(dynamic_queues,enabled) eq \"true\" ? \"Enabled\" : \"Disabled\"}]"
        puts ""

        set errors [validate_lsf_config]
        if {[llength $errors] > 0} {
            puts "Configuration Errors:"
            foreach error $errors {
                puts "  ❌ $error"
            }
        } else {
            puts "✅ LSF Configuration validation passed"
        }
        puts "═══════════════════════════════════════════════════════════════════════════"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            INITIALIZATION                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

# Validate configuration on load
set validation_errors [::CBFlow::LSF::validate_lsf_config]
if {[llength $validation_errors] > 0} {
    puts stderr "ERROR: LSF configuration validation failed:"
    foreach error $validation_errors {
        puts stderr "  - $error"
    }
} else {
    puts "INFO: CBFlow LSF configuration loaded successfully"
    if {$::CBFlow::LSF::debug_mode} {
        ::CBFlow::LSF::print_lsf_config_summary
    }
}

# Export key procedures to global namespace for easy access
proc get_lsf_queue_info {queue_type} {
    return [::CBFlow::LSF::get_queue_info $queue_type]
}

proc get_lsf_recommended_queue {flow_type stage_name} {
    return [::CBFlow::LSF::get_recommended_queue $flow_type $stage_name]
}

proc calculate_lsf_job_cost {queue_type runtime_hours} {
    return [::CBFlow::LSF::calculate_job_cost $queue_type $runtime_hours]
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL LAUNCH CONFIGURATION
# (Outside array set — values with spaces need individual set statements)
# ═══════════════════════════════════════════════════════════════════════════════

# Module load commands per tool
set lsf(module,fc)          "module load synopsysFusionCompiler/2025.06-SP2"
set lsf(module,pt)          "module load synopsysPrimeTime/2025.06"
set lsf(module,fm)          "module load synopsysFormality/2025.06"
set lsf(module,vc_lp)       "module load synopsysVCLP/2025.06"
set lsf(module,icv)         "module load synopsysICV/2025.06"
set lsf(module,redhawk)     "module load synopsysRedHawk/2025.06"
set lsf(module,genus)       "module load cadenceGenus/23.1"
set lsf(module,innovus)     "module load cadenceInnovus/23.1"
set lsf(module,tempus)      "module load cadenceTempus/23.1"

# Tool shell commands
set lsf(tool_shell,fc)      "fc_shell"
set lsf(tool_shell,pt)      "pt_shell"
set lsf(tool_shell,fm)      "fm_shell"
set lsf(tool_shell,vc_lp)   "vc_lp_shell"
set lsf(tool_shell,icv)     "icv"
set lsf(tool_shell,redhawk) "redhawk"
set lsf(tool_shell,genus)   "genus"
set lsf(tool_shell,innovus) "innovus"
set lsf(tool_shell,tempus)  "tempus"

# Wrapper shell (for module load compatibility)
set lsf(tool_wrapper_shell) "/bin/csh -f"

# LSF bsub settings
set lsf(bsub,project)       "RD"
set lsf(bsub,queue)         "normal_rhel8"
set lsf(bsub,affinity)      "affinity\[core(1):cpubind=socket:membind=localonly\]"

# XTerm settings
set lsf(xterm,enabled)      "true"
set lsf(xterm,command)       "xterm"
set lsf(xterm,geometry)      "200x50"