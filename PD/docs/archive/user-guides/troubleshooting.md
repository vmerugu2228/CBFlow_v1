# CBFlow Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide helps you diagnose and resolve common issues in CBFlow. It covers environment problems, configuration errors, execution failures, and provides systematic approaches to problem resolution.

## Diagnostic Framework

### Initial Diagnosis Steps

#### 1. Check System Status
```bash
# Check CBFlow environment
make validate_environment

# Verify tool availability
make check_tools

# Check license status
make check_licenses

# Validate current run status
make status
```

#### 2. Examine Logs
```bash
# Check recent error messages
grep -r "ERROR\|FATAL" logs/ | tail -20

# Look for warnings that might indicate problems
grep -r "WARNING\|WARN" logs/ | grep -i "critical\|severe"

# Check tool-specific logs
tail -50 logs/SYNTH/synthesis.log
tail -50 logs/FP/floorplan.log
```

#### 3. Validate Configuration
```bash
# Check configuration consistency
make validate_config

# Verify file paths
make validate_inputs

# Check dependency satisfaction
make check_dependencies
```

## Environment Issues

### Tool Access Problems

#### Problem: Tools Not Found
```bash
# Error message:
# genus: command not found
# innovus: command not found
```

**Diagnosis:**
```bash
# Check tool paths
which genus innovus tempus

# Verify environment variables
echo $GENUS_HOME
echo $INNOVUS_HOME
echo $PATH

# Check .cbflow.env file
cat .cbflow.env
```

**Solutions:**
```bash
# 1. Update tool paths in .cbflow.env
export GENUS_HOME="/path/to/genus/installation"
export PATH="$GENUS_HOME/bin:$PATH"

# 2. Source environment file
source .cbflow.env

# 3. Verify tool access
genus -version
innovus -version

# 4. Update CBFlow environment
make validate_environment
```

#### Problem: License Issues
```bash
# Error message:
# License checkout failed for feature 'genus'
# No license available
```

**Diagnosis:**
```bash
# Check license server
echo $LM_LICENSE_FILE
lmstat -a

# Check specific tool licenses
lmstat -f genus
lmstat -f innovus

# Test license checkout
genus -checkout_license
```

**Solutions:**
```bash
# 1. Fix license server configuration
export LM_LICENSE_FILE="port@license_server"

# 2. Check license server connectivity
telnet license_server port

# 3. Contact license administrator if needed

# 4. Use alternative license server
export LM_LICENSE_FILE="backup_port@backup_server"
```

### File System Issues

#### Problem: Permission Denied
```bash
# Error message:
# Permission denied: cannot create directory
# Cannot write to file
```

**Diagnosis:**
```bash
# Check directory permissions
ls -la
ls -la ../

# Check disk space
df -h .
df -h /tmp

# Check user permissions
id
groups
```

**Solutions:**
```bash
# 1. Fix directory permissions
chmod 755 .
chmod -R u+w work/

# 2. Clean up disk space
make cleanup_temp_files
rm -rf old_run_directories/

# 3. Use alternative location with write access
export CBFLOW_TEMP_DIR="/local/scratch/$USER"
mkdir -p $CBFLOW_TEMP_DIR
```

#### Problem: Disk Space Issues
```bash
# Error message:
# No space left on device
# Disk quota exceeded
```

**Diagnosis:**
```bash
# Check disk usage
df -h .
du -sh *
du -sh work/ logs/ results/

# Check quota limits
quota -u
```

**Solutions:**
```bash
# 1. Clean up temporary files
make cleanup_temp_files
rm -rf work/*/*/temp/

# 2. Compress old logs
gzip logs/*/*/*.log

# 3. Archive old results
tar -czf old_results.tar.gz results/
rm -rf results/old_runs/

# 4. Use alternative storage location
export CBFLOW_WORK_DIR="/large/storage/area"
```

## Configuration Issues

### Missing or Invalid Configuration

#### Problem: Missing Configuration Arrays
```bash
# Error message:
# can't read "flow(design_name)": no such variable
# Configuration array 'synth' not found
```

**Diagnosis:**
```bash
# Check configuration file syntax
tclsh -c "source user_config.tcl; parray flow"

# Validate configuration completeness
make validate_config

# Check for required parameters
grep -n "design_name\|flow_type" user_config.tcl
```

