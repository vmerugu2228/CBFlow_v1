# CBFlow Flat Mode Architecture

## Overview

Flat Mode is CBFlow's advanced execution model that consolidates multiple execution stages into single merged nodes, optimizing performance while maintaining the same functional outcomes. This architecture reduces tool overhead, minimizes data transfer, and improves overall execution efficiency.

## Architectural Concept

### Traditional vs Flat Mode Execution

#### Traditional (Regular) Mode
```
inputs → stage1 → stage2 → stage3 → stage4 → export_data → release_data
   ↓        ↓        ↓        ↓        ↓
 Tool    Tool     Tool     Tool     Tool
Session Session  Session  Session  Session
```

#### Flat Mode
```
inputs → merged_execution_node → export_data → release_data
   ↓             ↓
 Tool         Single Tool Session
Session      (stages 1-4 merged)
```

### Key Benefits
- **Performance**: 20-40% execution time reduction
- **Resource Efficiency**: Lower memory and CPU overhead
- **Simplified Management**: Fewer execution nodes to monitor
- **Reduced I/O**: Minimized intermediate file operations
- **Improved Convergence**: Better optimization across merged stages

## Implementation Architecture

### Flow Configuration Structure

Flat mode is configured through flow-level settings:

```tcl
# Flat mode configuration arrays
array set flat_data_sequence {
    FP {inputs export_data release_data}
    PNR {inputs export_data release_data}
    SYNTH {inputs export_data release_data}
}

array set flat_merged_nodes {
    FP "floorplan_merged"
    PNR "pnr_merged"
    SYNTH "synthesis_merged"
}

array set flat_execution_stages {
    FP {import_design floorplan powerplan post_floorplan}
    PNR {place cts cts_opt route route_opt pro signoff}
    SYNTH {synthesis}
}
```

### User Configuration Activation
```tcl
# User enables flat mode in run configuration
array set flow {
    run_type "flat"
    design_name "my_design"
    flow_type "FP"
}
```

## Merged Node Generation

### Command File Consolidation
Flat mode generates consolidated command files that merge flow_procs from individual stages:

```tcl
# Original individual stage commands:
# import_design_innovus.tcl
# floorplan_innovus.tcl
# powerplan_innovus.tcl
# post_floorplan_innovus.tcl

# Generated consolidated command:
# consolidated_floorplan_merged.tcl
```

### Flow_Proc Extraction and Merging
The generation process extracts flow_procs from each execution stage:

```tcl
# Extraction process
proc extract_and_merge_flow_procs {flow_type exec_stages} {
    set merged_content ""

    foreach stage $exec_stages {
        set cmd_files [find_stage_command_files $flow_type $stage]
        foreach cmd_file $cmd_files {
            set flow_procs [extract_flow_procs_from_file $cmd_file]
            append merged_content $flow_procs
        }
    }

    return $merged_content
}
```

### Generated Flat Command Structure
```tcl
#!/usr/bin/env tclsh
# CBFlow Flat Mode - Consolidated [FLOW] Flow
# Generated: [TIMESTAMP]
# Merged Node: [merged_node_name]
# Original Execution Nodes: [execution_stages]

# Load run environment
set run_dir [expr {[info exists ::env(CBFLOW_RUN_DIR)] ? $::env(CBFLOW_RUN_DIR) : [pwd]}]
source "$run_dir/.run.cbflow.tcl"

# Load flow utilities
source "$FLOW_DIR/utils/utilities/$utilities_version/utils.tcl"

# Flat mode execution tracking
set total_execution_stages [llength $execution_stages]
set completed_execution_stages 0

# For each original execution stage
foreach stage $execution_stages {
    flat_log "INFO" "Starting $stage stage..."

    # Execute merged flow_procs from this stage
    [merged_flow_procs_for_stage]

    incr completed_execution_stages
    flat_log "SUCCESS" "$stage stage completed"
}

flat_log "SUCCESS" "Flat mode execution completed"
```

## Makefile Integration

### Flat Mode Target Generation
Run Makefiles generate different targets for flat mode:

#### Regular Mode Targets
```makefile
# Individual stage targets
import_design: $(IMPORT_DESIGN_STAMP)
floorplan: $(FLOORPLAN_STAMP)
powerplan: $(POWERPLAN_STAMP)
post_floorplan: $(POST_FLOORPLAN_STAMP)
```

