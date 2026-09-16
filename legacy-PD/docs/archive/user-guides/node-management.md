# CBFlow Node Management Guide

## Overview

CBFlow's node management system provides powerful capabilities for creating, managing, and organizing execution nodes and branches. This guide explains how to effectively use node management for flexible flow execution, experimentation, and parallel development workflows.

## Understanding Nodes

### Node Types

#### Data Nodes
Data nodes handle input/output processing without tool execution:
- **`inputs`** - Input data preparation and validation
- **`export_data`** - Result packaging and export
- **`release_data`** - Final archival and release

#### Execution Nodes
Execution nodes perform actual tool-based processing:
- **`synthesis`** - Logic synthesis
- **`import_design`** - Design import for physical flows
- **`floorplan`** - Physical floorplanning
- **`place`** - Standard cell placement
- **`route`** - Global and detailed routing
- And many more...

#### Merged Nodes (Flat Mode)
Merged nodes combine multiple execution stages:
- **`synthesis_merged`** - All synthesis stages
- **`floorplan_merged`** - All floorplan stages
- **`pnr_merged`** - All P&R stages

### Node Naming Conventions

#### Base Nodes
```
Format: {stage_name}
Examples: synthesis, floorplan, place, route
```

#### Variant Nodes
```
Format: {stage_name}{variant_number}
Examples: synthesis1, synthesis2, floorplan1, place_experiment
```

#### Custom Nodes
```
Format: {stage_name}_{custom_name}
Examples: synthesis_low_power, place_high_density, route_timing_driven
```

## Node Management Commands

### Basic Node Operations

#### Listing Nodes
```bash
# List all available nodes in current flow
make list_nodes

# List nodes with status
make node_status

# List specific flow nodes
make list_flow_nodes FLOW_TYPE=PNR

# Show node dependencies
make show_dependencies
```

#### Creating Nodes
```bash
# Create execution node variant
make add_node NODE_TYPE=synthesis NODE_NAME=synthesis1

# Create custom named node
make add_node NODE_TYPE=place NODE_NAME=place_experiment

# Create node with specific configuration
make add_node NODE_TYPE=synthesis NODE_NAME=synthesis_low_power \
    CONFIG=../low_power_config.tcl
```

#### Deleting Nodes
```bash
# Delete specific node
make delete_node NODE=synthesis1

# Delete node and cleanup files
make delete_node NODE=place_experiment CLEANUP=true

# Force delete (ignore dependencies)
make delete_node NODE=synthesis2 FORCE=true
```

### Advanced Node Operations

#### Node Dependencies
```bash
# Show node dependency tree
make show_dependency_tree

# Check specific node dependencies
make check_dependencies NODE=route

# Validate dependency satisfaction
make validate_dependencies
```

#### Node Status Management
```bash
# Check individual node status
make node_status NODE=synthesis

# Reset node status
make reset_node_status NODE=synthesis1

# Mark node as complete (advanced use)
make mark_complete NODE=synthesis FORCE=true
```

## Branch Management

### Understanding Branches

Branches allow parallel exploration of different implementation strategies from a common base node.

#### Branch Concepts
- **Base Node**: The starting point for branch creation
- **Branch Node**: A variant created from the base node
- **Branch Independence**: Branches don't affect each other
- **Merge Capability**: Branches can be compared and merged

### Creating Branches

#### Basic Branch Creation
```bash
# Create branch from synthesis node
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_area_opt

# Create branch with custom settings
make create_branch BASE_NODE=place BRANCH_NAME=place_timing \
    CONFIG=../timing_config.tcl

# Create multiple branches for experimentation
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_power
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_speed
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_area
```

#### Advanced Branch Creation
```bash
# Create branch with inheritance
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_eco \
    INHERIT_CONFIG=true

# Create branch from specific checkpoint
make create_branch BASE_NODE=place BRANCH_NAME=place_recovery \
    FROM_CHECKPOINT=place_checkpoint_1

# Create branch with custom working directory
make create_branch BASE_NODE=route BRANCH_NAME=route_experiment \
    WORK_DIR=experiments/route_test
```

