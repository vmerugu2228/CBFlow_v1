# Running CBFlow Flows Guide

## Overview

This guide covers the practical aspects of executing CBFlow flows, from basic single-flow execution to complex multi-flow scenarios. Learn how to run flows efficiently, monitor progress, and handle various execution scenarios.

## Basic Flow Execution

### 1. Creating and Running a Flow

#### Quick Start Example
```bash
# Navigate to workspace
cd CBFlow/PD/workspace

# Create a synthesis run
make create_run CONFIG=../user_config_synth.tcl

# Navigate to the created run directory
cd P0_run_SYNTH_syn

# Execute the complete flow
make synthesis
```

#### Step-by-Step Execution
```bash
# Alternative: Run individual stages
make inputs          # Prepare and validate inputs
make synthesis       # Execute synthesis
make export_data     # Package outputs
make release_data    # Finalize and archive
```

### 2. Understanding Run Creation

#### Automatic Run Naming
CBFlow automatically generates run directory names:
```
Format: P{priority}_run_{FLOW_TYPE}_{node_name}

Examples:
P0_run_SYNTH_syn        # Default synthesis run
P0_run_FP_fp_test       # Floorplan run with custom name
P1_run_PNR_pnr_eco     # ECO P&R run with priority 1
```

#### Custom Run Names
```bash
# Create run with specific name
make create_run CONFIG=../config.tcl NODE_NAME=experiment_1

# Create run with priority
make create_run CONFIG=../config.tcl PRIORITY=1
```

### 3. Flow Types and Their Execution

#### SYNTH Flow (Synthesis)
```bash
# Complete synthesis flow
make synthesis

# Individual stages
make inputs
make synthesis_setup
make synthesis_run
make synthesis_validate
make export_data
make release_data
```

#### FP Flow (Floorplanning)
```bash
# Complete floorplan flow
make flat_flow

# Individual stages
make inputs
make import_design
make floorplan
make powerplan
make post_floorplan
make export_data
make release_data
```

#### PNR Flow (Place & Route)
```bash
# Complete P&R flow (most complex)
make flat_flow

# Key stages
make inputs
make place
make cts            # Clock tree synthesis
make cts_opt        # Post-CTS optimization
make route          # Global and detailed routing
make route_opt      # Post-route optimization
make pro            # Physical optimization
make signoff        # Signoff preparation
make export_data
make release_data
```

## Execution Modes

### Regular Mode (Individual Stages)

#### Characteristics
- Each stage executes independently
- Maximum flexibility and control
- Individual stage debugging
- Custom node creation supported

#### Usage
```bash
# Enable regular mode (default)
# No special configuration needed

# Run stages individually
make inputs
make synthesis_setup
make synthesis_run
make synthesis_validate
```

#### Benefits
- **Fine Control**: Pause between stages for analysis
- **Debugging**: Isolate issues to specific stages
- **Customization**: Add custom nodes and branches
- **Flexibility**: Modify configurations between stages

### Flat Mode (Merged Execution)

#### Characteristics
- Multiple stages merged into single execution
- Optimized performance (20-40% faster)
- Simplified management
- Restricted customization

#### Configuration
```tcl
# Enable flat mode in user configuration
array set flow {
    run_type "flat"
    design_name "my_design"
    flow_type "SYNTH"
}
```

#### Usage
```bash
# In flat mode, merged targets are created
make synthesis        # Runs all synthesis stages in single session
make floorplan_merged # Runs merged floorplan stages
make pnr_merged      # Runs merged P&R stages
```

#### Benefits
- **Performance**: Faster execution due to reduced tool overhead
- **Simplicity**: Single command execution
- **Resource Efficiency**: Lower memory and I/O usage
- **Optimization**: Better optimization across merged stages

## Advanced Execution Scenarios

### 1. Parallel Flow Execution

#### Running Multiple Flows Simultaneously
```bash
# Terminal 1: High-performance synthesis
cd P0_run_SYNTH_high_perf
nohup make synthesis > synthesis.out 2>&1 &

# Terminal 2: Low-power synthesis
cd P1_run_SYNTH_low_power
nohup make synthesis > synthesis.out 2>&1 &

# Terminal 3: Area-optimized synthesis
cd P2_run_SYNTH_area_opt
nohup make synthesis > synthesis.out 2>&1 &

# Monitor all runs
jobs
ps aux | grep tclsh
```

