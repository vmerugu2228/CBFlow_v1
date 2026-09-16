# CBFlow Script Development Guide

## Overview

This guide provides comprehensive information for developing CBFlow scripts, including architecture patterns, best practices, integration guidelines, and testing strategies. CBFlow scripts form the core automation engine of the physical design flow.

## Script Architecture

### CBFlow Script Categories

#### Core Script Categories
```
utils/
├── generation/         # Makefile and configuration generation
├── utilities/          # Common utility functions
├── validation/         # Quality assurance and validation
├── node_management/    # Node and branch management
└── release/           # Release packaging and management
```

Each category follows the version management structure:
```
utils/[category]/
├── v1.0.0/            # Stable version
├── workspace/         # Development area
├── current/           # Symlink to active version
└── tests/            # Test suite
```

### Script Types and Patterns

#### 1. Utility Scripts
**Purpose**: Reusable functions and procedures
**Pattern**: Namespace-organized, library-style

```tcl
# utilities/v1.0.0/utils.tcl
namespace eval ::CBFlow::Utilities {
    variable debug_mode false
    variable log_file ""

    namespace export {
        cbflow_log
        cbflow_error
        validate_file_exists
        create_timestamp
    }
}

proc ::CBFlow::Utilities::cbflow_log {level message {context ""}} {
    variable log_file

    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set log_entry "[$timestamp] [$level] $message"

    if {$context ne ""} {
        append log_entry " \[$context\]"
    }

    puts $log_entry

    if {$log_file ne "" && [file writable [file dirname $log_file]]} {
        set fd [open $log_file a]
        puts $fd $log_entry
        close $fd
    }
}
```

#### 2. Generation Scripts
**Purpose**: Create files, configurations, and build systems
**Pattern**: Template-based generation with validation

```tcl
# generation/v1.0.0/gen_run_makefile.tcl
#!/usr/bin/env tclsh

# Load dependencies
source "[file dirname [info script]]/../utilities/current/utils.tcl"

proc generate_run_makefile {flow_type run_dir {options {}}} {
    # Input validation
    if {![validate_flow_type $flow_type]} {
        return -code error "Invalid flow type: $flow_type"
    }

    if {![file isdirectory $run_dir]} {
        return -code error "Run directory does not exist: $run_dir"
    }

    # Load configuration
    load_hierarchical_configuration $flow_type $run_dir

    # Generate Makefile content
    set makefile_content [build_makefile_template $flow_type $options]

    # Write Makefile
    set makefile_path [file join $run_dir "Makefile"]
    write_file $makefile_path $makefile_content

    ::CBFlow::Utilities::cbflow_log "INFO" "Generated Makefile: $makefile_path"
    return true
}

# Template building function
proc build_makefile_template {flow_type options} {
    global flow

    # Determine execution mode
    set run_type "node"
    if {[info exists flow(run_type)]} {
        set run_type $flow(run_type)
    }

    # Load appropriate template
    if {$run_type eq "flat"} {
        set template [load_flat_mode_template $flow_type]
    } else {
        set template [load_regular_mode_template $flow_type]
    }

    # Substitute variables
    set substituted [substitute_template_variables $template $flow_type]

    return $substituted
}
```

#### 3. Node Management Scripts
**Purpose**: Manage execution nodes and dependencies
**Pattern**: State-based operations with validation

```tcl
# node_management/v1.0.0/manage_node.tcl
namespace eval ::CBFlow::NodeManagement {
    variable node_database
    variable valid_operations {list add delete create_branch delete_branch status}

    namespace export {
        manage_node_operation
        validate_node_operation
        list_available_nodes
    }
}

proc ::CBFlow::NodeManagement::manage_node_operation {operation args} {
    variable valid_operations

    # Validate operation
    if {$operation ni $valid_operations} {
        return -code error "Invalid operation: $operation. Valid: [join $valid_operations {, }]"
    }

    # Dispatch to specific handler
    switch $operation {
        "list" {
            return [handle_list_operation {*}$args]
        }
        "add" {
            return [handle_add_operation {*}$args]
        }
        "delete" {
            return [handle_delete_operation {*}$args]
        }
        "create_branch" {
            return [handle_create_branch_operation {*}$args]
        }
        "delete_branch" {
            return [handle_delete_branch_operation {*}$args]
        }
        "status" {
            return [handle_status_operation {*}$args]
        }
    }
}
```

