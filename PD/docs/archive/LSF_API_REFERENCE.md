# CBFlow LSF API Reference

## Overview

This document provides comprehensive API reference for all LSF management functions available in CBFlow. All APIs are organized by namespace for easy navigation.

## Table of Contents

- [LSF Utilities (::lsf::utils)](#lsf-utilities-lsfutils)
- [Dynamic Queues (::lsf::dynamic)](#dynamic-queues-lsfdynamic)
- [Cost Management (::lsf::cost)](#cost-management-lsfcost)
- [Integration Layer (::lsf::integration)](#integration-layer-lsfintegration)
- [Optimizer (::lsf::optimizer)](#optimizer-lsfoptimizer)
- [Data Management (::lsf::data)](#data-management-lsfdata)
- [Monitoring (::lsf::monitor)](#monitoring-lsfmonitor)

---

## LSF Utilities (::lsf::utils)

Core LSF job management and utility functions.

### ::lsf::utils::initialize

Initialize the LSF utilities system.

**Syntax:**
```tcl
::lsf::utils::initialize
```

**Returns:** `boolean` - True if initialization successful

**Example:**
```tcl
if {[::lsf::utils::initialize]} {
    puts "LSF utilities ready"
}
```

### ::lsf::utils::submit_lsf_job

Submit a job to LSF with specified queue and parameters.

**Syntax:**
```tcl
::lsf::utils::submit_lsf_job queue_type job_name command ?options?
```

**Parameters:**
- `queue_type` (string) - Queue type (S, M, L, XL, ultra)
- `job_name` (string) - Name for the LSF job
- `command` (string) - Command to execute
- `options` (dict, optional) - Additional LSF options

**Returns:** `string` - LSF job ID or empty string on failure

**Example:**
```tcl
set job_id [::lsf::utils::submit_lsf_job "L" "synthesis_job" "genus -f run.tcl"]
if {$job_id ne ""} {
    puts "Job submitted with ID: $job_id"
}
```

### ::lsf::utils::get_job_status

Get the current status of an LSF job.

**Syntax:**
```tcl
::lsf::utils::get_job_status job_id
```

**Parameters:**
- `job_id` (string) - LSF job ID

**Returns:** `string` - Job status (PEND, RUN, DONE, EXIT, etc.)

**Example:**
```tcl
set status [::lsf::utils::get_job_status "12345"]
puts "Job status: $status"
```

### ::lsf::utils::cancel_job

Cancel a running or pending LSF job.

**Syntax:**
```tcl
::lsf::utils::cancel_job job_id
```

**Parameters:**
- `job_id` (string) - LSF job ID to cancel

**Returns:** `boolean` - True if cancellation successful

### ::lsf::utils::get_job_info

Get detailed information about an LSF job.

**Syntax:**
```tcl
::lsf::utils::get_job_info job_id
```

**Parameters:**
- `job_id` (string) - LSF job ID

**Returns:** `dict` - Job information including runtime, resources, etc.

**Example:**
```tcl
set job_info [::lsf::utils::get_job_info "12345"]
set runtime [dict get $job_info runtime_seconds]
set memory_used [dict get $job_info max_memory_gb]
```

### ::lsf::utils::wait_for_job

Wait for an LSF job to complete.

**Syntax:**
```tcl
::lsf::utils::wait_for_job job_id ?timeout_seconds?
```

**Parameters:**
- `job_id` (string) - LSF job ID
- `timeout_seconds` (integer, optional) - Maximum wait time (default: 3600)

**Returns:** `string` - Final job status

### ::lsf::utils::launch_lsf_xterm

Launch an XTerm session through LSF.

**Syntax:**
```tcl
::lsf::utils::launch_lsf_xterm queue_type title command ?options?
```

**Parameters:**
- `queue_type` (string) - LSF queue to use
- `title` (string) - XTerm window title
- `command` (string) - Command to run in XTerm
- `options` (dict, optional) - XTerm and LSF options

**Returns:** `string` - LSF job ID

**Example:**
```tcl
set job_id [::lsf::utils::launch_lsf_xterm "M" "Innovus Session" "innovus"]
```

---

## Dynamic Queues (::lsf::dynamic)

Intelligent dynamic queue creation and management.

### ::lsf::dynamic::create_dynamic_queue

Create a dynamic queue based on workload requirements.

**Syntax:**
```tcl
::lsf::dynamic::create_dynamic_queue flow_type stage_name design_characteristics
```

**Parameters:**
- `flow_type` (string) - Flow type (SYNTH, PNR, FP, etc.)
- `stage_name` (string) - Stage name (synthesis, route, etc.)
- `design_characteristics` (dict) - Design properties

**Returns:** `string` - Dynamic queue name or empty string

**Example:**
```tcl
set design_chars [dict create gate_count 500000 design_size "large"]
set queue_name [::lsf::dynamic::create_dynamic_queue "SYNTH" "synthesis" $design_chars]
```

### ::lsf::dynamic::get_heuristic_resource_prediction

Get resource prediction using heuristic rules.

**Syntax:**
```tcl
::lsf::dynamic::get_heuristic_resource_prediction flow_type stage_name design_characteristics
```

**Parameters:**
- `flow_type` (string) - Flow type
- `stage_name` (string) - Stage name
- `design_characteristics` (dict) - Design properties

**Returns:** `dict` - Resource prediction with memory_gb, cpu_count, predicted_queue

**Example:**
```tcl
set design_chars [dict create gate_count 750000 hierarchy_depth 6]
set prediction [::lsf::dynamic::get_heuristic_resource_prediction "PNR" "route" $design_chars]
set memory_needed [dict get $prediction memory_gb]
set queue_rec [dict get $prediction predicted_queue]
```

### ::lsf::dynamic::cleanup_expired_queues

Clean up expired dynamic queues.

**Syntax:**
```tcl
::lsf::dynamic::cleanup_expired_queues
```

**Returns:** `integer` - Number of queues cleaned up

### ::lsf::dynamic::get_dynamic_queue_status

Get status of all dynamic queues.

**Syntax:**
```tcl
::lsf::dynamic::get_dynamic_queue_status
```

**Returns:** `dict` - Status information including total_queues, active_queues, total_usage

---

## Cost Management (::lsf::cost)

Cost tracking, budgeting, and optimization functions.

### ::lsf::cost::initialize

Initialize the cost management system.

**Syntax:**
```tcl
::lsf::cost::initialize
```

**Returns:** `boolean` - True if initialization successful

### ::lsf::cost::calculate_job_cost

Calculate the cost of a job based on resources and runtime.

**Syntax:**
```tcl
::lsf::cost::calculate_job_cost job_data
```

**Parameters:**
- `job_data` (dict) - Job information with memory_gb, cpu_count, runtime_seconds

**Returns:** `dict` - Cost breakdown with memory_cost, cpu_cost, total_cost

**Example:**
```tcl
set job_data [dict create memory_gb 32 cpu_count 16 runtime_seconds 7200]
set cost_breakdown [::lsf::cost::calculate_job_cost $job_data]
set total_cost [dict get $cost_breakdown total_cost]
puts "Job cost: $[format "%.2f" $total_cost]"
```

### ::lsf::cost::track_job_cost

Track cost for a completed job.

**Syntax:**
```tcl
::lsf::cost::track_job_cost job_id job_data
```

**Parameters:**
- `job_id` (string) - Job identifier
- `job_data` (dict) - Job execution data

**Returns:** `void`

### ::lsf::cost::get_cost_report

Generate cost report for specified time period.

**Syntax:**
```tcl
::lsf::cost::get_cost_report ?days?
```

**Parameters:**
- `days` (integer, optional) - Number of days to include (default: 30)

**Returns:** `dict` - Cost report with total_cost, job_count, cost_by_flow, cost_by_queue

**Example:**
```tcl
set report [::lsf::cost::get_cost_report 7]  # Last 7 days
set total_cost [dict get $report total_cost]
set job_count [dict get $report job_count]
puts "7-day cost: $[format "%.2f" $total_cost] for $job_count jobs"
```

### ::lsf::cost::set_budget

Set budget for a flow type.

**Syntax:**
```tcl
::lsf::cost::set_budget flow_type budget_amount ?period?
```

**Parameters:**
- `flow_type` (string) - Flow type (SYNTH, PNR, etc.)
- `budget_amount` (float) - Budget amount in dollars
- `period` (string, optional) - Budget period (default: "monthly")

**Returns:** `void`

**Example:**
```tcl
::lsf::cost::set_budget "PNR" 1500.0 "monthly"
```

### ::lsf::cost::get_budget_status

Get current budget status for a flow type.

**Syntax:**
```tcl
::lsf::cost::get_budget_status flow_type
```

**Parameters:**
- `flow_type` (string) - Flow type

**Returns:** `dict` - Budget status with allocated_budget, current_spend, budget_utilization, status

**Example:**
```tcl
set status [::lsf::cost::get_budget_status "SYNTH"]
set utilization [dict get $status budget_utilization]
if {$utilization > 0.8} {
    puts "Warning: Budget utilization at [format "%.1f" [expr {$utilization * 100}]]%"
}
```

### ::lsf::cost::optimize_resources

Get optimized resource allocation using ML.

**Syntax:**
```tcl
::lsf::cost::optimize_resources flow_type stage_name design_characteristics
```

**Parameters:**
- `flow_type` (string) - Flow type
- `stage_name` (string) - Stage name
- `design_characteristics` (dict) - Design properties

**Returns:** `dict` - Optimization with memory_gb, cpu_count, estimated_cost, confidence

**Example:**
```tcl
set design_chars [dict create gate_count 300000 net_count 150000]
set optimization [::lsf::cost::optimize_resources "SYNTH" "synthesis" $design_chars]
set memory_rec [dict get $optimization memory_gb]
set cost_est [dict get $optimization estimated_cost]
```

### ::lsf::cost::get_cost_optimization_recommendations

Get recommendations for cost optimization.

**Syntax:**
```tcl
::lsf::cost::get_cost_optimization_recommendations
```

**Returns:** `list` - List of recommendation dictionaries

---

## Integration Layer (::lsf::integration)

Seamless integration with CBFlow execution systems.

### ::lsf::integration::initialize

Initialize LSF integration layer.

**Syntax:**
```tcl
::lsf::integration::initialize
```

**Returns:** `boolean` - True if LSF integration enabled

### ::lsf::integration::submit_node_to_lsf

Submit a CBFlow node execution to LSF.

**Syntax:**
```tcl
::lsf::integration::submit_node_to_lsf flow_type stage_name command ?options?
```

**Parameters:**
- `flow_type` (string) - Flow type
- `stage_name` (string) - Stage name
- `command` (string) - Command to execute
- `options` (dict, optional) - Additional options

**Returns:** `string` - LSF job ID

### ::lsf::integration::get_execution_context

Get current execution context for LSF allocation.

**Syntax:**
```tcl
::lsf::integration::get_execution_context
```

**Returns:** `dict` - Context with flow_type, stage_name, working_directory, design_characteristics

### ::lsf::integration::monitor_active_jobs

Monitor and update status of active LSF jobs.

**Syntax:**
```tcl
::lsf::integration::monitor_active_jobs
```

**Returns:** `integer` - Number of active jobs

### ::lsf::integration::get_integration_status

Get current integration status.

**Syntax:**
```tcl
::lsf::integration::get_integration_status
```

**Returns:** `dict` - Status with lsf_enabled, xterm_integration, node_integration, active_jobs_count

**Example:**
```tcl
set status [::lsf::integration::get_integration_status]
if {[dict get $status lsf_enabled]} {
    puts "LSF integration is active"
    puts "Active jobs: [dict get $status active_jobs_count]"
}
```

### ::lsf::integration::enable

Enable LSF integration.

**Syntax:**
```tcl
::lsf::integration::enable
```

**Returns:** `void`

### ::lsf::integration::disable

Disable LSF integration.

**Syntax:**
```tcl
::lsf::integration::disable
```

**Returns:** `void`

### ::lsf::integration::cleanup

Clean up integration resources and cancel active jobs.

**Syntax:**
```tcl
::lsf::integration::cleanup
```

**Returns:** `void`

---

## Optimizer (::lsf::optimizer)

Resource allocation optimization and performance tuning.

### ::lsf::optimizer::optimize_resource_allocation

Perform comprehensive resource allocation optimization.

**Syntax:**
```tcl
::lsf::optimizer::optimize_resource_allocation flow_type stage_name design_characteristics
```

**Parameters:**
- `flow_type` (string) - Flow type
- `stage_name` (string) - Stage name
- `design_characteristics` (dict) - Design properties

**Returns:** `dict` - Optimization result with applied_optimizations, failed_optimizations

### ::lsf::optimizer::determine_optimal_queue

Determine optimal queue based on resource requirements.

**Syntax:**
```tcl
::lsf::optimizer::determine_optimal_queue avg_memory_gb avg_cpu_utilization
```

**Parameters:**
- `avg_memory_gb` (float) - Average memory usage in GB
- `avg_cpu_utilization` (float) - Average CPU utilization (0.0-1.0)

**Returns:** `string` - Recommended queue type

### ::lsf::optimizer::get_optimization_statistics

Get optimization performance statistics.

**Syntax:**
```tcl
::lsf::optimizer::get_optimization_statistics
```

**Returns:** `dict` - Statistics with total_optimizations, successful_optimizations, recent_optimization_rate

---

## Data Management (::lsf::data)

Data persistence and analytics data management.

### ::lsf::data::store_job_data

Store job execution data for analytics.

**Syntax:**
```tcl
::lsf::data::store_job_data job_data
```

**Parameters:**
- `job_data` (dict) - Complete job execution data

**Returns:** `boolean` - True if data stored successfully

### ::lsf::data::get_historical_job_data

Retrieve historical job data for analysis.

**Syntax:**
```tcl
::lsf::data::get_historical_job_data flow_type stage_name ?limit?
```

**Parameters:**
- `flow_type` (string) - Flow type filter
- `stage_name` (string) - Stage name filter
- `limit` (integer, optional) - Maximum records to return (default: 100)

**Returns:** `list` - List of job data dictionaries

### ::lsf::data::get_recent_performance_metrics

Get recent performance metrics.

**Syntax:**
```tcl
::lsf::data::get_recent_performance_metrics ?hours?
```

**Parameters:**
- `hours` (integer, optional) - Hours of data to include (default: 24)

**Returns:** `dict` - Performance metrics

### ::lsf::data::cleanup_old_data

Clean up old data based on retention policies.

**Syntax:**
```tcl
::lsf::data::cleanup_old_data
```

**Returns:** `integer` - Number of records cleaned up

---

## Monitoring (::lsf::monitor)

Real-time monitoring and system health functions.

### ::lsf::monitor::start_monitoring

Start the monitoring system.

**Syntax:**
```tcl
::lsf::monitor::start_monitoring
```

**Returns:** `boolean` - True if monitoring started

### ::lsf::monitor::stop_monitoring

Stop the monitoring system.

**Syntax:**
```tcl
::lsf::monitor::stop_monitoring
```

**Returns:** `boolean` - True if monitoring stopped

### ::lsf::monitor::get_system_metrics

Get current system metrics.

**Syntax:**
```tcl
::lsf::monitor::get_system_metrics
```

**Returns:** `dict` - System metrics including LSF queue status, resource utilization

### ::lsf::monitor::detect_anomalies

Detect anomalies in current job execution.

**Syntax:**
```tcl
::lsf::monitor::detect_anomalies job_data
```

**Parameters:**
- `job_data` (dict) - Job execution data

**Returns:** `list` - List of detected anomalies

---

## Common Data Structures

### Job Data Dictionary

Standard job data structure used throughout the API:

```tcl
set job_data [dict create \
    job_id "12345" \
    flow_type "SYNTH" \
    stage_name "synthesis" \
    queue_type "M" \
    memory_gb 16 \
    cpu_count 8 \
    runtime_seconds 3600 \
    exit_status 0 \
    max_memory_used 14.2 \
    avg_cpu_utilization 0.75 \
    cost_dollars 6.40 \
    design_characteristics [dict create gate_count 500000 design_size "medium"] \
]
```

### Design Characteristics Dictionary

Standard design characteristics structure:

```tcl
set design_characteristics [dict create \
    gate_count 500000 \
    design_size "medium" \
    hierarchy_depth 6 \
    net_count 250000 \
    technology_node "7nm" \
    clock_frequency 1000 \
    power_domains 4 \
]
```

### Cost Report Dictionary

Standard cost report structure:

```tcl
set cost_report [dict create \
    total_cost 125.50 \
    job_count 25 \
    average_cost 5.02 \
    cost_by_flow [dict create SYNTH 45.20 PNR 80.30] \
    cost_by_queue [dict create S 15.50 M 60.00 L 50.00] \
    period_days 30 \
]
```

## Error Handling

All API functions use standard CBFlow error handling:

```tcl
# Functions return meaningful values on success, empty/false on failure
# Check return values and use error utilities for diagnostics

if {[catch {::lsf::utils::submit_lsf_job "M" "test" "echo hello"} job_id]} {
    CBFLOW_ERROR "Failed to submit job: $job_id" "LSF"
} elseif {$job_id eq ""} {
    CBFLOW_WARNING "Job submission returned empty job ID" "LSF"
} else {
    CBFLOW_INFO "Job submitted successfully: $job_id" "LSF"
}
```

## Version Information

- **API Version**: 1.0.0
- **Compatible with**: CBFlow v2.0.0+
- **Last Updated**: 2025-01-08

---

This API reference covers all public functions in the CBFlow LSF Management System. For usage examples and best practices, see the other documentation files in this directory.