**Solutions:**
```bash
# 1. Add missing configuration
cat >> user_config.tcl << 'EOF'
array set flow {
    design_name "my_design"
    flow_type "SYNTH"
}
EOF

# 2. Fix syntax errors
tclsh -c "source user_config.tcl"  # Check for errors

# 3. Use configuration template
cp ../core/config/templates/user_config_template.tcl user_config.tcl
# Edit template as needed

# 4. Validate fixed configuration
make validate_config
```

#### Problem: Invalid File Paths
```bash
# Error message:
# Input file not found: /path/to/design.v
# Cannot access library file
```

**Diagnosis:**
```bash
# Check file existence
ls -la /path/to/design.v
ls -la /path/to/library.lib

# Check path variables
echo $inputs_spec
grep -n "\.v\|\.lib\|\.sdc" user_config.tcl
```

**Solutions:**
```bash
# 1. Fix file paths in configuration
set inputs_spec {
    rtl "/correct/path/to/design.v"
    sdc "/correct/path/to/constraints.sdc"
    library "/correct/path/to/library.lib"
}

# 2. Use relative paths if appropriate
set inputs_spec {
    rtl "../designs/my_design.v"
    sdc "../constraints/my_design.sdc"
}

# 3. Create symbolic links if needed
ln -s /shared/libraries/process.lib local_library.lib

# 4. Validate input files
make validate_inputs
```

### Configuration Hierarchy Issues

#### Problem: Configuration Override Conflicts
```bash
# Error message:
# Conflicting configuration values
# Unexpected configuration behavior
```

**Diagnosis:**
```bash
# Check configuration precedence
make show_config_hierarchy

# Examine merged configuration
cat setup/consolidated_config.tcl

# Check for multiple definitions
grep -n "design_name" user_config.tcl ../core/config/project/*/v1.0.0/*.tcl
```

**Solutions:**
```bash
# 1. Review configuration hierarchy
# User > Project > Technology > Flow

# 2. Remove conflicting definitions
# Keep only necessary overrides in user_config.tcl

# 3. Use proper configuration level
# Move project-wide settings to project config
# Keep only run-specific settings in user config

# 4. Validate final configuration
make validate_config
make show_final_config
```

## Execution Failures

### Stage Execution Issues

#### Problem: Synthesis Failures
```bash
# Error message:
# Synthesis failed with errors
# Tool exited with non-zero status
```

**Diagnosis:**
```bash
# Check synthesis logs
tail -50 logs/SYNTH/synthesis.log
grep -i "error\|fatal" logs/SYNTH/synthesis.log

# Check tool-specific issues
grep -i "elaboration\|compile\|optimize" logs/SYNTH/synthesis.log

# Verify input files
make validate_inputs
ls -la work/SYNTH/synthesis/inputs/
```

**Solutions:**
```bash
# 1. Fix RTL issues
# Check for syntax errors in RTL
# Verify module hierarchy
# Fix compilation errors

# 2. Adjust synthesis settings
array set synth {
    optimization_effort "low"     # Reduce effort temporarily
    compile_strategy "area"       # Try different strategy
    enable_recovery "true"        # Enable error recovery
}

# 3. Clean and retry
make clean_stage STAGE=synthesis
make synthesis

# 4. Run in debug mode
array set flow {
    debug_mode "true"
    verbose_logging "true"
}
make synthesis
```

#### Problem: Place & Route Failures
```bash
# Error message:
# Placement failed - congestion too high
# Routing incomplete - DRC violations
```

**Diagnosis:**
```bash
# Check P&R logs
tail -100 logs/PNR/place.log
tail -100 logs/PNR/route.log

# Look for specific issues
grep -i "congestion\|drc\|violation" logs/PNR/*.log
grep -i "placement\|routing" logs/PNR/*.log

# Check design statistics
grep -i "utilization\|density" logs/PNR/*.log
```

**Solutions:**
```bash
# 1. Reduce design density
array set fp {
    core_utilization "0.65"       # Reduce from 0.75
}

# 2. Adjust placement settings
array set pnr {
    placement_density "0.70"      # Lower density
    congestion_effort "high"      # Increase effort
}

# 3. Fix floorplan issues
# Redistribute macros
# Add placement blockages
# Improve power planning

# 4. Iterative approach
make clean_stage STAGE=place
make place
# Check results before proceeding
make route
```