#### 4. Validation Scripts
**Purpose**: Quality assurance and verification
**Pattern**: Rule-based validation with reporting

```tcl
# validation/v1.0.0/validate_flow.tcl
namespace eval ::CBFlow::Validation {
    variable validation_rules
    variable quality_metrics

    namespace export {
        validate_flow_inputs
        validate_flow_outputs
        generate_quality_report
    }
}

proc ::CBFlow::Validation::validate_flow_inputs {flow_type input_spec} {
    variable validation_rules

    set validation_errors {}

    # Validate each input file
    dict for {file_type file_path} $input_spec {
        # Check existence
        if {![file exists $file_path]} {
            lappend validation_errors "Missing $file_type: $file_path"
            continue
        }

        # Apply type-specific validation
        if {[dict exists $validation_rules $file_type]} {
            set validator [dict get $validation_rules $file_type]
            if {[catch {$validator $file_path} result]} {
                lappend validation_errors "Invalid $file_type $file_path: $result"
            }
        }
    }

    # Report results
    if {[llength $validation_errors] > 0} {
        ::CBFlow::Utilities::cbflow_log "ERROR" "Input validation failed"
        foreach error $validation_errors {
            ::CBFlow::Utilities::cbflow_log "ERROR" "  $error"
        }
        return false
    }

    ::CBFlow::Utilities::cbflow_log "INFO" "Input validation passed"
    return true
}
```

## Development Patterns

### Configuration Handling

#### Loading Hierarchical Configuration
```tcl
proc load_hierarchical_configuration {flow_type run_dir} {
    # Load in precedence order (lowest to highest priority)

    # 1. Flow configuration (system defaults)
    source_config_file "$::FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"
    source_config_file "$::FLOW_DIR/config/flow/v1.0.0/node_configs/${flow_type}_config.tcl"

    # 2. Technology configuration
    if {[info exists ::project(technology)]} {
        set tech_config "$::FLOW_DIR/config/technology/$::project(technology)/v1.0.0/technology_config.tcl"
        if {[file exists $tech_config]} {
            source_config_file $tech_config
        }
    }

    # 3. Project configuration
    if {[info exists ::project(name)]} {
        set project_config "$::FLOW_DIR/config/project/$::project(name)/v1.0.0/${::project(name)}_config.tcl"
        if {[file exists $project_config]} {
            source_config_file $project_config
        }
    }

    # 4. User configuration (highest priority)
    set user_config "$run_dir/setup/user_config.tcl"
    if {[file exists $user_config]} {
        source_config_file $user_config
    }

    # Generate consolidated configuration
    generate_consolidated_config $run_dir
}

proc source_config_file {config_file} {
    if {[catch {source $config_file} error]} {
        ::CBFlow::Utilities::cbflow_error "Failed to load configuration: $config_file - $error"
    }
}
```

#### Configuration Array Access
```tcl
proc get_config_value {array_name key {default ""}} {
    upvar #0 $array_name config_array

    if {[info exists config_array($key)]} {
        return $config_array($key)
    } else {
        return $default
    }
}

proc set_config_value {array_name key value} {
    upvar #0 $array_name config_array
    set config_array($key) $value
}

# Flow-specific config access
proc get_flow_config {flow_type key {default ""}} {
    set flow_var [string tolower $flow_type]
    return [get_config_value $flow_var $key $default]
}
```

### Error Handling Patterns

