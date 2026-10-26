# CBFlow API Reference

## Overview

This API reference provides comprehensive documentation for CBFlow's programmatic interfaces, including core utilities, configuration management, node operations, and extension points. The APIs are organized by namespace and functionality.

## Core Namespace APIs

### `::CBFlow::Utilities`

The utilities namespace provides common functions used throughout CBFlow.

#### Logging Functions

##### `cbflow_log`
```tcl
proc ::CBFlow::Utilities::cbflow_log {level message {context ""}}
```

**Description**: Centralized logging function for all CBFlow operations.

**Parameters**:
- `level` (string): Log level - "ERROR", "WARN", "INFO", "DEBUG"
- `message` (string): Log message content
- `context` (string, optional): Additional context information

**Returns**: Nothing

**Example**:
```tcl
::CBFlow::Utilities::cbflow_log "INFO" "Starting synthesis" "SYNTH"
::CBFlow::Utilities::cbflow_log "ERROR" "File not found: design.v"
```

##### `cbflow_error`
```tcl
proc ::CBFlow::Utilities::cbflow_error {message {error_code ""} {context ""}}
```

**Description**: Enhanced error handling with logging and optional error codes.

**Parameters**:
- `message` (string): Error message
- `error_code` (string, optional): Error code for programmatic handling
- `context` (string, optional): Context where error occurred

**Throws**: Error with specified message

**Example**:
```tcl
::CBFlow::Utilities::cbflow_error "Invalid flow type: $flow_type" "INVALID_FLOW" "validation"
```

##### `cbflow_debug`
```tcl
proc ::CBFlow::Utilities::cbflow_debug {message {context ""}}
```

**Description**: Debug-level logging that respects debug mode settings.

**Parameters**:
- `message` (string): Debug message
- `context` (string, optional): Debug context

**Returns**: Nothing

#### File Validation Functions

##### `validate_file_exists`
```tcl
proc ::CBFlow::Utilities::validate_file_exists {file_path {error_on_missing true}}
```

**Description**: Validates file existence with optional error throwing.

**Parameters**:
- `file_path` (string): Path to file to validate
- `error_on_missing` (boolean, optional): Whether to throw error if missing (default: true)

**Returns**: Boolean indicating file existence

**Throws**: Error if file missing and `error_on_missing` is true

**Example**:
```tcl
if {[::CBFlow::Utilities::validate_file_exists $input_file false]} {
    # Process file
}
```

##### `create_timestamp`
```tcl
proc ::CBFlow::Utilities::create_timestamp {{format "%Y%m%d_%H%M%S"}}
```

**Description**: Creates formatted timestamp strings.

**Parameters**:
- `format` (string, optional): Tcl clock format string

**Returns**: Formatted timestamp string

**Example**:
```tcl
set timestamp [::CBFlow::Utilities::create_timestamp]
set iso_timestamp [::CBFlow::Utilities::create_timestamp "%Y-%m-%dT%H:%M:%S"]
```

### `::CBFlow::Directory`

Directory management and structure operations.

#### Directory Creation

##### `create_flow_directories`
```tcl
proc ::CBFlow::Directory::create_flow_directories {flow_type run_dir}
```

**Description**: Creates complete directory structure for specified flow type.

**Parameters**:
- `flow_type` (string): Flow type (SYNTH, FP, PNR, etc.)
- `run_dir` (string): Base run directory path

**Returns**: Boolean success status

**Throws**: Error if flow_type invalid or directory creation fails

**Example**:
```tcl
::CBFlow::Directory::create_flow_directories "SYNTH" "/path/to/run"
```

##### `get_flow_directory_path`
```tcl
proc ::CBFlow::Directory::get_flow_directory_path {flow_type dir_type run_dir}
```

**Description**: Resolves flow-specific directory path.

**Parameters**:
- `flow_type` (string): Flow type
- `dir_type` (string): Directory type (work, logs, reports, results)
- `run_dir` (string): Base run directory