### Managing Branches

#### Branch Operations
```bash
# List all branches
make list_branches

# Show branch tree structure
make show_branch_tree

# Compare branches
make compare_branches BRANCH1=synthesis_power BRANCH2=synthesis_speed

# Merge branch results
make merge_branch SOURCE=synthesis_area TARGET=synthesis
```

#### Branch Status
```bash
# Check branch status
make branch_status BRANCH=synthesis_power

# Show branch differences from base
make branch_diff BRANCH=synthesis_area

# Generate branch report
make branch_report BRANCH=synthesis_power
```

### Branch Workflows

#### Parallel Experimentation
```bash
# Setup: Create base synthesis run
make create_run CONFIG=../base_config.tcl
cd P0_run_SYNTH_syn
make inputs  # Prepare inputs

# Create experimental branches
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_high_effort
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_low_power
make create_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_area_opt

# Configure each branch differently
# synthesis_high_effort - maximum optimization
echo 'array set synth {optimization_effort "maximum"}' > \
    work/SYNTH/synthesis_high_effort/config_override.tcl

# synthesis_low_power - power optimization
echo 'array set synth {optimization_focus "power"}' > \
    work/SYNTH/synthesis_low_power/config_override.tcl

# synthesis_area_opt - area optimization
echo 'array set synth {optimization_focus "area"}' > \
    work/SYNTH/synthesis_area_opt/config_override.tcl

# Execute branches in parallel
make run_node NODE=synthesis_high_effort &
make run_node NODE=synthesis_low_power &
make run_node NODE=synthesis_area_opt &

# Wait for completion and compare
wait
make compare_all_branches
```

#### ECO (Engineering Change Order) Workflow
```bash
# Create ECO branch from existing implementation
make create_branch BASE_NODE=route BRANCH_NAME=route_eco

# Apply ECO changes
cd work/PNR/route_eco/
# ... apply ECO netlist changes ...

# Run ECO implementation
make run_node NODE=route_eco

# Compare ECO vs original
make compare_branches BRANCH1=route BRANCH2=route_eco

# If ECO is successful, merge back
make merge_branch SOURCE=route_eco TARGET=route
```

#### A/B Testing Workflow
```bash
# Create A/B test branches
make create_branch BASE_NODE=place BRANCH_NAME=place_strategy_a
make create_branch BASE_NODE=place BRANCH_NAME=place_strategy_b

# Configure different strategies
# Strategy A: High utilization
echo 'array set pnr {placement_density "0.85"}' > \
    work/PNR/place_strategy_a/config_override.tcl

# Strategy B: Lower utilization, better timing
echo 'array set pnr {placement_density "0.70"}' > \
    work/PNR/place_strategy_b/config_override.tcl

# Execute both strategies
make run_node NODE=place_strategy_a
make run_node NODE=place_strategy_b

# Analyze results
make compare_branches BRANCH1=place_strategy_a BRANCH2=place_strategy_b
make generate_comparison_report BRANCHES="place_strategy_a place_strategy_b"
```

## Flat Mode Restrictions

### Understanding Flat Mode Limitations

In flat mode, individual execution nodes are blocked to maintain the merged execution model.

#### Blocked Operations
```bash
# These commands will fail in flat mode:
make add_node NODE_TYPE=import_design  # ❌ Individual execution node
make add_node NODE_TYPE=floorplan      # ❌ Individual execution node
make add_node NODE_TYPE=powerplan      # ❌ Individual execution node

# Error message:
# ❌ In flat mode, individual execution nodes are not allowed
# ℹ Individual execution nodes are merged into a single execution node in flat mode
```