#### Robust Error Handling
```tcl
proc execute_with_error_handling {script_block {error_handler ""}} {
    set old_errorInfo $::errorInfo
    set old_errorCode $::errorCode

    if {[catch {
        uplevel 1 $script_block
    } result options]} {
        # Log error with context
        ::CBFlow::Utilities::cbflow_log "ERROR" "Execution failed: $result"

        # Execute custom error handler if provided
        if {$error_handler ne ""} {
            catch {uplevel 1 $error_handler}
        }

        # Restore error context and re-throw
        set ::errorInfo $old_errorInfo
        set ::errorCode $old_errorCode
        return -options $options $result
    }

    return $result
}

# Usage example
execute_with_error_handling {
    # Risky operation
    process_large_file $file_path
} {
    # Cleanup on error
    cleanup_temp_files
    send_error_notification
}
```

#### Validation with Context
```tcl
proc validate_with_context {validation_block context_info} {
    if {[catch {
        uplevel 1 $validation_block
    } result]} {
        set error_msg "Validation failed in $context_info: $result"
        ::CBFlow::Utilities::cbflow_error $error_msg
    }
    return true
}

# Usage
validate_with_context {
    if {![file exists $input_file]} {
        error "Input file missing"
    }
} "input validation for synthesis"
```

### File and Directory Operations

#### Safe File Operations
```tcl
proc safe_file_write {file_path content} {
    # Create backup if file exists
    if {[file exists $file_path]} {
        set backup_path "${file_path}.backup.[clock seconds]"
        file copy $file_path $backup_path
    }

    # Ensure directory exists
    set dir_path [file dirname $file_path]
    if {![file isdirectory $dir_path]} {
        file mkdir $dir_path
    }

    # Write to temporary file first
    set temp_path "${file_path}.tmp.[pid]"

    if {[catch {
        set fd [open $temp_path w]
        puts -nonewline $fd $content
        close $fd

        # Atomic move to final location
        file rename $temp_path $file_path
    } error]} {
        # Cleanup temp file on error
        if {[file exists $temp_path]} {
            file delete $temp_path
        }
        return -code error "Failed to write file $file_path: $error"
    }

    return true
}

proc safe_file_read {file_path} {
    if {![file exists $file_path]} {
        return -code error "File does not exist: $file_path"
    }

    if {![file readable $file_path]} {
        return -code error "File not readable: $file_path"
    }

    if {[catch {
        set fd [open $file_path r]
        set content [read $fd]
        close $fd
    } error]} {
        return -code error "Failed to read file $file_path: $error"
    }

    return $content
}
```

#### Directory Management
```tcl
proc create_directory_structure {base_dir structure_spec} {
    foreach {dir_type dir_path} $structure_spec {
        set full_path [file join $base_dir $dir_path]

        if {[catch {
            file mkdir $full_path
            ::CBFlow::Utilities::cbflow_log "INFO" "Created directory: $full_path"
        } error]} {
            ::CBFlow::Utilities::cbflow_error "Failed to create directory $full_path: $error"
        }
    }
}

proc cleanup_temp_directories {base_dir pattern} {
    set temp_dirs [glob -nocomplain -directory $base_dir $pattern]

    foreach temp_dir $temp_dirs {
        if {[file isdirectory $temp_dir]} {
            if {[catch {
                file delete -force $temp_dir
                ::CBFlow::Utilities::cbflow_log "INFO" "Cleaned up temp directory: $temp_dir"
            } error]} {
                ::CBFlow::Utilities::cbflow_log "WARN" "Failed to cleanup $temp_dir: $error"
            }
        }
    }
}
```

### Template Processing