**Returns**: Full directory path or empty string if not found

**Example**:
```tcl
set work_dir [::CBFlow::Directory::get_flow_directory_path "SYNTH" "work" $run_dir]
```

#### Directory Validation

##### `validate_directory_structure`
```tcl
proc ::CBFlow::Directory::validate_directory_structure {flow_type run_dir}
```

**Description**: Validates that required directory structure exists.

**Parameters**:
- `flow_type` (string): Flow type to validate
- `run_dir` (string): Run directory to check

**Returns**: Boolean validation result

**Example**:
```tcl
if {![::CBFlow::Directory::validate_directory_structure "SYNTH" $run_dir]} {
    error "Invalid directory structure"
}
```

### `::CBFlow::NodeManagement`

Node and branch management operations.

#### Node Operations

##### `create_execution_node`
```tcl
proc ::CBFlow::NodeManagement::create_execution_node {flow_type node_type node_name run_dir}
```

**Description**: Creates new execution node with validation.

**Parameters**:
- `flow_type` (string): Flow type (SYNTH, FP, PNR, etc.)
- `node_type` (string): Type of node (synthesis, floorplan, place, etc.)
- `node_name` (string): Custom name for the node
- `run_dir` (string): Run directory path

**Returns**: Boolean success status

**Throws**: Error if validation fails or node creation fails

**Example**:
```tcl
::CBFlow::NodeManagement::create_execution_node "SYNTH" "synthesis" "synthesis_low_power" $run_dir
```

##### `list_available_nodes`
```tcl
proc ::CBFlow::NodeManagement::list_available_nodes {flow_type {run_dir ""}}
```

**Description**: Lists all available nodes for specified flow type.

**Parameters**:
- `flow_type` (string): Flow type to query
- `run_dir` (string, optional): Run directory to check for existing nodes

**Returns**: List of available node types

**Example**:
```tcl
set nodes [::CBFlow::NodeManagement::list_available_nodes "FP"]
# Returns: {inputs import_design floorplan powerplan post_floorplan export_data release_data}
```

##### `get_node_status`
```tcl
proc ::CBFlow::NodeManagement::get_node_status {node_name run_dir}
```

**Description**: Gets current status of specified node.

**Parameters**:
- `node_name` (string): Name of node to check
- `run_dir` (string): Run directory path

**Returns**: Dictionary with status information

**Example**:
```tcl
set status [::CBFlow::NodeManagement::get_node_status "synthesis" $run_dir]
# Returns: {status "completed" timestamp "20251007_143022" duration "1800"}
```

#### Branch Operations

##### `create_node_branch`
```tcl
proc ::CBFlow::NodeManagement::create_node_branch {base_node branch_name {config_overrides {}}}
```

**Description**: Creates branch from existing node.

**Parameters**:
- `base_node` (string): Base node to branch from
- `branch_name` (string): Name for new branch
- `config_overrides` (dict, optional): Configuration overrides for branch

**Returns**: Boolean success status

**Example**:
```tcl
set overrides {optimization_effort "high" power_optimization "true"}
::CBFlow::NodeManagement::create_node_branch "synthesis" "synthesis_high_effort" $overrides
```

##### `delete_node`
```tcl
proc ::CBFlow::NodeManagement::delete_node {node_name run_dir {force false}}
```

**Description**: Deletes specified node and associated files.

**Parameters**:
- `node_name` (string): Node to delete
- `run_dir` (string): Run directory path
- `force` (boolean, optional): Force deletion ignoring dependencies

**Returns**: Boolean success status

### `::CBFlow::Validation`

Input and output validation functions.

#### Input Validation

##### `validate_input_files`
```tcl
proc ::CBFlow::Validation::validate_input_files {flow_type input_spec}
```

**Description**: Comprehensive validation of input files for flow.

**Parameters**:
- `flow_type` (string): Flow type for validation context
- `input_spec` (dict): Dictionary of file_type -> file_path mappings

**Returns**: Boolean validation result

