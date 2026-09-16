# CBFlow LSF Configuration Guide

## Overview

This guide covers all aspects of configuring the CBFlow LSF Management System, from basic queue setup to advanced ML analytics and cost management.

## Configuration Files Structure

```
core/config/
├── flow/v1.0.0/
│   └── lsf_config.tcl              # Main LSF configuration
└── project/phoenix/v1.0.0/
    └── phoenix_config.tcl          # Project-specific LSF settings
```

## Main LSF Configuration (`lsf_config.tcl`)

### Basic Queue Configuration

```tcl
# LSF Queue Definitions
array set lsf {
    # Small Queue - Light workloads, fast turnaround
    queue_types,S,memory "8GB"
    queue_types,S,cpu "4"
    queue_types,S,runtime_limit "2:00"
    queue_types,S,priority "normal"

    # Medium Queue - Standard workloads
    queue_types,M,memory "16GB"
    queue_types,M,cpu "8"
    queue_types,M,runtime_limit "4:00"
    queue_types,M,priority "normal"

    # Large Queue - Big designs
    queue_types,L,memory "32GB"
    queue_types,L,cpu "16"
    queue_types,L,runtime_limit "8:00"
    queue_types,L,priority "normal"

    # Extra Large Queue - Very big designs
    queue_types,XL,memory "64GB"
    queue_types,XL,cpu "32"
    queue_types,XL,runtime_limit "12:00"
    queue_types,XL,priority "normal"

    # Ultra Queue - Massive designs
    queue_types,ultra,memory "128GB"
    queue_types,ultra,cpu "64"
    queue_types,ultra,runtime_limit "24:00"
    queue_types,ultra,priority "high"
}
```

### Available Queue Types

Configure which queues are available in your environment:

```tcl
# Available queues in your LSF cluster
set lsf(available_queues) [list S M L XL ultra]

# Default queue when no specific recommendation
set lsf(default_queue) "M"
```

### ML Analytics Configuration

```tcl
# Machine Learning Settings
array set lsf {
    # Enable ML-based predictions
    ml_analytics,enable_prediction true

    # Training data requirements
    ml_analytics,minimum_training_samples 50
    ml_analytics,training_interval_hours 24

    # Model configuration
    ml_analytics,memory_prediction_model "random_forest"
    ml_analytics,runtime_prediction_model "gradient_boost"
    ml_analytics,confidence_threshold 0.7

    # Data retention
    ml_analytics,data_retention_days 90
    ml_analytics,max_training_samples 10000
}
```

### Cost Management Settings

```tcl
# Cost Configuration
array set lsf {
    # Cost rates (adjust for your environment)
    cost,cpu_rate_per_hour 0.10
    cost,memory_rate_per_gb_hour 0.05

    # Budget settings
    cost,enable_budget_tracking true
    cost,default_monthly_budget 1000.0
    cost,budget_alert_threshold 0.8
    cost,budget_warning_threshold 0.9

    # Cost optimization
    cost,enable_optimization true
    cost,target_efficiency 0.85
    cost,max_acceptable_waste 0.15
}
```

### Dynamic Queue Management

```tcl
# Dynamic Queue Settings
array set lsf {
    # Dynamic queue creation
    dynamic,enable_dynamic_queues true
    dynamic,max_concurrent_queues 10
    dynamic,queue_lifetime_hours 24
    dynamic,resource_buffer_factor 1.2

    # Queue selection strategy
    dynamic,selection_strategy "ml_optimized"  # options: ml_optimized, cost_optimized, performance_optimized
    dynamic,load_balancing_factor 0.3

    # Cleanup settings
    dynamic,auto_cleanup true
    dynamic,cleanup_interval_minutes 60
}
```

### Integration Settings

```tcl
# Integration Configuration
array set lsf {
    # XTerm integration
    integration,enable_xterm_lsf true
    integration,xterm_fallback_local true

    # Node execution integration
    integration,enable_node_lsf true
    integration,node_fallback_local true

    # Monitoring
    integration,enable_monitoring true
    integration,monitoring_interval_seconds 30

    # Debug settings
    integration,debug_mode false
    integration,log_level "INFO"  # DEBUG, INFO, WARNING, ERROR
}
```

## Project Configuration (`phoenix_config.tcl`)

### Node-Specific LSF Requirements

Define specific LSF requirements for each flow and stage:

```tcl
# SYNTHESIS Flow Requirements
set project(lsf,node_requirements,SYNTH,synthesis,queue) "M"
set project(lsf,node_requirements,SYNTH,synthesis,memory) "16GB"
set project(lsf,node_requirements,SYNTH,synthesis,cpu) "8"
set project(lsf,node_requirements,SYNTH,synthesis,runtime_estimate) "2.0"

set project(lsf,node_requirements,SYNTH,optimization,queue) "L"
set project(lsf,node_requirements,SYNTH,optimization,memory) "24GB"
set project(lsf,node_requirements,SYNTH,optimization,cpu) "12"
set project(lsf,node_requirements,SYNTH,optimization,runtime_estimate) "3.0"

# PLACE & ROUTE Flow Requirements (Most Resource Intensive)
set project(lsf,node_requirements,PNR,floorplan,queue) "M"
set project(lsf,node_requirements,PNR,floorplan,memory) "16GB"
set project(lsf,node_requirements,PNR,floorplan,cpu) "8"
set project(lsf,node_requirements,PNR,floorplan,runtime_estimate) "1.5"

set project(lsf,node_requirements,PNR,placement,queue) "L"
set project(lsf,node_requirements,PNR,placement,memory) "32GB"
set project(lsf,node_requirements,PNR,placement,cpu) "16"
set project(lsf,node_requirements,PNR,placement,runtime_estimate) "4.0"

set project(lsf,node_requirements,PNR,route,queue) "XL"
set project(lsf,node_requirements,PNR,route,memory) "64GB"
set project(lsf,node_requirements,PNR,route,cpu) "32"
set project(lsf,node_requirements,PNR,route,runtime_estimate) "8.0"

set project(lsf,node_requirements,PNR,route_opt,queue) "XL"
set project(lsf,node_requirements,PNR,route_opt,memory) "64GB"
set project(lsf,node_requirements,PNR,route_opt,cpu) "32"
set project(lsf,node_requirements,PNR,route_opt,runtime_estimate) "6.0"

# FLOORPLAN Flow Requirements
set project(lsf,node_requirements,FP,inputs,queue) "S"
set project(lsf,node_requirements,FP,inputs,memory) "8GB"
set project(lsf,node_requirements,FP,inputs,cpu) "4"
set project(lsf,node_requirements,FP,inputs,runtime_estimate) "0.5"

set project(lsf,node_requirements,FP,floorplan,queue) "M"
set project(lsf,node_requirements,FP,floorplan,memory) "16GB"
set project(lsf,node_requirements,FP,floorplan,cpu) "8"
set project(lsf,node_requirements,FP,floorplan,runtime_estimate) "2.0"
```

### Design-Specific Overrides

Override defaults based on design characteristics:

```tcl
# Large design overrides
if {[info exists project(design_size)] && $project(design_size) eq "large"} {
    # Bump up all memory requirements by 50%
    set project(lsf,memory_multiplier) 1.5

    # Use higher-tier queues for large designs
    set project(lsf,node_requirements,SYNTH,synthesis,queue) "L"
    set project(lsf,node_requirements,PNR,route,queue) "ultra"
}

# Technology node specific settings
if {[info exists project(technology_node)] && $project(technology_node) eq "3nm"} {
    # Advanced nodes require more memory
    set project(lsf,memory_multiplier) 2.0
}
```

### Budget Configuration

```tcl
# Budget settings per flow type
set project(lsf,budget,SYNTH,monthly) 500.0
set project(lsf,budget,PNR,monthly) 1500.0
set project(lsf,budget,FP,monthly) 200.0
set project(lsf,budget,overall,monthly) 2500.0

# Alert thresholds
set project(lsf,budget,alert_threshold) 0.8
set project(lsf,budget,warning_threshold) 0.9
set project(lsf,budget,critical_threshold) 0.95

# Cost optimization preferences
set project(lsf,cost_optimization,enable) true
set project(lsf,cost_optimization,strategy) "balanced"  # aggressive, balanced, conservative
set project(lsf,cost_optimization,max_performance_loss) 0.1  # 10% max performance loss for cost savings
```

### ML Model Configuration

```tcl
# ML model preferences for this project
set project(lsf,ml,enable_custom_models) true
set project(lsf,ml,model_update_frequency) "weekly"
set project(lsf,ml,feature_weights,gate_count) 0.3
set project(lsf,ml,feature_weights,hierarchy_depth) 0.2
set project(lsf,ml,feature_weights,net_count) 0.2
set project(lsf,ml,feature_weights,design_size) 0.3

# Training data filters
set project(lsf,ml,training_data_filters,min_gate_count) 10000
set project(lsf,ml,training_data_filters,max_runtime_hours) 24
set project(lsf,ml,training_data_filters,success_rate_threshold) 0.9
```

## Advanced Configuration Options

### Custom Queue Definitions

Add your own queue types:

```tcl
# Custom GPU queue
set lsf(queue_types,gpu,memory) "32GB"
set lsf(queue_types,gpu,cpu) "16"
set lsf(queue_types,gpu,gpu) "4"
set lsf(queue_types,gpu,runtime_limit) "6:00"
set lsf(queue_types,gpu,priority) "high"

# Memory-optimized queue
set lsf(queue_types,mem_opt,memory) "256GB"
set lsf(queue_types,mem_opt,cpu) "32"
set lsf(queue_types,mem_opt,runtime_limit) "48:00"
set lsf(queue_types,mem_opt,priority) "normal"
```

### Site-Specific LSF Settings