#### Template System
```tcl
proc process_template {template_file substitutions output_file} {
    # Read template
    set template_content [safe_file_read $template_file]

    # Perform substitutions
    set processed_content $template_content
    dict for {variable value} $substitutions {
        set pattern "@${variable}@"
        regsub -all $pattern $processed_content $value processed_content
    }

    # Write processed content
    safe_file_write $output_file $processed_content

    return true
}

proc create_substitution_dict {flow_type run_dir} {
    global flow project tech

    # Build substitution dictionary
    set substitutions [dict create]

    # Basic substitutions
    dict set substitutions "FLOW_TYPE" $flow_type
    dict set substitutions "RUN_DIR" $run_dir
    dict set substitutions "TIMESTAMP" [clock format [clock seconds]]

    # Flow-specific substitutions
    if {[info exists flow(design_name)]} {
        dict set substitutions "DESIGN_NAME" $flow(design_name)
    }

    if {[info exists flow(run_type)]} {
        dict set substitutions "RUN_TYPE" $flow(run_type)
    }

    # Add environment variables
    dict set substitutions "FLOW_DIR" $::env(FLOW_DIR)
    dict set substitutions "USER" $::env(USER)

    return $substitutions
}
```

### Execution Control

#### Process Management
```tcl
proc execute_external_command {command {timeout 3600}} {
    ::CBFlow::Utilities::cbflow_log "INFO" "Executing: $command"

    # Start process
    if {[catch {
        set process_id [exec {*}$command &]
    } error]} {
        return -code error "Failed to start command: $error"
    }

    # Monitor execution with timeout
    set start_time [clock seconds]
    while {[process_exists $process_id]} {
        if {[expr {[clock seconds] - $start_time}] > $timeout} {
            # Kill process on timeout
            catch {exec kill $process_id}
            return -code error "Command timed out after $timeout seconds"
        }

        # Sleep briefly before next check
        after 1000
    }

    # Get exit status
    if {[catch {
        set exit_status [exec_get_exit_status $process_id]
    } error]} {
        return -code error "Failed to get exit status: $error"
    }

    if {$exit_status != 0} {
        return -code error "Command failed with exit status: $exit_status"
    }

    ::CBFlow::Utilities::cbflow_log "INFO" "Command completed successfully"
    return true
}

proc process_exists {pid} {
    return [expr {![catch {exec kill -0 $pid}]}]
}
```

#### Parallel Execution
```tcl
proc execute_parallel_tasks {task_list {max_parallel 4}} {
    set active_tasks {}
    set completed_tasks {}
    set failed_tasks {}

    foreach task $task_list {
        # Wait if at max parallel limit
        while {[llength $active_tasks] >= $max_parallel} {
            check_task_completion active_tasks completed_tasks failed_tasks
            after 1000
        }

        # Start new task
        set task_id [start_background_task $task]
        lappend active_tasks $task_id
    }

    # Wait for all tasks to complete
    while {[llength $active_tasks] > 0} {
        check_task_completion active_tasks completed_tasks failed_tasks
        after 1000
    }

    # Report results
    ::CBFlow::Utilities::cbflow_log "INFO" "Parallel execution complete: [llength $completed_tasks] succeeded, [llength $failed_tasks] failed"

    if {[llength $failed_tasks] > 0} {
        return -code error "Some tasks failed: $failed_tasks"
    }

    return $completed_tasks
}
```

## Integration Patterns

### Tool Integration

#### Tool Command Generation
```tcl
proc generate_tool_command {flow_type stage_name tool_config} {
    # Get tool information
    set tool_vendor [dict get $tool_config vendor]
    set tool_name [dict get $tool_config name]
    set tool_args [dict get $tool_config args]

    # Load tool-specific command template
    set template_file "$::FLOW_DIR/cmds/$flow_type/$tool_vendor/$tool_name/current/${stage_name}_${tool_name}.tcl"

    if {![file exists $template_file]} {
        return -code error "Tool command template not found: $template_file"
    }

    # Process template with flow_procs
    set command_content [extract_and_process_flow_procs $template_file $flow_type]

    return $command_content
}

proc extract_and_process_flow_procs {template_file flow_type} {
    set template_content [safe_file_read $template_file]

    # Extract flow_proc definitions
    set flow_procs [extract_flow_procs $template_content]

    # Build command script
    set command_script [build_command_header $flow_type]
    append command_script "\n# Flow procedures\n"
    append command_script $flow_procs
    append command_script "\n# Main execution\n"
    append command_script [build_main_execution $flow_procs]

    return $command_script
}
```

