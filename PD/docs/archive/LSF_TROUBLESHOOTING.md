# CBFlow LSF Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting procedures for the CBFlow LSF Management System, including common issues, diagnostic procedures, and step-by-step solutions.

## Table of Contents

1. [Quick Diagnosis](#quick-diagnosis)
2. [LSF Integration Issues](#lsf-integration-issues)
3. [Job Submission Problems](#job-submission-problems)
4. [Cost Tracking Issues](#cost-tracking-issues)
5. [ML Analytics Problems](#ml-analytics-problems)
6. [Performance Issues](#performance-issues)
7. [Configuration Problems](#configuration-problems)
8. [Debug Mode and Logging](#debug-mode-and-logging)
9. [Recovery Procedures](#recovery-procedures)

---

## Quick Diagnosis

### System Health Check

Run this comprehensive diagnostic to identify issues:

```tcl
# Quick system health check
proc lsf_quick_diagnosis {} {
    puts "=== CBFlow LSF System Diagnosis ==="

    # 1. Check LSF integration status
    puts "\n1. LSF Integration Status:"
    if {[catch {source "utils/utilities/v1.0.0/lsf_integration.tcl"} error]} {
        puts "   ✗ LSF integration failed to load: $error"
    } else {
        set status [::lsf::integration::get_integration_status]
        puts "   ✓ LSF integration loaded"
        puts "   - LSF enabled: [dict get $status lsf_enabled]"
        puts "   - XTerm integration: [dict get $status xterm_integration]"
        puts "   - Active jobs: [dict get $status active_jobs_count]"
    }

    # 2. Check configuration files
    puts "\n2. Configuration Files:"
    set config_files [list \
        "core/config/flow/v1.0.0/lsf_config.tcl" \
        "core/config/project/phoenix/v1.0.0/phoenix_config.tcl" \
    ]

    foreach config_file $config_files {
        if {[file exists $config_file]} {
            puts "   ✓ $config_file exists"
            if {[catch {source $config_file} error]} {
                puts "   ✗ Failed to load $config_file: $error"
            }
        } else {
            puts "   ✗ $config_file missing"
        }
    }

    # 3. Check LSF cluster connectivity
    puts "\n3. LSF Cluster Connectivity:"
    if {[catch {exec which bsub} bsub_path]} {
        puts "   ✗ LSF commands not found in PATH"
    } else {
        puts "   ✓ LSF commands available: $bsub_path"

        if {[catch {exec bqueues} queue_output]} {
            puts "   ✗ Cannot connect to LSF cluster: $queue_output"
        } else {
            puts "   ✓ LSF cluster accessible"
            set queue_count [llength [split $queue_output "\n"]]
            puts "   - Available queues: [expr {$queue_count - 1}]"
        }
    }

    # 4. Check Python ML dependencies
    puts "\n4. ML Analytics Dependencies:"
    if {[catch {exec python3 -c "import sklearn, pandas, numpy"} ml_check]} {
        puts "   ✗ Python ML dependencies missing: $ml_check"
        puts "   → Install with: pip install scikit-learn pandas numpy"
    } else {
        puts "   ✓ Python ML dependencies available"
    }

    # 5. Check database accessibility
    puts "\n5. Database Status:"
    if {[catch {exec sqlite3 /tmp/cbflow_lsf_analytics.db ".tables"} db_check]} {
        puts "   ✗ Cannot access analytics database: $db_check"
    } else {
        puts "   ✓ Analytics database accessible"
        set table_count [llength [split $db_check "\n"]]
        puts "   - Tables found: $table_count"
    }

    puts "\n=== Diagnosis Complete ==="
}

# Run the diagnosis
lsf_quick_diagnosis
```

### Common Error Patterns

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `LSF integration not available` | No LSF config or cluster unreachable | Check config files and LSF connectivity |
| `can't read "::env(CONFIG_ROOT)"` | Environment not set up | Source CBFlow environment first |
| `Queue 'XL' not available` | Queue doesn't exist in cluster | Update available_queues in config |
| `Failed to load LSF configuration` | Syntax error in config file | Check TCL syntax in lsf_config.tcl |
| `scikit-learn not available` | Python dependencies missing | Install: `pip install scikit-learn` |
| `Failed to submit job` | LSF permissions or resource limits | Check user quotas and permissions |

---

## LSF Integration Issues

### Problem: LSF Integration Not Loading

**Symptoms:**
- "LSF integration not available" message
- XTerm sessions don't use LSF
- No cost tracking

**Diagnostic Steps:**

```tcl
# Step 1: Check if auto-integration loaded
puts "Checking auto-integration status..."
if {[info exists ::auto_initialize_lsf]} {
    puts "Auto-integration variable set to: $::auto_initialize_lsf"
} else {
    puts "Auto-integration variable not set"
}

# Step 2: Manual integration test
puts "\nTesting manual integration..."
if {[catch {
    source "utils/utilities/v1.0.0/lsf_integration.tcl"
    set init_result [::lsf::integration::initialize]
    puts "Manual integration result: $init_result"
} error]} {
    puts "Manual integration failed: $error"
}

# Step 3: Check configuration path resolution
puts "\nChecking configuration paths..."
set config_dirs [list \
    "../../../config/flow/v1.0.0" \
    "../../config/flow/v1.0.0" \
    "../config/flow/v1.0.0" \
    "config/flow/v1.0.0" \
]

foreach config_dir $config_dirs {
    set lsf_config [file join $config_dir "lsf_config.tcl"]
    puts "Checking: $lsf_config - [file exists $lsf_config]"
}
```

**Solutions:**

1. **Missing Configuration:**
   ```bash
   # Verify config file exists
   ls -la core/config/flow/v1.0.0/lsf_config.tcl

   # If missing, copy from template
   cp core/config/flow/v1.0.0/lsf_config.tcl.template core/config/flow/v1.0.0/lsf_config.tcl
   ```

2. **Environment Issues:**
   ```tcl
   # Set up environment properly
   source .cbflow.tcl  # or appropriate environment file

   # Then retry integration
   source "utils/utilities/v1.0.0/lsf_auto_integration.tcl"
   ```

3. **Permissions:**
   ```bash
   # Check file permissions
   chmod 644 core/config/flow/v1.0.0/lsf_config.tcl
   chmod 755 core/utils/utilities/v1.0.0/lsf_*.tcl
   ```

### Problem: XTerm Integration Not Working

**Symptoms:**
- XTerm launches locally instead of through LSF
- No LSF job IDs returned from xterm calls

**Diagnostic Steps:**

```tcl
# Test xterm command interception
puts "Testing xterm integration..."

# Check if exec command was overridden
if {[info commands ::lsf::integration::original_exec] ne ""} {
    puts "✓ exec command successfully overridden"
} else {
    puts "✗ exec command not overridden"
}

# Test xterm command parsing
set test_args [list xterm -title "Test" -e "echo hello"]
set xterm_info [::lsf::integration::parse_xterm_command $test_args]
puts "Parsed xterm command: $xterm_info"

# Check execution context
set context [::lsf::integration::get_execution_context]
puts "Execution context: $context"
```

**Solutions:**

1. **Manual Override Installation:**
   ```tcl
   # Manually install xterm override
   source "utils/utilities/v1.0.0/lsf_integration.tcl"
   ::lsf::integration::override_xterm_execution
   ```

2. **Enable XTerm Integration:**
   ```tcl
   # In lsf_config.tcl
   set lsf(integration,enable_xterm_lsf) true
   set lsf(integration,xterm_fallback_local) true
   ```

---

## Job Submission Problems

### Problem: Jobs Fail to Submit to LSF

**Symptoms:**
- `submit_lsf_job` returns empty string
- LSF error messages about resource requirements
- Jobs stuck in PEND state

**Diagnostic Steps:**

```tcl
# Test basic LSF functionality
proc test_lsf_submission {} {
    puts "Testing LSF job submission..."

    # Test simple command
    if {[catch {exec bsub -q normal -J test_job echo "hello"} submit_output]} {
        puts "✗ Basic LSF submission failed: $submit_output"
        return false
    } else {
        puts "✓ Basic LSF submission successful"
        puts "Output: $submit_output"

        # Extract job ID
        if {[regexp {Job <(\d+)>} $submit_output -> job_id]} {
            puts "Job ID: $job_id"

            # Check job status
            after 2000  # Wait 2 seconds
            if {[catch {exec bjobs $job_id} job_status]} {
                puts "Job status check failed: $job_status"
            } else {
                puts "Job status: $job_status"
            }
        }
        return true
    }
}

test_lsf_submission
```

**Common Solutions:**

1. **Queue Not Available:**
   ```tcl
   # Check available queues
   if {[catch {exec bqueues} queue_list]} {
       puts "Cannot list queues: $queue_list"
   } else {
       puts "Available queues:"
       puts $queue_list
   }

   # Update lsf_config.tcl with correct queue names
   set lsf(available_queues) [list normal short long]  # Use actual queue names
   ```

2. **Resource Requirements Issues:**
   ```tcl
   # Test with minimal resources
   set minimal_job [::lsf::utils::submit_lsf_job "normal" "test_minimal" "echo test" [dict create memory "1GB" cpu "1"]]
   puts "Minimal job result: $minimal_job"
   ```

3. **User Limits Exceeded:**
   ```bash
   # Check user limits
   bhosts
   busers $USER
   bparams -l
   ```

### Problem: Jobs Fail Due to Resource Constraints

**Symptoms:**
- Jobs exit with code 140 (memory limit)
- Jobs exit with code 143 (time limit)
- "Insufficient resources" messages

**Diagnostic Procedure:**

```tcl
proc diagnose_resource_issues {failed_job_id} {
    puts "Diagnosing resource issues for job $failed_job_id..."

    # Get job information
    if {[catch {exec bjobs -l $failed_job_id} job_details]} {
        puts "Cannot get job details: $job_details"
        return
    }

    puts "Job details:"
    puts $job_details

    # Check for specific failure patterns
    if {[string match "*TERM_MEMLIMIT*" $job_details]} {
        puts "✗ Job failed due to memory limit"
        puts "Recommendation: Increase memory allocation or use larger queue"
    }

    if {[string match "*TERM_RUNLIMIT*" $job_details]} {
        puts "✗ Job failed due to runtime limit"
        puts "Recommendation: Increase runtime limit or optimize job"
    }

    if {[string match "*TERM_LOAD*" $job_details]} {
        puts "✗ Job failed due to load limits"
        puts "Recommendation: Check host load limits and job requirements"
    }
}
```

**Solutions:**

1. **Memory Limit Issues:**
   ```tcl
   # Increase memory allocation
   set job_data [dict create \
       memory_gb 64 \
       cpu_count 16 \
       runtime_seconds 14400 \
   ]

   # Use larger queue
   set job_id [::lsf::utils::submit_lsf_job "XL" "memory_intensive" $command]
   ```

2. **Runtime Limit Issues:**
   ```tcl
   # Extend runtime limits in queue configuration
   set lsf(queue_types,L,runtime_limit) "12:00"  # 12 hours instead of 8
   ```

---

## Cost Tracking Issues

### Problem: Cost Calculations Incorrect

**Symptoms:**
- Cost reports show $0.00 or unrealistic values
- Budget alerts not triggering
- Cost per job seems too high/low

**Diagnostic Steps:**

```tcl
proc validate_cost_calculation {} {
    puts "Validating cost calculation..."

    # Test cost calculation with known values
    set test_job [dict create \
        memory_gb 16 \
        cpu_count 8 \
        runtime_seconds 3600 \
    ]

    set cost_result [::lsf::cost::calculate_job_cost $test_job]
    puts "Test job cost calculation:"
    dict for {key value} $cost_result {
        puts "  $key: $[format "%.2f" $value]"
    }

    # Expected: Memory: 16 * 0.05 * 1 = $0.80, CPU: 8 * 0.10 * 1 = $0.80, Total: $1.60
    set expected_total 1.60
    set actual_total [dict get $cost_result total_cost]
    set difference [expr {abs($actual_total - $expected_total)}]

    if {$difference < 0.01} {
        puts "✓ Cost calculation appears correct"
    } else {
        puts "✗ Cost calculation incorrect - Expected: $[format "%.2f" $expected_total], Actual: $[format "%.2f" $actual_total]"
    }

    # Check cost rates
    puts "\nCost rates:"
    puts "  CPU rate: $::lsf(cost,cpu_rate_per_hour) per hour"
    puts "  Memory rate: $::lsf(cost,memory_rate_per_gb_hour) per GB per hour"
}

validate_cost_calculation
```

**Solutions:**

1. **Incorrect Cost Rates:**
   ```tcl
   # Update cost rates in lsf_config.tcl
   set lsf(cost,cpu_rate_per_hour) 0.10      # $0.10 per CPU per hour
   set lsf(cost,memory_rate_per_gb_hour) 0.05  # $0.05 per GB per hour
   ```

2. **Missing Job Data:**
   ```tcl
   # Ensure all required fields are present
   proc track_job_with_validation {job_id job_data} {
       set required_fields [list memory_gb cpu_count runtime_seconds]

       foreach field $required_fields {
           if {![dict exists $job_data $field]} {
               puts "Warning: Missing required field: $field"
               dict set job_data $field 0
           }
       }

       ::lsf::cost::track_job_cost $job_id $job_data
   }
   ```

### Problem: Budget Alerts Not Working

**Diagnostic Steps:**

```tcl
proc debug_budget_alerts {} {
    puts "Debugging budget alerts..."

    # Check if budget tracking is enabled
    if {[info exists ::lsf(cost,enable_budget_tracking)]} {
        puts "Budget tracking enabled: $::lsf(cost,enable_budget_tracking)"
    } else {
        puts "✗ Budget tracking setting not found"
    }

    # Check budget configuration
    set flows [list SYNTH PNR FP]
    foreach flow $flows {
        if {[catch {
            set status [::lsf::cost::get_budget_status $flow]
            puts "$flow budget status:"
            dict for {key value} $status {
                puts "  $key: $value"
            }
        } error]} {
            puts "✗ Failed to get budget status for $flow: $error"
        }
    }

    # Test manual budget alert
    ::lsf::cost::check_budget_alerts "SYNTH"
}

debug_budget_alerts
```

**Solutions:**

1. **Enable Budget Tracking:**
   ```tcl
   # In lsf_config.tcl
   set lsf(cost,enable_budget_tracking) true
   set lsf(cost,budget_alert_threshold) 0.8

   # Restart cost management
   ::lsf::cost::initialize
   ```

2. **Set Budgets:**
   ```tcl
   # Set budgets for all flows
   ::lsf::cost::set_budget "SYNTH" 500.0 "monthly"
   ::lsf::cost::set_budget "PNR" 1500.0 "monthly"
   ::lsf::cost::set_budget "FP" 200.0 "monthly"
   ```

---

## ML Analytics Problems

### Problem: ML Predictions Not Available

**Symptoms:**
- "Using fallback resource prediction" messages
- Confidence scores always low
- No ML-based optimization

**Diagnostic Steps:**

```tcl
proc debug_ml_analytics {} {
    puts "Debugging ML analytics..."

    # Check Python availability
    if {[catch {exec python3 --version} python_version]} {
        puts "✗ Python3 not available: $python_version"
    } else {
        puts "✓ Python3 available: $python_version"
    }

    # Check ML dependencies
    set ml_modules [list scikit-learn pandas numpy]
    foreach module $ml_modules {
        if {[catch {exec python3 -c "import $module; print('$module OK')"} module_check]} {
            puts "✗ $module not available: $module_check"
        } else {
            puts "✓ $module_check"
        }
    }

    # Check ML script
    set ml_script "core/utils/ml_analytics/v1.0.0/lsf_ml_analytics.py"
    if {[file exists $ml_script]} {
        puts "✓ ML script exists: $ml_script"

        # Test script execution
        if {[catch {exec python3 $ml_script --help} help_output]} {
            puts "✗ ML script execution failed: $help_output"
        } else {
            puts "✓ ML script executable"
        }
    } else {
        puts "✗ ML script missing: $ml_script"
    }

    # Check training data
    if {[catch {::lsf::data::get_historical_job_data "" "" 10} training_data]} {
        puts "✗ Cannot access training data: $training_data"
    } else {
        set data_count [llength $training_data]
        puts "✓ Training data available: $data_count records"

        if {$data_count < 50} {
            puts "⚠ Insufficient training data for ML models"
        }
    }
}

debug_ml_analytics
```

**Solutions:**

1. **Install ML Dependencies:**
   ```bash
   # Install required Python packages
   pip3 install scikit-learn pandas numpy sqlite3

   # Verify installation
   python3 -c "import sklearn; print('sklearn version:', sklearn.__version__)"
   ```

2. **Generate Training Data:**
   ```tcl
   # Create some sample training data
   proc generate_sample_training_data {} {
       for {set i 0} {$i < 100} {incr i} {
           set job_data [dict create \
               job_id "sample_$i" \
               flow_type [lindex [list SYNTH PNR FP] [expr {$i % 3}]] \
               stage_name [lindex [list synthesis route floorplan] [expr {$i % 3}]] \
               memory_gb [expr {8 + ($i % 4) * 8}] \
               cpu_count [expr {4 + ($i % 3) * 4}] \
               runtime_seconds [expr {1800 + ($i % 10) * 600}] \
               exit_status 0 \
               design_characteristics [dict create \
                   gate_count [expr {100000 + ($i % 5) * 200000}] \
                   design_size [lindex [list small medium large] [expr {$i % 3}]] \
               ] \
           ]

           ::lsf::data::store_job_data $job_data
       }
   }

   generate_sample_training_data
   ```

### Problem: Model Training Fails

**Diagnostic Steps:**

```tcl
proc debug_model_training {} {
    puts "Debugging ML model training..."

    # Check if advanced ML is enabled
    set ml_script "core/utils/ml_analytics/v1.0.0/lsf_advanced_ml.py"

    if {[catch {exec python3 $ml_script train_models} training_output]} {
        puts "✗ Model training failed:"
        puts $training_output
    } else {
        puts "✓ Model training output:"
        puts $training_output
    }

    # Check model files
    set model_dir "/tmp/cbflow_ml_models"
    if {[file exists $model_dir]} {
        puts "✓ Model directory exists"
        set model_files [glob -nocomplain "$model_dir/*.pkl"]
        puts "Model files found: [llength $model_files]"
        foreach model_file $model_files {
            puts "  [file tail $model_file]"
        }
    } else {
        puts "✗ Model directory missing: $model_dir"
    }
}

debug_model_training
```

**Solutions:**

1. **Fix Training Data Issues:**
   ```tcl
   # Clean and validate training data
   proc clean_training_data {} {
       set raw_data [::lsf::data::get_historical_job_data "" "" 1000]
       set clean_data [list]

       foreach job $raw_data {
           # Validate required fields
           if {[dict exists $job runtime_seconds] &&
               [dict exists $job memory_gb] &&
               [dict exists $job exit_status] &&
               [dict get $job exit_status] == 0 &&
               [dict get $job runtime_seconds] > 60} {
               lappend clean_data $job
           }
       }

       puts "Cleaned data: [llength $clean_data] of [llength $raw_data] records"
       return $clean_data
   }
   ```

---

## Performance Issues

### Problem: Slow Job Submission

**Diagnostic Steps:**

```tcl
proc benchmark_job_submission {} {
    puts "Benchmarking job submission performance..."

    # Time LSF job submission
    set start_time [clock milliseconds]
    set job_id [::lsf::utils::submit_lsf_job "S" "benchmark_test" "echo test"]
    set end_time [clock milliseconds]

    set submission_time [expr {$end_time - $start_time}]
    puts "Job submission time: ${submission_time}ms"

    if {$submission_time > 5000} {
        puts "⚠ Slow job submission (>5s)"
    } else {
        puts "✓ Job submission performance acceptable"
    }

    # Clean up test job
    if {$job_id ne ""} {
        ::lsf::utils::cancel_job $job_id
    }
}

benchmark_job_submission
```

**Solutions:**

1. **Optimize LSF Configuration:**
   ```tcl
   # Reduce LSF overhead
   set lsf(submission,reduce_overhead) true
   set lsf(submission,batch_submissions) true
   ```

2. **Check Network Connectivity:**
   ```bash
   # Test LSF cluster connectivity
   ping -c 3 lsf-master-node
   traceroute lsf-master-node
   ```

### Problem: High Resource Waste

**Diagnostic Steps:**

```tcl
proc analyze_resource_waste {} {
    puts "Analyzing resource waste..."

    set recent_jobs [::lsf::data::get_historical_job_data "" "" 100]
    set waste_analysis [dict create total_jobs 0 high_waste_jobs 0]

    foreach job $recent_jobs {
        dict incr waste_analysis total_jobs

        set requested_memory [dict_get_default $job requested_memory_gb 0]
        set actual_memory [dict_get_default $job max_memory_used 0]
        set requested_cpu [dict_get_default $job requested_cpu 0]
        set actual_cpu [dict_get_default $job avg_cpu_utilization 0.0]

        if {$requested_memory > 0 && $actual_memory > 0} {
            set memory_waste [expr {1.0 - ($actual_memory / $requested_memory)}]
            if {$memory_waste > 0.5} {  # >50% waste
                dict incr waste_analysis high_waste_jobs
                puts "High memory waste job [dict get $job job_id]: [format "%.1f" [expr {$memory_waste * 100}]]%"
            }
        }

        if {$actual_cpu < 0.3} {  # <30% CPU utilization
            puts "Low CPU utilization job [dict get $job job_id]: [format "%.1f" [expr {$actual_cpu * 100}]]%"
        }
    }

    set waste_rate [expr {double([dict get $waste_analysis high_waste_jobs]) / [dict get $waste_analysis total_jobs]}]
    puts "High waste rate: [format "%.1f" [expr {$waste_rate * 100}]]%"
}

analyze_resource_waste
```

---

## Debug Mode and Logging

### Enable Comprehensive Debug Mode

```tcl
# Enable debug mode for all LSF components
proc enable_debug_mode {} {
    # Environment variable
    set ::env(CBFLOW_LSF_DEBUG) 1

    # LSF configuration debug
    if {[info exists ::lsf]} {
        set ::lsf(debug,config_loading) true
        set ::lsf(debug,job_submission) true
        set ::lsf(debug,cost_calculation) true
        set ::lsf(debug,ml_analytics) true
    }

    # Integration debug
    if {[namespace exists ::lsf::integration]} {
        set ::lsf::integration::config(debug_mode) true
    }

    puts "Debug mode enabled for all LSF components"
}

enable_debug_mode
```

### Detailed Logging

```tcl
# Set up detailed logging
proc setup_detailed_logging {} {
    set log_file "/tmp/cbflow_lsf_debug.log"
    set log_fp [open $log_file "a"]

    # Override error handling to include more details
    proc CBFLOW_DEBUG_LOG {level message component} {
        set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
        set log_entry "$timestamp \[$level\] \[$component\] $message"

        puts $::log_fp $log_entry
        flush $::log_fp
        puts $log_entry
    }

    # Redirect all error functions to debug log
    rename CBFLOW_INFO CBFLOW_INFO_ORIG
    rename CBFLOW_WARNING CBFLOW_WARNING_ORIG
    rename CBFLOW_ERROR CBFLOW_ERROR_ORIG

    proc CBFLOW_INFO {message component} {
        CBFLOW_DEBUG_LOG "INFO" $message $component
        CBFLOW_INFO_ORIG $message $component
    }

    proc CBFLOW_WARNING {message component} {
        CBFLOW_DEBUG_LOG "WARNING" $message $component
        CBFLOW_WARNING_ORIG $message $component
    }

    proc CBFLOW_ERROR {message component} {
        CBFLOW_DEBUG_LOG "ERROR" $message $component
        CBFLOW_ERROR_ORIG $message $component
    }

    puts "Detailed logging enabled to: $log_file"
}

setup_detailed_logging
```

---

## Recovery Procedures

### System Recovery After Failure

```tcl
proc recover_lsf_system {} {
    puts "Starting LSF system recovery..."

    # 1. Stop all LSF monitoring
    if {[namespace exists ::lsf::monitor]} {
        ::lsf::monitor::stop_monitoring
    }

    # 2. Cancel all active jobs
    if {[namespace exists ::lsf::integration]} {
        ::lsf::integration::cleanup
    }

    # 3. Backup current state
    backup_lsf_state

    # 4. Reset configurations
    reset_lsf_configurations

    # 5. Reinitialize system
    source "utils/utilities/v1.0.0/lsf_auto_integration.tcl"

    # 6. Verify recovery
    if {[lsf_quick_diagnosis]} {
        puts "✓ LSF system recovery successful"
    } else {
        puts "✗ LSF system recovery failed - manual intervention required"
    }
}

proc backup_lsf_state {} {
    set backup_dir "/tmp/cbflow_lsf_backup_[clock seconds]"
    file mkdir $backup_dir

    # Backup database
    if {[file exists "/tmp/cbflow_lsf_analytics.db"]} {
        file copy "/tmp/cbflow_lsf_analytics.db" "$backup_dir/"
    }

    # Backup ML models
    if {[file exists "/tmp/cbflow_ml_models"]} {
        file copy "/tmp/cbflow_ml_models" "$backup_dir/"
    }

    puts "LSF state backed up to: $backup_dir"
}

proc reset_lsf_configurations () {
    # Clear all LSF namespace variables
    foreach ns [namespace children :: ::lsf::*] {
        namespace delete $ns
    }

    # Clear global arrays
    if {[info exists ::lsf]} {
        unset ::lsf
    }

    # Reload configurations
    source "core/config/flow/v1.0.0/lsf_config.tcl"
    source "core/config/project/phoenix/v1.0.0/phoenix_config.tcl"

    puts "LSF configurations reset"
}
```

### Database Recovery

```tcl
proc recover_lsf_database {} {
    set db_path "/tmp/cbflow_lsf_analytics.db"
    set backup_path "${db_path}.backup"

    # Create backup if database exists
    if {[file exists $db_path]} {
        file copy $db_path $backup_path
        puts "Database backed up to: $backup_path"
    }

    # Test database integrity
    if {[catch {exec sqlite3 $db_path "PRAGMA integrity_check;"} integrity_result]} {
        puts "Database integrity check failed: $integrity_result"

        # Attempt repair
        puts "Attempting database repair..."
        if {[catch {exec sqlite3 $db_path ".dump" | sqlite3 "${db_path}.repaired"} repair_result]} {
            puts "Database repair failed: $repair_result"

            # Create new database
            file delete -force $db_path
            source "utils/utilities/v1.0.0/lsf_data_manager.tcl"
            ::lsf::data::initialize
            puts "New database created"
        } else {
            file rename "${db_path}.repaired" $db_path
            puts "Database repaired successfully"
        }
    } else {
        puts "Database integrity check passed: $integrity_result"
    }
}
```

---

This troubleshooting guide covers the most common issues encountered with the CBFlow LSF Management System. For additional support, enable debug mode and examine the detailed logs to identify specific failure points.