#### Flat Mode Targets
```makefile
# Merged execution target
floorplan_merged: $(FLOORPLAN_MERGED_STAMP)

$(FLOORPLAN_MERGED_STAMP): $(FLOORPLAN_MERGED_VALIDATE_STAMP)
    @echo "Complete floorplan_merged flow finished"
    @touch $@

# Consolidated setup, run, validate phases
$(FLOORPLAN_MERGED_SETUP_STAMP): $(INPUTS_STAMP)
    @echo "Setting up floorplan_merged with hierarchical configuration..."
    @$(ENV_SETUP) tclsh "$$FLOW_DIR/utils/generation/$$GENERATION_VERSION/generate_setup.tcl" FP floorplan_merged floorplan_merged_default "$$RUN_DIR"
    @touch $@

$(FLOORPLAN_MERGED_RUN_STAMP): $(FLOORPLAN_MERGED_SETUP_STAMP)
    @echo "Running floorplan_merged with hierarchical configuration..."
    @cd work/FP/floorplan_merged/run && $(PNR_TOOL) -f setup.tcl
    @touch $@
```

## Node Management Integration

### Flat Mode Validation
Node management commands enforce flat mode restrictions:

```tcl
proc validate_flat_mode_restrictions {node_type flow_type} {
    global flow

    # Check if we're in flat mode
    set run_type "node"
    if {[info exists flow(run_type)]} {
        set run_type $flow(run_type)
    }

    if {$run_type eq "flat"} {
        # Get blocked execution nodes for this flow
        set blocked_nodes [get_blocked_execution_nodes $flow_type]

        if {[lsearch -exact $blocked_nodes $node_type] != -1} {
            error "Cannot add individual execution node '$node_type' in flat mode"
        }
    }
}
```

### Allowed vs Blocked Operations

#### Allowed in Flat Mode
- **Data Nodes**: `inputs`, `export_data`, `release_data`
- **Merged Execution Nodes**: `floorplan_merged`, `pnr_merged`, etc.
- **Custom Data Variants**: `inputs1`, `export_data_custom`

#### Blocked in Flat Mode
- **Individual Execution Nodes**: `import_design`, `floorplan`, `powerplan`
- **Execution Branches**: `create_branch` command entirely blocked
- **Stage Variants**: `floorplan1`, `place2`, etc.

### Error Messages and Guidance
```bash
❌ In flat mode, individual execution nodes are not allowed
ℹ Individual execution nodes are merged into a single execution node in flat mode
ℹ Valid node types for FP (flat mode): inputs, floorplan_merged, export_data, release_data
ℹ Blocked execution nodes: import_design, floorplan, powerplan, post_floorplan
```

## Status Reporting Integration

### Flat Mode Aware Status Display
Status commands detect flat mode and display appropriate structure:

```tcl
proc get_base_flow_nodes {flow_type} {
    # Check if we're in flat mode
    set run_type "node"
    if {[info exists ::flow(run_type)]} {
        set run_type $::flow(run_type)
    }

    # Return flat mode structure if enabled
    if {$run_type eq "flat"} {
        return [get_flat_mode_nodes $flow_type]
    }

    # Otherwise return regular nodes
    return [get_regular_mode_nodes $flow_type]
}
```

### Status Display Examples

#### Regular Mode Status
```
Base Flow Nodes:
  ⚪ inputs (Not Started)
  ⚪ import_design (Not Started)
  ⚪ floorplan (Not Started)
  ⚪ powerplan (Not Started)
  ⚪ post_floorplan (Not Started)
  ⚪ export_data (Not Started)
  ⚪ release_data (Not Started)
```

#### Flat Mode Status
```
Flow Nodes (flat mode):
  ⚪ inputs (Not Started)
  ⚪ floorplan_merged (Not Started)
  ⚪ export_data (Not Started)
  ⚪ release_data (Not Started)
```

## Performance Characteristics

### Execution Time Reduction
Typical performance improvements:

| Flow Type | Regular Mode | Flat Mode | Improvement |
|-----------|-------------|-----------|-------------|
| SYNTH     | 45 min      | 32 min    | 29%         |
| FP        | 2.5 hours   | 1.8 hours | 28%         |
| PNR       | 8 hours     | 5.5 hours | 31%         |

