#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ML Analytics Configuration
# Resource prediction, queue optimization, and data collection settings
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ ML Analytics Settings ─────────────────────────────────────────────────────┐
array set ml {
    analytics,enabled                          "true"
    analytics,data_retention_days              "90"
    analytics,model_update_frequency           "weekly"
    analytics,prediction_confidence_threshold  "0.8"
    analytics,learning_rate                    "0.01"

    # ── Data Collection ──
    data_collection,metrics {
        "memory_utilization" "cpu_utilization" "runtime_actual"
        "queue_wait_time" "resource_efficiency" "cost_per_hour"
        "job_completion_rate" "error_rate" "restart_count"
    }
    data_collection,sampling_interval  "60"
    data_collection,database_path      "data/lsf_analytics.db"
    data_collection,log_retention      "30"

    # ── Queue Prediction Model ──
    models,queue_prediction,type     "random_forest"
    models,queue_prediction,features {
        "design_size" "flow_type" "stage_type" "historical_memory_usage"
        "cpu_requirements" "runtime_estimate" "complexity_score"
    }
    models,queue_prediction,target   "optimal_queue_type"

    # ── Resource Optimization Model ──
    models,resource_optimization,type     "neural_network"
    models,resource_optimization,features {
        "current_utilization" "pending_jobs" "time_of_day" "project_priority"
        "cost_constraints" "deadline_pressure" "resource_availability"
    }
    models,resource_optimization,target   "resource_allocation_strategy"
}