#### Parallel Stage Execution (Same Flow)
```bash
# Some flows support parallel subnode execution
make PARALLEL=true synthesis

# Monitor parallel execution
make ps
tail -f logs/*/synthesis*.log
```

### 2. Incremental Execution

#### Continuing from Checkpoints
```bash
# Resume from last successful stage
make continue

# Resume from specific stage
make resume_from STAGE=synthesis

# Re-run specific stage
make retrace STAGE=synthesis_run
```

#### Selective Re-execution
```bash
# Re-run only failed stages
make retry_failed

# Force re-run of specific stage
make FORCE=1 synthesis_run

# Clean and re-run stage
make clean_stage STAGE=synthesis
make synthesis
```

### 3. Dependency Management

#### Understanding Dependencies
```bash
# View stage dependencies
make show_dependencies

# Check dependency status
make check_dependencies

# Force execution ignoring dependencies
make IGNORE_DEPS=1 synthesis
```

#### Custom Dependencies
```tcl
# Add custom dependencies in configuration
array set custom_deps {
    synthesis {inputs custom_validation}
    custom_validation {inputs}
}
```

## Monitoring and Status

### 1. Real-time Monitoring

#### Status Commands
```bash
# Overall run status
make status

# Detailed status with timing
make status_detailed

# Specific flow status
make status_synthesis
make status_floorplan

# Node-specific status
make node_status NODE=synthesis_run
```

#### Log Monitoring
```bash
# Follow active logs
tail -f logs/SYNTH/synthesis.log

# Monitor multiple logs
tail -f logs/SYNTH/*.log

# Watch for errors across all logs
grep -r "ERROR" logs/ | tail -f

# Monitor progress with timestamps
tail -f logs/SYNTH/synthesis.log | while read line; do
    echo "$(date): $line"
done
```

### 2. Progress Tracking

#### Stamp Files
CBFlow uses stamp files to track completion:
```bash
# Check stamp file status
ls -la status/SYNTH/

# Example stamp files
status/SYNTH/synthesis_setup.stamp
status/SYNTH/synthesis_run.stamp
status/SYNTH/synthesis_validate.stamp
```

#### Progress Reporting
```bash
# Generate progress report
make progress_report

# Check time estimates
make time_estimate

# View resource usage
make resource_usage
```

### 3. Result Validation

#### Automatic Validation
```bash
# Validate current stage results
make validate

# Validate specific stage
make validate_synthesis

# Comprehensive validation
make validate_all
```

#### Quality Checks
```bash
# Check quality metrics
make quality_check

# Generate quality report
make quality_report

# Check against targets
make check_targets
```

## Flow Handoffs and Integration

### 1. Multi-Flow Workflows

#### RTL-to-GDS Flow Sequence
```bash
# 1. Synthesis
make create_run CONFIG=../synth_config.tcl
cd P0_run_SYNTH_syn
make synthesis

# 2. Floorplan (using synthesis outputs)
cd ../
make create_run CONFIG=../fp_config.tcl FLOW_TYPE=FP \
    INPUTS_FROM=P0_run_SYNTH_syn/results/SYNTH
cd P0_run_FP_fp
make flat_flow

# 3. Place & Route (using floorplan outputs)
cd ../
make create_run CONFIG=../pnr_config.tcl FLOW_TYPE=PNR \
    INPUTS_FROM=P0_run_FP_fp/results/FP
cd P0_run_PNR_pnr
make flat_flow

# 4. Physical Verification
cd ../
make create_run CONFIG=../pv_config.tcl FLOW_TYPE=PV \
    INPUTS_FROM=P0_run_PNR_pnr/results/PNR
cd P0_run_PV_pv
make flat_flow
```

#### Automated Flow Chaining
```bash
# Create flow chain script
cat > run_complete_flow.sh << 'EOF'
#!/bin/bash

# Function to check run success
check_run_success() {
    local run_dir=$1
    if [ -f "$run_dir/status/COMPLETE" ]; then
        echo "✓ $run_dir completed successfully"
        return 0
    else
        echo "✗ $run_dir failed"
        return 1
    fi
}

# Synthesis
echo "Starting synthesis..."
make create_run CONFIG=../synth_config.tcl
cd P0_run_SYNTH_syn
make synthesis
check_run_success $(pwd) || exit 1

# Floorplan
echo "Starting floorplan..."
cd ../
make create_run CONFIG=../fp_config.tcl FLOW_TYPE=FP
cd P0_run_FP_fp
make flat_flow
check_run_success $(pwd) || exit 1

# Continue with remaining flows...
EOF

chmod +x run_complete_flow.sh
./run_complete_flow.sh
```