**Throws**: Error with detailed validation failures

**Example**:
```tcl
set inputs {
    rtl "/path/to/design.v"
    sdc "/path/to/constraints.sdc"
    library "/path/to/library.lib"
}
::CBFlow::Validation::validate_input_files "SYNTH" $inputs
```

##### `validate_configuration`
```tcl
proc ::CBFlow::Validation::validate_configuration {config_arrays}
```

**Description**: Validates configuration arrays for completeness and consistency.

**Parameters**:
- `config_arrays` (list): List of configuration array names to validate

**Returns**: Boolean validation result

**Example**:
```tcl
::CBFlow::Validation::validate_configuration {flow project synth}
```

#### Quality Validation

##### `check_quality_metrics`
```tcl
proc ::CBFlow::Validation::check_quality_metrics {flow_type results_dir {thresholds {}}}
```

**Description**: Validates quality metrics against specified thresholds.

**Parameters**:
- `flow_type` (string): Flow type for metric context
- `results_dir` (string): Directory containing results to validate
- `thresholds` (dict, optional): Custom quality thresholds

**Returns**: Dictionary with quality check results

**Example**:
```tcl
set thresholds {timing_slack 0.0 area_utilization 0.85}
set quality [::CBFlow::Validation::check_quality_metrics "SYNTH" $results_dir $thresholds]
```

## Configuration Management APIs

### Configuration Loading

#### `load_hierarchical_configuration`
```tcl
proc load_hierarchical_configuration {flow_type run_dir}
```

**Description**: Loads configuration using hierarchical precedence rules.

**Parameters**:
- `flow_type` (string): Flow type for configuration context
- `run_dir` (string): Run directory containing user configuration

**Returns**: Nothing (populates global configuration arrays)

**Side Effects**: Populates global arrays: flow, project, tech, and flow-specific arrays

**Example**:
```tcl
load_hierarchical_configuration "SYNTH" $run_dir
# After this call, global arrays are populated with merged configuration
```

#### `get_config_value`
```tcl
proc get_config_value {array_name key {default ""}}
```

**Description**: Safely retrieves configuration value with default fallback.

**Parameters**:
- `array_name` (string): Name of configuration array
- `key` (string): Configuration key to retrieve
- `default` (string, optional): Default value if key not found

**Returns**: Configuration value or default

**Example**:
```tcl
set design_name [get_config_value "flow" "design_name" "default_design"]
set clock_period [get_config_value "project" "clock_period" "2.0"]
```

#### `set_config_value`
```tcl
proc set_config_value {array_name key value}
```

**Description**: Sets configuration value in specified array.

**Parameters**:
- `array_name` (string): Target configuration array
- `key` (string): Configuration key
- `value` (string): Value to set

**Returns**: Nothing

**Example**:
```tcl
set_config_value "flow" "debug_mode" "true"
set_config_value "synth" "optimization_effort" "high"
```

### Flow-Specific Configuration

#### `get_flow_config`
```tcl
proc get_flow_config {flow_type key {default ""}}
```

**Description**: Retrieves configuration from flow-specific array.

**Parameters**:
- `flow_type` (string): Flow type (determines array name)
- `key` (string): Configuration key
- `default` (string, optional): Default value

**Returns**: Configuration value or default

**Example**:
```tcl
set synth_effort [get_flow_config "SYNTH" "optimization_effort" "medium"]
set place_density [get_flow_config "PNR" "place_density" "0.70"]
```

## Generation APIs

### Makefile Generation

#### `generate_run_makefile`
```tcl
proc generate_run_makefile {flow_type run_dir {options {}}}
```

**Description**: Generates run-specific Makefile for flow execution.

**Parameters**:
- `flow_type` (string): Flow type for Makefile generation
- `run_dir` (string): Target run directory
- `options` (dict, optional): Generation options

**Returns**: Boolean success status

**Throws**: Error if generation fails

**Example**:
```tcl
set options {flat_mode true debug_mode true}
generate_run_makefile "SYNTH" $run_dir $options
```