#### Allowed Operations
```bash
# These commands work in flat mode:
make add_node NODE_TYPE=inputs         # ✅ Data node
make add_node NODE_TYPE=export_data    # ✅ Data node
make add_node NODE_TYPE=floorplan_merged  # ✅ Merged execution node

# Variants are also allowed:
make add_node NODE_TYPE=inputs NODE_NAME=inputs1          # ✅ Data variant
make add_node NODE_TYPE=export_data NODE_NAME=export_v2   # ✅ Data variant
```

### Working with Flat Mode Restrictions

#### Alternative Approaches
```bash
# Instead of creating individual stage variants, use merged node variants
make add_node NODE_TYPE=floorplan_merged NODE_NAME=floorplan_experiment

# Create branches for experimentation
make create_branch BASE_NODE=floorplan_merged BRANCH_NAME=fp_high_util
make create_branch BASE_NODE=floorplan_merged BRANCH_NAME=fp_low_power
```

#### Switching Between Modes
```bash
# To use individual stages, switch to regular mode
# Edit user_config.tcl:
# array set flow {
#     run_type "node"  # Changed from "flat"
# }

# Regenerate makefile
make clean
make setup

# Now individual stages are available
make add_node NODE_TYPE=floorplan NODE_NAME=floorplan1
```

## Node Configuration

### Per-Node Configuration

#### Node-Specific Config Files
```bash
# Each node can have its own configuration
work/SYNTH/synthesis/config_override.tcl
work/SYNTH/synthesis1/config_override.tcl
work/FP/floorplan_experiment/config_override.tcl
```

#### Configuration Inheritance
```tcl
# Node inherits from run configuration by default
# Override specific settings per node

# work/SYNTH/synthesis_low_power/config_override.tcl
array set synth {
    optimization_focus "power"
    clock_gating "aggressive"
    power_optimization "true"
}

# Override project settings for this node
array set project {
    clock_period "2.0"  # Slower for power savings
}
```

### Dynamic Configuration

#### Runtime Configuration Updates
```bash
# Update node configuration
make update_node_config NODE=synthesis1 CONFIG=../new_config.tcl

# Apply configuration changes
make refresh_node_config NODE=synthesis1

# Validate configuration
make validate_node_config NODE=synthesis1
```

#### Conditional Configuration
```tcl
# Conditional settings based on node name
if {[info exists node_name] && $node_name eq "synthesis_low_power"} {
    array set synth {
        optimization_focus "power"
        power_gating "true"
    }
} elseif {[info exists node_name] && $node_name eq "synthesis_high_perf"} {
    array set synth {
        optimization_focus "timing"
        compile_effort "maximum"
    }
}
```

## Node Execution

### Individual Node Execution

#### Running Specific Nodes
```bash
# Run specific node
make run_node NODE=synthesis1

# Run node with custom timeout
make run_node NODE=place_experiment TIMEOUT=7200

# Run node in background
make run_node NODE=route_timing &

# Run node with specific configuration
make run_node NODE=synthesis_power CONFIG=../power_config.tcl
```

#### Parallel Node Execution
```bash
# Run multiple nodes in parallel
make run_node NODE=synthesis1 &
make run_node NODE=synthesis2 &
make run_node NODE=synthesis3 &

# Wait for all to complete
wait

# Check results
make node_status
make compare_all_results
```

### Dependency-Aware Execution

#### Automatic Dependency Resolution
```bash
# Run node with dependencies
make run_with_deps NODE=route

# This automatically runs:
# 1. inputs (if not complete)
# 2. place (if not complete)
# 3. cts (if not complete)
# 4. route (the requested node)
```

#### Custom Dependency Chains
```bash
# Define custom dependency for experimental node
make set_node_deps NODE=synthesis_experiment DEPS="inputs custom_setup"

# Run with custom dependencies
make run_with_deps NODE=synthesis_experiment
```

## Node Analysis and Reporting

### Result Comparison