#### Flow Proc Extraction
```tcl
proc extract_flow_procs {template_content} {
    set flow_procs ""
    set in_flow_proc false
    set brace_count 0

    foreach line [split $template_content "\n"] {
        if {[regexp {^\s*flow_proc\s+(\w+)} $line -> proc_name]} {
            set in_flow_proc true
            set brace_count 0
            append flow_procs $line "\n"
        } elseif {$in_flow_proc} {
            append flow_procs $line "\n"

            # Count braces to find end of procedure
            set open_braces [llength [regexp -all -inline {\{} $line]]
            set close_braces [llength [regexp -all -inline {\}} $line]]
            set brace_count [expr {$brace_count + $open_braces - $close_braces}]

            if {$brace_count == 0} {
                set in_flow_proc false
            }
        }
    }

    return $flow_procs
}
```

### Flat Mode Implementation

#### Merged Node Generation
```tcl
proc generate_flat_mode_command {flow_type execution_stages} {
    set merged_command [build_flat_mode_header $flow_type $execution_stages]

    # Add environment setup
    append merged_command [build_environment_setup]

    # Process each execution stage
    foreach stage $execution_stages {
        append merged_command "\n# === $stage Stage ===\n"
        append merged_command "flat_log \"INFO\" \"Starting $stage stage...\"\n"

        # Extract and merge flow_procs for this stage
        set stage_procs [extract_stage_flow_procs $flow_type $stage]
        append merged_command $stage_procs

        append merged_command "flat_log \"SUCCESS\" \"$stage stage completed\"\n"
    }

    # Add completion
    append merged_command [build_flat_mode_completion]

    return $merged_command
}

proc build_flat_mode_header {flow_type execution_stages} {
    set header "#!/usr/bin/env tclsh\n"
    append header "# CBFlow Flat Mode - Consolidated $flow_type Flow\n"
    append header "# Generated: [clock format [clock seconds]]\n"
    append header "# Execution Stages: [join $execution_stages { }]\n\n"

    return $header
}
```

## Testing Strategies

### Unit Testing Patterns

#### Test Structure
```tcl
# Test framework integration
source "../common/test_framework.tcl"

# Module under test
source "../workspace/target_module.tcl"

proc setup_test {} {
    # Create isolated test environment
    global test_env
    set test_env(temp_dir) [create_temp_test_directory]
    set test_env(config) [create_test_configuration]
    return true
}

proc cleanup_test {} {
    global test_env
    if {[info exists test_env(temp_dir)]} {
        file delete -force $test_env(temp_dir)
    }
}

proc test_function_success_case {} {
    global test_env

    # Setup test data
    set input_data [create_test_input]

    # Execute function
    set result [target_function $input_data]

    # Verify results
    assert_true [validate_result $result] "Result should be valid"
    assert_equal [get_result_type $result] "expected_type" "Result type should match"

    return true
}

proc test_function_error_case {} {
    # Test error handling
    assert_error {
        target_function "invalid_input"
    } "Should throw error for invalid input"

    return true
}
```

#### Mock Objects
```tcl
# Mock external dependencies
proc create_mock_environment {} {
    # Mock file system operations
    rename file file_real
    proc file {args} {
        switch [lindex $args 0] {
            "exists" {
                return [mock_file_exists [lindex $args 1]]
            }
            "isdirectory" {
                return [mock_file_isdirectory [lindex $args 1]]
            }
            default {
                return [file_real {*}$args]
            }
        }
    }

    # Mock external commands
    rename exec exec_real
    proc exec {args} {
        return [mock_exec_command {*}$args]
    }
}

proc restore_real_environment {} {
    # Restore original commands
    rename file ""
    rename file_real file
    rename exec ""
    rename exec_real exec
}
```