#### `generate_consolidated_config`
```tcl
proc generate_consolidated_config {run_dir}
```

**Description**: Generates consolidated configuration file from hierarchy.

**Parameters**:
- `run_dir` (string): Run directory for output

**Returns**: Path to generated configuration file

**Example**:
```tcl
set config_file [generate_consolidated_config $run_dir]
```

### Template Processing

#### `process_template`
```tcl
proc process_template {template_file substitutions output_file}
```

**Description**: Processes template file with variable substitutions.

**Parameters**:
- `template_file` (string): Path to template file
- `substitutions` (dict): Variable -> value substitution mappings
- `output_file` (string): Output file path

**Returns**: Boolean success status

**Example**:
```tcl
set subs {
    FLOW_TYPE "SYNTH"
    DESIGN_NAME "my_cpu"
    RUN_DIR $run_dir
}
process_template "template.mk.in" $subs "Makefile"
```

## Flow Execution APIs

### Stage Execution

#### `execute_stage`
```tcl
proc execute_stage {flow_type stage_name run_dir {options {}}}
```

**Description**: Executes specific flow stage.

**Parameters**:
- `flow_type` (string): Flow type
- `stage_name` (string): Stage to execute
- `run_dir` (string): Run directory
- `options` (dict, optional): Execution options

**Returns**: Boolean success status

**Example**:
```tcl
set options {timeout 3600 parallel false}
execute_stage "SYNTH" "synthesis" $run_dir $options
```

#### `get_stage_dependencies`
```tcl
proc get_stage_dependencies {flow_type stage_name}
```

**Description**: Returns list of stage dependencies.

**Parameters**:
- `flow_type` (string): Flow type
- `stage_name` (string): Stage to query

**Returns**: List of dependency stage names

**Example**:
```tcl
set deps [get_stage_dependencies "FP" "powerplan"]
# Returns: {inputs import_design floorplan}
```

### Execution Status

#### `get_execution_status`
```tcl
proc get_execution_status {run_dir {detailed false}}
```

**Description**: Gets execution status for run.

**Parameters**:
- `run_dir` (string): Run directory to check
- `detailed` (boolean, optional): Include detailed timing information

**Returns**: Dictionary with status information

**Example**:
```tcl
set status [get_execution_status $run_dir true]
# Returns: {
#   overall_status "running"
#   completed_stages {inputs synthesis}
#   current_stage "export_data"
#   start_time "20251007_143022"
#   estimated_completion "20251007_153022"
# }
```

## Error Handling APIs

### Error Reporting

#### `report_error`
```tcl
proc report_error {error_msg {context ""} {recovery_suggestion ""}}
```

**Description**: Standardized error reporting with optional recovery suggestions.

**Parameters**:
- `error_msg` (string): Error message
- `context` (string, optional): Context where error occurred
- `recovery_suggestion` (string, optional): Suggested recovery action

**Returns**: Nothing

**Example**:
```tcl
report_error "Synthesis failed" "SYNTH execution" "Check RTL for syntax errors"
```

### Error Recovery

#### `attempt_recovery`
```tcl
proc attempt_recovery {recovery_strategy run_dir}
```

**Description**: Attempts automated error recovery.

**Parameters**:
- `recovery_strategy` (string): Recovery strategy to attempt
- `run_dir` (string): Run directory for recovery

**Returns**: Boolean indicating recovery success

**Example**:
```tcl
if {[attempt_recovery "retry_with_reduced_effort" $run_dir]} {
    puts "Recovery successful"
}
```

## Extension APIs

### Plugin Interface

#### `register_flow_plugin`
```tcl
proc register_flow_plugin {plugin_name plugin_namespace}
```

**Description**: Registers flow plugin for extended functionality.

**Parameters**:
- `plugin_name` (string): Name of plugin
- `plugin_namespace` (string): Namespace containing plugin procedures

**Returns**: Boolean registration success