#### Basic Comparison
```bash
# Compare two synthesis nodes
make compare_nodes NODE1=synthesis NODE2=synthesis1

# Compare multiple nodes
make compare_multiple_nodes NODES="synthesis synthesis1 synthesis2"

# Generate comparison report
make comparison_report NODES="synthesis synthesis1" OUTPUT=comparison.html
```

#### Detailed Analysis
```bash
# Timing comparison
make compare_timing NODES="synthesis synthesis1"

# Area comparison
make compare_area NODES="place1 place2"

# Power comparison
make compare_power NODES="synthesis_power synthesis_speed"

# QoR (Quality of Results) comparison
make compare_qor NODES="synthesis synthesis1 synthesis2"
```

### Reporting and Documentation

#### Node Reports
```bash
# Generate node summary report
make node_report NODE=synthesis1

# Generate detailed node report
make detailed_node_report NODE=place_experiment

# Generate branch comparison report
make branch_report BRANCH=synthesis_low_power
```

#### Flow Reports
```bash
# Generate flow-wide node report
make flow_node_report

# Generate execution timeline
make execution_timeline

# Generate resource usage report
make resource_report
```

## Best Practices

### Node Management Strategy
1. **Use Descriptive Names**: Choose clear, descriptive node names
2. **Document Experiments**: Maintain documentation for experimental nodes
3. **Clean Up Regularly**: Remove obsolete nodes and branches
4. **Monitor Resources**: Track disk space and computation resources

### Branch Management Strategy
1. **Plan Branch Structure**: Design branch hierarchy before creation
2. **Limit Branch Depth**: Avoid deep branch hierarchies
3. **Regular Comparison**: Compare branches frequently during development
4. **Merge Successfully**: Merge successful experiments back to main line

### Configuration Management
1. **Version Control**: Track node configurations in version control
2. **Standardize Overrides**: Use consistent configuration override patterns
3. **Validate Changes**: Test configuration changes thoroughly
4. **Document Decisions**: Record rationale for configuration choices

### Performance Optimization
1. **Parallel Execution**: Use parallel node execution when possible
2. **Resource Planning**: Plan resource allocation for multiple nodes
3. **Dependency Optimization**: Minimize unnecessary dependencies
4. **Cleanup Strategy**: Implement regular cleanup of temporary files

## Troubleshooting

### Common Issues

#### Node Creation Failures
```bash
# Check if node type is valid for current flow
make validate_node_type NODE_TYPE=synthesis FLOW_TYPE=SYNTH

# Check flat mode restrictions
make check_flat_mode_restrictions NODE_TYPE=floorplan

# Verify node naming conflicts
make check_node_name_conflict NODE_NAME=synthesis1
```

#### Branch Management Issues
```bash
# Check branch base node exists
make verify_base_node BASE_NODE=synthesis

# Validate branch naming
make validate_branch_name BRANCH_NAME=synthesis_experiment

# Check branch dependencies
make check_branch_deps BRANCH=synthesis1
```

#### Execution Issues
```bash
# Debug node execution failure
make debug_node_failure NODE=synthesis1

# Check node dependencies
make validate_node_deps NODE=route

# Verify node configuration
make validate_node_config NODE=synthesis_experiment
```

### Recovery Procedures

#### Node Recovery
```bash
# Reset failed node
make reset_node NODE=synthesis1

# Recreate corrupted node
make recreate_node NODE=place_experiment

# Emergency node cleanup
make emergency_node_cleanup NODE=synthesis1
```

#### Branch Recovery
```bash
# Reset branch to base state
make reset_branch BRANCH=synthesis_area

# Recreate branch from base
make recreate_branch BASE_NODE=synthesis BRANCH_NAME=synthesis_area

# Emergency branch cleanup
make emergency_branch_cleanup BRANCH=synthesis_experiment
```

---

CBFlow's node management system provides powerful capabilities for flexible flow execution, enabling sophisticated experimentation and parallel development workflows while maintaining clear organization and dependency management.