### Flat Mode Issues

#### Problem: Flat Mode Restrictions
```bash
# Error message:
# Cannot add individual execution node 'floorplan' in flat mode
# Individual execution nodes are merged in flat mode
```

**Diagnosis:**
```bash
# Check current execution mode
grep "run_type" user_config.tcl
make show_run_mode

# Check what nodes are blocked
make list_blocked_nodes
```

**Solutions:**
```bash
# 1. Switch to regular mode if individual stages needed
array set flow {
    run_type "node"    # Change from "flat"
}
make clean
make setup

# 2. Use merged nodes in flat mode
make add_node NODE_TYPE=floorplan_merged NODE_NAME=floorplan_experiment

# 3. Create branches for experimentation
make create_branch BASE_NODE=floorplan_merged BRANCH_NAME=fp_experiment

# 4. Use data node variants (always allowed)
make add_node NODE_TYPE=inputs NODE_NAME=inputs1
```

### Memory and Resource Issues

#### Problem: Out of Memory
```bash
# Error message:
# Out of memory
# Tool killed due to memory limit
# Malloc failed
```

**Diagnosis:**
```bash
# Check memory usage
top -p $(pgrep -f genus)
ps aux | grep innovus

# Check system memory
free -h
cat /proc/meminfo

# Check CBFlow memory settings
grep -i memory user_config.tcl setup/*.tcl
```

**Solutions:**
```bash
# 1. Increase memory limits
array set flow {
    memory_limit "32GB"    # Increase from 16GB
}

array set synth {
    memory_limit "16GB"    # Tool-specific limit
}

# 2. Optimize memory usage
array set synth {
    memory_optimization "aggressive"
    garbage_collection "frequent"
}

# 3. Use memory-efficient settings
array set pnr {
    incremental_mode "true"
    checkpoint_frequency "stage"
}

# 4. Run on machine with more memory
# Or use distributed execution
```

#### Problem: Execution Timeout
```bash
# Error message:
# Execution timeout exceeded
# Process killed due to timeout
```

**Diagnosis:**
```bash
# Check timeout settings
grep -i timeout user_config.tcl
make show_timeout_settings

# Check execution progress
tail -f logs/SYNTH/synthesis.log
make progress_report
```

**Solutions:**
```bash
# 1. Increase timeout values
array set flow {
    timeout "14400"        # 4 hours instead of 2
}

array set synth {
    timeout,synthesis "7200"  # Stage-specific timeout
}

# 2. Optimize for speed
array set synth {
    optimization_effort "medium"  # Reduce from "high"
    compile_strategy "quick"
}

# 3. Use incremental approach
# Break large designs into smaller pieces
# Use hierarchical flows

# 4. Check for infinite loops
# Monitor log files for repeated messages
# Kill and restart if stuck
```

## Tool-Specific Issues

### Genus (Synthesis) Issues

#### Common Problems and Solutions

**Problem: Elaboration Failures**
```bash
# Check RTL syntax
genus -batch -execute "read_hdl design.v; elaborate"

# Fix common issues:
# - Missing modules
# - Parameter mismatches
# - Syntax errors
```

**Problem: Optimization Failures**
```bash
# Reduce optimization aggressiveness
set_attribute syn_generic_effort low
set_attribute syn_map_effort low

# Check constraints
report_timing_requirements
report_clocks
```

### Innovus (Physical) Issues

#### Common Problems and Solutions

**Problem: Import Failures**
```bash
# Check file formats
file netlist.v
file constraints.sdc

# Verify compatibility
checkDesign -all
```

**Problem: Placement Issues**
```bash
# Check utilization
report_place_utilization

# Adjust settings
setPlaceMode -place_global_max_density 0.7
setPlaceMode -place_detail_legalization_inst_gap 1
```

## Systematic Debugging Approach

### Step-by-Step Debug Process

#### 1. Isolate the Problem
```bash
# Identify failing stage
make status

# Check last successful stage
ls -lt status/*/

# Find exact failure point
grep -n "ERROR\|FATAL" logs/*/*log | tail -10
```

#### 2. Reproduce the Issue
```bash
# Clean and retry
make clean_stage STAGE=synthesis
make synthesis

# Run with debug enabled
array set flow {
    debug_mode "true"
    verbose_logging "true"
}
make synthesis
```