```tcl
# Site-specific LSF configuration
set lsf(site,cluster_name) "design_cluster"
set lsf(site,default_project) "physical_design"
set lsf(site,resource_requirements) "-R \"select[type==LINUX64]\""
set lsf(site,job_name_prefix) "cbflow"

# LSF submission options
set lsf(submission,default_options) [list \
    "-P" $lsf(site,default_project) \
    "-R" $lsf(site,resource_requirements) \
]
```

### Database Configuration

```tcl
# ML Analytics Database Settings
set lsf(database,path) "/tmp/cbflow_lsf_analytics.db"
set lsf(database,backup_interval_hours) 24
set lsf(database,max_size_mb) 1000
set lsf(database,auto_vacuum) true

# Data retention policies
set lsf(database,job_data_retention_days) 90
set lsf(database,cost_data_retention_days) 365
set lsf(database,performance_data_retention_days) 180
```

## Environment-Specific Configurations

### Development Environment

```tcl
# Development settings - more permissive
set lsf(environment) "development"
set lsf(cost,enable_budget_tracking) false
set lsf(integration,debug_mode) true
set lsf(dynamic,enable_dynamic_queues) false
```

### Production Environment

```tcl
# Production settings - strict controls
set lsf(environment) "production"
set lsf(cost,enable_budget_tracking) true
set lsf(integration,debug_mode) false
set lsf(dynamic,enable_dynamic_queues) true
set lsf(ml_analytics,enable_prediction) true
```

### Testing Environment

```tcl
# Testing settings - isolated and controlled
set lsf(environment) "testing"
set lsf(integration,enable_xterm_lsf) false
set lsf(integration,enable_node_lsf) false
set lsf(cost,enable_budget_tracking) false
```

## Configuration Validation

### Built-in Validation

The system automatically validates configurations on startup:

```tcl
# Enable configuration validation
set lsf(validation,enable) true
set lsf(validation,strict_mode) true
set lsf(validation,halt_on_error) false
```

### Custom Validation Rules

Add your own validation:

```tcl
proc validate_custom_lsf_config {} {
    global lsf project

    # Ensure all required queues are defined
    set required_queues [list S M L XL]
    foreach queue $required_queues {
        if {![info exists lsf(queue_types,$queue,memory)]} {
            CBFLOW_ERROR "Missing queue definition for $queue" "CONFIG"
            return false
        }
    }

    # Validate budget settings
    if {[info exists project(lsf,budget,overall,monthly)]} {
        set total_budget $project(lsf,budget,overall,monthly)
        if {$total_budget <= 0} {
            CBFLOW_WARNING "Invalid budget amount: $total_budget" "CONFIG"
        }
    }

    return true
}

# Register custom validation
set lsf(validation,custom_proc) "validate_custom_lsf_config"
```

## Configuration Templates

### Template for New Projects

```tcl
# Copy this template to your project config file

# Project-specific LSF settings for [PROJECT_NAME]
set project(name) "PROJECT_NAME"
set project(design_size) "medium"  # small, medium, large, xlarge

# Default LSF settings
set project(lsf,default_queue) "M"
set project(lsf,enable_cost_tracking) true
set project(lsf,enable_ml_optimization) true

# Budget allocation (adjust as needed)
set project(lsf,budget,monthly) 1000.0
set project(lsf,budget,alert_threshold) 0.8

# Node-specific requirements (customize for your flows)
# SYNTH flow
set project(lsf,node_requirements,SYNTH,synthesis,queue) "M"
set project(lsf,node_requirements,SYNTH,synthesis,memory) "16GB"

# PNR flow
set project(lsf,node_requirements,PNR,route,queue) "L"
set project(lsf,node_requirements,PNR,route,memory) "32GB"

# Add more node requirements as needed...
```

## Configuration Best Practices

### 1. Start Conservative
Begin with larger resource allocations and let the ML system optimize down over time.

### 2. Set Realistic Budgets
Base monthly budgets on historical spending patterns, not arbitrary limits.

### 3. Use Design-Specific Overrides
Create different configurations for different design sizes and complexities.

### 4. Enable Gradual Learning
Allow the ML system to collect data for at least 2 weeks before relying on predictions.

### 5. Monitor and Adjust
Regularly review cost reports and efficiency metrics to tune configurations.

## Troubleshooting Configuration Issues

### Common Problems

1. **Queue Not Found**
   ```
   Error: Queue 'XL' not available in LSF cluster
   ```
   Solution: Check `lsf(available_queues)` matches your actual LSF queues.

2. **Budget Alerts Not Working**
   ```
   Warning: Budget tracking disabled
   ```
   Solution: Ensure `cost,enable_budget_tracking` is `true` in config.

3. **ML Predictions Not Available**
   ```
   Info: Using fallback resource prediction
   ```
   Solution: Wait for sufficient training data or check Python dependencies.

### Debug Configuration Loading

```tcl
# Enable configuration debug mode
set lsf(debug,config_loading) true

# This will show detailed config loading information
source "core/config/flow/v1.0.0/lsf_config.tcl"
```

---

This guide covers the comprehensive configuration options available in the CBFlow LSF Management System. For implementation examples and usage patterns, see the other documentation files in this directory.