### Integration Testing

#### Flow Testing
```tcl
proc test_complete_flow_execution {} {
    # Setup complete test environment
    set test_workspace [setup_integration_workspace]

    try {
        # Test complete flow
        cd $test_workspace

        # Create test run
        exec make create_run CONFIG=../test_configs/integration_test.tcl

        # Execute flow stages
        cd P0_run_SYNTH_test
        exec make inputs
        exec make synthesis
        exec make export_data

        # Validate results
        assert_file_exists "results/SYNTH/netlist.v"
        assert_file_exists "results/SYNTH/timing.rpt"

        # Validate quality metrics
        set metrics [parse_quality_metrics "reports/SYNTH/"]
        assert_within_range $metrics(timing_slack) -0.1 0.5
        assert_within_range $metrics(area) 1000 2000

    } finally {
        # Cleanup
        cd ../../..
        file delete -force $test_workspace
    }

    return true
}
```

## Performance Optimization

### Profiling and Monitoring

#### Performance Measurement
```tcl
proc measure_execution_time {script_block} {
    set start_time [clock microseconds]

    set result [uplevel 1 $script_block]

    set end_time [clock microseconds]
    set execution_time [expr {($end_time - $start_time) / 1000.0}]

    ::CBFlow::Utilities::cbflow_log "PERF" "Execution time: ${execution_time}ms"

    return [list $result $execution_time]
}

proc profile_function_calls {function_name} {
    # Wrap function with profiling
    set original_proc [info body $function_name]
    set original_args [info args $function_name]

    proc ${function_name}_original $original_args $original_proc

    proc $function_name $original_args "
        set start_time \[clock microseconds\]
        set result \[${function_name}_original {*}\$args\]
        set end_time \[clock microseconds\]
        set execution_time \[expr {(\$end_time - \$start_time) / 1000.0}\]
        ::CBFlow::Utilities::cbflow_log \"PROF\" \"$function_name: \${execution_time}ms\"
        return \$result
    "
}
```

#### Memory Optimization
```tcl
proc optimize_memory_usage {} {
    # Force garbage collection
    if {[info commands ::tcl::unsupported::gc] ne ""} {
        ::tcl::unsupported::gc
    }

    # Clear large variables
    clear_temporary_arrays

    # Optimize string operations
    use_string_map_for_substitutions
}

proc clear_temporary_arrays {} {
    global temp_arrays

    foreach array_name $temp_arrays {
        if {[array exists $array_name]} {
            unset $array_name
        }
    }

    set temp_arrays {}
}
```

## Best Practices Summary

### Code Organization
1. **Use Namespaces**: Organize related functions in namespaces
2. **Modular Design**: Create reusable, focused modules
3. **Clear Interfaces**: Define clear input/output specifications
4. **Documentation**: Document all public interfaces

### Error Handling
1. **Validate Early**: Check inputs at function entry
2. **Fail Fast**: Return errors immediately when detected
3. **Provide Context**: Include meaningful error messages
4. **Cleanup Resources**: Ensure proper cleanup on errors

### Performance
1. **Profile First**: Measure before optimizing
2. **Cache Results**: Cache expensive computations
3. **Minimize I/O**: Reduce file system operations
4. **Parallel Processing**: Use parallel execution where safe

### Testing
1. **Test Driven**: Write tests as you develop
2. **Cover Edge Cases**: Test boundary conditions
3. **Mock Dependencies**: Isolate units under test
4. **Integration Tests**: Test complete workflows

### Maintenance
1. **Version Control**: Track all changes
2. **Incremental Updates**: Make small, focused changes
3. **Backward Compatibility**: Maintain compatibility when possible
4. **Regular Refactoring**: Keep code clean and maintainable

---

This guide provides the foundation for developing robust, maintainable, and high-performance CBFlow scripts that integrate seamlessly with the overall automation framework.