#### 3. Simplify the Problem
```bash
# Use minimal configuration
# Reduce design complexity
# Disable advanced optimizations
# Use default settings

# Test with known good configuration
cp ../working_config.tcl user_config.tcl
make synthesis
```

#### 4. Check Dependencies
```bash
# Verify all dependencies are satisfied
make check_dependencies

# Check input file integrity
make validate_inputs

# Verify environment consistency
make validate_environment
```

#### 5. Collect Debug Information
```bash
# Gather comprehensive debug info
make debug_report

# Save relevant logs
tar -czf debug_info.tar.gz logs/ setup/ status/

# Document the issue
echo "Problem description" > debug_description.txt
echo "Steps to reproduce" >> debug_description.txt
echo "Error messages" >> debug_description.txt
```

## Performance Issues

### Slow Execution

#### Diagnosis
```bash
# Check system resources
top
iostat 1
sar -u 1

# Check CBFlow-specific issues
make performance_report
make resource_usage
```

#### Solutions
```bash
# 1. Optimize parallel execution
array set flow {
    max_jobs "8"           # Increase parallel jobs
    parallel_stages "true"
}

# 2. Use faster storage
export CBFLOW_TEMP_DIR="/fast/local/storage"

# 3. Optimize tool settings
array set synth {
    optimization_effort "medium"  # Reduce from "high"
    incremental_compile "true"
}

# 4. Use flat mode for better performance
array set flow {
    run_type "flat"
}
```

### Disk I/O Issues

#### Diagnosis
```bash
# Check I/O wait time
iostat -x 1

# Check disk usage patterns
iotop

# Check CBFlow disk usage
du -sh work/ logs/ results/
```

#### Solutions
```bash
# 1. Optimize temporary file usage
array set flow {
    cleanup_temp_files "aggressive"
    compress_logs "true"
}

# 2. Use local storage for temporary files
export CBFLOW_TEMP_DIR="/local/scratch"

# 3. Minimize file operations
array set synth {
    checkpoint_frequency "minimal"
    logging_level "WARN"  # Reduce from "INFO"
}
```

## Recovery Procedures

### Data Recovery

#### Corrupted Run Recovery
```bash
# 1. Assess damage
make validate_run_integrity

# 2. Recover from backups
make restore_from_backup BACKUP_DATE=20251007

# 3. Partial recovery
make recover_stage STAGE=synthesis FROM_CHECKPOINT=synthesis_checkpoint_1

# 4. Emergency recovery
make emergency_recovery
```

#### Configuration Recovery
```bash
# 1. Restore configuration from backup
cp setup/user_config.tcl.backup setup/user_config.tcl

# 2. Regenerate configuration
make regenerate_config

# 3. Reset to defaults
make reset_config_to_defaults
```

### Emergency Procedures

#### Complete Reset
```bash
# 1. Stop all processes
make kill_all_processes

# 2. Clean everything
make emergency_clean

# 3. Restart from scratch
make create_run CONFIG=../user_config.tcl
```

#### Partial Reset
```bash
# 1. Reset specific stage
make reset_stage STAGE=synthesis

# 2. Clean and regenerate
make clean_stage STAGE=synthesis
make regenerate_stage STAGE=synthesis
```

## Getting Help

### Internal Resources
```bash
# Check CBFlow documentation
ls ../core/docs/

# View specific guides
cat ../core/docs/flows/SYNTH.md
cat ../core/docs/user-guides/configuration.md

# Check CBFlow version and known issues
make version
cat ../core/docs/KNOWN_ISSUES.md
```

### Debug Information Collection
```bash
# Generate comprehensive debug package
make create_debug_package

# This creates: debug_package_YYYYMMDD_HHMMSS.tar.gz
# containing:
# - All configuration files
# - Recent log files
# - Status information
# - Environment settings
# - System information
```

### Support Information
When seeking help, provide:
1. CBFlow version information
2. Problem description and steps to reproduce
3. Error messages and relevant log excerpts
4. Configuration files (sanitized)
5. System and environment information

---

This troubleshooting guide provides systematic approaches to diagnosing and resolving the most common CBFlow issues. For complex problems, use the step-by-step debugging process and collect comprehensive debug information.