### 2. Data Handoff Validation

#### Input Validation
```bash
# Validate inputs before starting flow
make validate_inputs

# Check file format compatibility
make check_formats

# Verify data integrity
make verify_inputs
```

#### Output Validation
```bash
# Validate outputs after flow completion
make validate_outputs

# Check handoff requirements
make check_handoff

# Generate handoff package
make create_handoff
```

## Performance Optimization

### 1. Resource Management

#### Memory Optimization
```tcl
# Configure memory limits
array set flow {
    memory_limit "16GB"
    swap_usage "minimal"
    gc_frequency "high"
}
```

#### CPU Optimization
```tcl
# Configure parallel execution
array set flow {
    max_jobs "8"
    parallel_stages "true"
    cpu_affinity "optimal"
}
```

#### Disk I/O Optimization
```tcl
# Optimize disk usage
array set flow {
    temp_dir "/fast/local/storage"
    compress_temps "true"
    cleanup_frequency "stage"
}
```

### 2. Tool Optimization

#### Tool Configuration
```tcl
# Optimize tool settings
array set synth {
    tool,args "-batch -no_gui -multi_cpu 4"
    memory_limit "8GB"
    temp_dir "/tmp/genus_$env(USER)"
}
```

#### License Optimization
```bash
# Check license availability
make check_licenses

# Queue job until licenses available
make WAIT_LICENSE=true synthesis

# Use license efficiently
make LICENSE_REUSE=true flat_flow
```

## Error Handling and Recovery

### 1. Error Detection

#### Automatic Error Detection
```bash
# Check for errors in current run
make check_errors

# Analyze error patterns
make error_analysis

# Generate error report
make error_report
```

#### Log Analysis
```bash
# Search for common error patterns
grep -r "ERROR\|FATAL\|Failed" logs/

# Check for warnings that might become errors
grep -r "WARNING\|WARN" logs/ | grep -i "critical\|severe"

# Analyze timing-related issues
grep -r "timing\|slack\|violation" logs/
```

### 2. Recovery Strategies

#### Automatic Recovery
```bash
# Retry failed stage
make retry

# Retry with different settings
make retry_with_config CONFIG=../recovery_config.tcl

# Resume from checkpoint
make resume_checkpoint
```

#### Manual Recovery
```bash
# Clean and restart stage
make clean_stage STAGE=synthesis
make synthesis

# Reset to known good state
make reset_to_stage STAGE=inputs
make continue

# Emergency reset
make emergency_clean
make create_run CONFIG=../config.tcl
```

### 3. Debugging Techniques

#### Enable Debug Mode
```tcl
# Add to user configuration
array set flow {
    debug_mode "true"
    verbose_logging "true"
    keep_temp_files "true"
}
```

#### Interactive Debugging
```bash
# Run in interactive mode
make INTERACTIVE=true synthesis

# Start tool manually for debugging
cd work/SYNTH/synthesis/run
genus -f setup.tcl
```

## Best Practices

### 1. Flow Execution
- **Plan Resource Usage**: Estimate memory and time requirements
- **Monitor Progress**: Use real-time monitoring for long-running flows
- **Validate Inputs**: Always validate inputs before starting
- **Use Flat Mode**: For production runs where performance matters

### 2. Multi-Flow Management
- **Coordinate Dependencies**: Ensure proper handoff between flows
- **Version Control**: Track configurations for reproducibility
- **Resource Scheduling**: Avoid resource conflicts in parallel execution
- **Quality Gates**: Implement quality checks between flows

### 3. Error Prevention
- **Pre-flight Checks**: Validate environment before execution
- **Incremental Validation**: Check results at each stage
- **Backup Strategies**: Maintain recovery points
- **Documentation**: Keep detailed logs of changes and issues

---

This guide provides comprehensive coverage of CBFlow execution scenarios, from simple single-flow runs to complex multi-flow production environments.