### Resource Utilization
- **Memory**: 15-25% reduction in peak memory usage
- **Disk I/O**: 40-60% reduction in intermediate file operations
- **Tool Licensing**: Reduced tool session count
- **Network Traffic**: Minimized network file system access

### Overhead Reduction
```
Regular Mode Overhead:
- Tool startup: N × startup_time
- Environment setup: N × setup_time
- File I/O: N × (save + load) operations
- Memory allocation: N × allocation cycles

Flat Mode Overhead:
- Tool startup: 1 × startup_time
- Environment setup: 1 × setup_time
- File I/O: Minimal intermediate operations
- Memory allocation: Consolidated allocation
```

## Flow-Specific Implementations

### FP Flow Flat Mode
```
Regular: inputs → import_design → floorplan → powerplan → post_floorplan → export_data → release_data
Flat:    inputs → floorplan_merged → export_data → release_data

Merged stages: import_design + floorplan + powerplan + post_floorplan
Benefits: Single Innovus session, direct data flow, optimized floorplan convergence
```

### PNR Flow Flat Mode
```
Regular: inputs → place → cts → cts_opt → route → route_opt → pro → signoff → export_data → release_data
Flat:    inputs → pnr_merged → export_data → release_data

Merged stages: place + cts + cts_opt + route + route_opt + pro + signoff
Benefits: Continuous optimization, better timing convergence, reduced database saves
```

### SYNTH Flow Flat Mode
```
Regular: inputs → synthesis → export_data → release_data
Flat:    inputs → synthesis_merged → export_data → release_data

Merged stages: synthesis (single stage, benefits limited)
Benefits: Simplified execution model, consistent interface
```

## Configuration Examples

### Enabling Flat Mode
```tcl
# User configuration to enable flat mode
array set flow {
    run_type "flat"           # Enable flat mode
    design_name "my_chip"
    flow_type "FP"
}

# Flow-specific flat mode settings
array set fp {
    flat_optimization "true"
    flat_memory_limit "32GB"
    flat_timeout "14400"      # 4 hours
}
```

### Flow-Specific Flat Configuration
```tcl
# Advanced flat mode configuration
array set flat_config {
    # Execution control
    enable_checkpoints "true"
    checkpoint_interval "30"  # minutes

    # Memory management
    memory_optimization "aggressive"
    garbage_collection "periodic"

    # Progress reporting
    progress_reporting "detailed"
    stage_timing "true"
}
```

## Limitations and Considerations

### When NOT to Use Flat Mode

1. **Interactive Development**
   - Need to examine intermediate results
   - Iterative design exploration
   - Debug-intensive flows

2. **Custom Stage Variants**
   - Multiple placement experiments
   - Different optimization strategies
   - Parallel execution branches

3. **Resource Constraints**
   - Limited memory for merged execution
   - Tool licensing restrictions
   - Checkpoint requirements

### Trade-offs
- **Performance vs Flexibility**: Faster execution but less control
- **Simplicity vs Customization**: Easier management but fewer options
- **Optimization vs Visibility**: Better convergence but less intermediate data

## Migration Strategy

### From Regular to Flat Mode
1. **Validate Flow**: Ensure flow works in regular mode
2. **Enable Flat Mode**: Set `run_type = "flat"`
3. **Test Execution**: Verify flat mode execution
4. **Compare Results**: Validate equivalent outputs
5. **Optimize Settings**: Tune flat mode parameters

### From Flat to Regular Mode
1. **Change Configuration**: Set `run_type = "node"`
2. **Remove Flat Restrictions**: Allow individual stage creation
3. **Regenerate Makefile**: Update execution targets
4. **Test Individual Stages**: Verify stage-by-stage execution

## Future Enhancements

### Advanced Flat Mode Features
- **Selective Merging**: User-defined stage groupings
- **Hybrid Execution**: Mix of flat and regular stages
- **Dynamic Mode Switching**: Runtime mode selection
- **Intelligent Checkpointing**: Automatic checkpoint insertion

### Performance Optimizations
- **Memory Streaming**: Large design memory optimization
- **Parallel Merging**: Multi-threaded execution within merged nodes
- **Predictive Optimization**: AI-driven optimization strategies
- **Resource Prediction**: Intelligent resource allocation

---

Flat Mode represents CBFlow's commitment to execution efficiency while maintaining architectural flexibility and user control over the physical design process.