**Example**:
```tcl
register_flow_plugin "custom_optimizer" "::MyCompany::CustomOpt"
```

#### `execute_plugin_hook`
```tcl
proc execute_plugin_hook {hook_name args}
```

**Description**: Executes registered plugin hooks.

**Parameters**:
- `hook_name` (string): Hook identifier
- `args` (list): Arguments to pass to hook

**Returns**: Results from hook execution

**Example**:
```tcl
execute_plugin_hook "pre_synthesis" $flow_type $run_dir
```

### Custom Flow Integration

#### `define_custom_flow`
```tcl
proc define_custom_flow {flow_name stage_sequence dependencies}
```

**Description**: Defines new custom flow type.

**Parameters**:
- `flow_name` (string): Name for custom flow
- `stage_sequence` (list): Ordered list of stages
- `dependencies` (dict): Stage dependency mappings

**Returns**: Boolean definition success

**Example**:
```tcl
set stages {setup custom_opt verify cleanup}
set deps {
    setup {}
    custom_opt {setup}
    verify {custom_opt}
    cleanup {verify}
}
define_custom_flow "CUSTOM_OPT" $stages $deps
```

## Data Structure References

### Configuration Arrays

#### Flow Array Structure
```tcl
array set flow {
    design_name "string"          # Design name
    flow_type "string"            # Flow type (SYNTH, FP, PNR, etc.)
    run_type "string"             # Execution mode (flat, node)
    debug_mode "boolean"          # Debug output enable
    timeout "integer"             # Overall timeout (seconds)
    max_jobs "integer"            # Maximum parallel jobs
}
```

#### Project Array Structure
```tcl
array set project {
    technology "string"           # Technology node
    clock_period "float"          # Clock period (ns)
    target_frequency "float"      # Target frequency (MHz)
    power_budget "float"          # Power budget (mW)
    area_target "float"           # Area target (mm²)
}
```

#### Flow-Specific Array Structure
```tcl
# Example: Synthesis configuration
array set synth {
    optimization_effort "string"  # low, medium, high, maximum
    optimization_focus "string"   # timing, area, power
    tool,vendor "string"          # Tool vendor
    tool,name "string"            # Tool name
    tool,version "string"         # Tool version
    timeout,synthesis "integer"   # Stage timeout
}
```

### Status Data Structures

#### Node Status Structure
```tcl
{
    status "string"               # not_started, running, completed, failed
    start_time "string"           # Start timestamp
    end_time "string"             # End timestamp (if completed)
    duration "integer"            # Execution duration (seconds)
    log_file "string"             # Path to log file
    error_message "string"        # Error message (if failed)
}
```

#### Quality Metrics Structure
```tcl
{
    timing_slack "float"          # Worst slack (ns)
    area "float"                  # Total area (um²)
    power "float"                 # Total power (mW)
    utilization "float"           # Area utilization (0.0-1.0)
    violations "integer"          # Number of violations
}
```

## Error Codes

### Standard Error Codes
- **`CONFIG_ERROR`**: Configuration-related errors
- **`FILE_ERROR`**: File system or I/O errors
- **`VALIDATION_ERROR`**: Input or output validation failures
- **`EXECUTION_ERROR`**: Flow execution failures
- **`TOOL_ERROR`**: EDA tool-related errors
- **`TIMEOUT_ERROR`**: Execution timeout errors
- **`DEPENDENCY_ERROR`**: Dependency resolution failures
- **`PERMISSION_ERROR`**: File or directory permission issues

### Usage Example
```tcl
if {[catch {
    execute_stage "SYNTH" "synthesis" $run_dir
} error]} {
    if {[string match "*TIMEOUT_ERROR*" $error]} {
        # Handle timeout specifically
        attempt_recovery "extend_timeout" $run_dir
    } else {
        # Generic error handling
        report_error $error
    }
}
```

---

This API reference provides the foundation for programmatic interaction with CBFlow, enabling custom scripts, integrations, and extensions to leverage the full power of the physical design automation framework.