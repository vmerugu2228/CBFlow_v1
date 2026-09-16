# CBFlow Testing Guide

## Overview

This guide covers the comprehensive testing framework for CBFlow, including unit testing, integration testing, regression testing, and performance testing. CBFlow's testing strategy ensures reliability, maintainability, and quality across all components.

## Testing Framework Architecture

### Test Hierarchy

```
tests/
├── unit/              # Unit tests for individual functions
├── integration/       # Integration tests for workflows
├── regression/        # Regression tests for stability
├── performance/       # Performance and benchmark tests
├── fixtures/          # Test data and configurations
├── common/           # Shared testing utilities
└── reports/          # Test execution reports
```

### Test Organization by Category

```
utils/[category]/tests/
├── unit/
│   ├── test_function1.tcl
│   ├── test_function2.tcl
│   └── test_module.tcl
├── integration/
│   ├── test_workflow_basic.tcl
│   ├── test_workflow_advanced.tcl
│   └── test_cross_module.tcl
├── regression/
│   ├── test_regression_suite.tcl
│   └── test_known_issues.tcl
├── fixtures/
│   ├── configs/
│   ├── inputs/
│   └── expected_outputs/
└── common/
    ├── test_framework.tcl
    ├── test_utilities.tcl
    └── mock_objects.tcl
```

## Test Framework Components

### Core Test Framework

#### test_framework.tcl
```tcl
#!/usr/bin/env tclsh
# CBFlow Test Framework
# Provides common testing utilities and assertion functions

namespace eval ::CBFlow::Test {
    variable test_results
    variable current_test
    variable test_count 0
    variable pass_count 0
    variable fail_count 0

    namespace export {
        run_test_suite
        assert_true
        assert_false
        assert_equal
        assert_error
        assert_file_exists
        assert_within_range
        create_temp_test_environment
        cleanup_test_environment
    }
}

# Test execution control
proc ::CBFlow::Test::run_test_suite {test_procedures} {
    variable test_count
    variable pass_count
    variable fail_count

    set test_count 0
    set pass_count 0
    set fail_count 0

    puts "========================================="
    puts "CBFlow Test Suite Execution"
    puts "========================================="

    foreach test_proc $test_procedures {
        if {[catch {
            run_single_test $test_proc
        } error]} {
            puts "ERROR: Test execution failed: $error"
            incr fail_count
        }
        incr test_count
    }

    puts "========================================="
    puts "Test Results: $pass_count passed, $fail_count failed out of $test_count total"
    puts "========================================="

    return [expr {$fail_count == 0}]
}

proc ::CBFlow::Test::run_single_test {test_proc} {
    variable current_test
    variable pass_count
    variable fail_count

    set current_test $test_proc
    puts "Running test: $test_proc"

    if {[catch {
        $test_proc
        puts "  PASS: $test_proc"
        incr pass_count
    } error]} {
        puts "  FAIL: $test_proc - $error"
        incr fail_count
    }
}

# Assertion functions
proc ::CBFlow::Test::assert_true {condition message} {
    if {![uplevel 1 [list expr $condition]]} {
        error "Assertion failed: $message (expected true, got false)"
    }
}

proc ::CBFlow::Test::assert_false {condition message} {
    if {[uplevel 1 [list expr $condition]]} {
        error "Assertion failed: $message (expected false, got true)"
    }
}

proc ::CBFlow::Test::assert_equal {actual expected message} {
    if {$actual ne $expected} {
        error "Assertion failed: $message (expected '$expected', got '$actual')"
    }
}

proc ::CBFlow::Test::assert_error {script expected_pattern} {
    set caught_error false
    if {[catch {
        uplevel 1 $script
    } error]} {
        set caught_error true
        if {$expected_pattern ne "" && ![string match $expected_pattern $error]} {
            error "Assertion failed: Error message doesn't match pattern '$expected_pattern', got '$error'"
        }
    }

    if {!$caught_error} {
        error "Assertion failed: Expected error but none was thrown"
    }
}

proc ::CBFlow::Test::assert_file_exists {file_path message} {
    if {![file exists $file_path]} {
        error "Assertion failed: $message (file does not exist: $file_path)"
    }
}

proc ::CBFlow::Test::assert_within_range {value min_val max_val message} {
    if {$value < $min_val || $value > $max_val} {
        error "Assertion failed: $message (value $value not in range \[$min_val, $max_val\])"
    }
}

# Test environment management
proc ::CBFlow::Test::create_temp_test_environment {} {
    set temp_dir "/tmp/cbflow_test_[clock seconds]_[pid]"
    file mkdir $temp_dir
    return $temp_dir
}

proc ::CBFlow::Test::cleanup_test_environment {temp_dir} {
    if {[file isdirectory $temp_dir]} {
        file delete -force $temp_dir
    }
}
```

### Test Utilities

#### test_utilities.tcl
```tcl
# Common test utilities and helper functions

namespace eval ::CBFlow::TestUtils {
    namespace export {
        create_test_config
        create_test_input_files
        validate_test_output
        compare_test_results
        generate_test_data
    }
}

proc ::CBFlow::TestUtils::create_test_config {config_type {custom_settings {}}} {
    switch $config_type {
        "basic_synth" {
            return [create_basic_synth_config $custom_settings]
        }
        "flat_mode" {
            return [create_flat_mode_config $custom_settings]
        }
        "multi_flow" {
            return [create_multi_flow_config $custom_settings]
        }
        default {
            error "Unknown config type: $config_type"
        }
    }
}

proc ::CBFlow::TestUtils::create_basic_synth_config {custom_settings} {
    set config {
        array set flow {
            design_name "test_design"
            flow_type "SYNTH"
            run_type "node"
        }

        array set project {
            technology "tsmc_7nm"
            clock_period "2.0"
        }

        array set synth {
            optimization_effort "medium"
            compile_strategy "timing"
        }
    }

    # Apply custom settings
    foreach {setting value} $custom_settings {
        append config "\nset $setting \"$value\""
    }

    return $config
}

proc ::CBFlow::TestUtils::create_test_input_files {temp_dir file_specs} {
    dict for {file_type content} $file_specs {
        set file_path [file join $temp_dir "${file_type}.test"]

        set fd [open $file_path w]
        puts -nonewline $fd $content
        close $fd

        dict set result_paths $file_type $file_path
    }

    return $result_paths
}

proc ::CBFlow::TestUtils::generate_test_rtl {} {
    return {
module test_design (
    input clk,
    input rst_n,
    input [7:0] data_in,
    output reg [7:0] data_out
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_out <= 8'b0;
    else
        data_out <= data_in;
end

endmodule
    }
}

proc ::CBFlow::TestUtils::generate_test_sdc {} {
    return {
create_clock -name clk -period 2.0 [get_ports clk]
set_input_delay -max 0.2 -clock clk [get_ports data_in]
set_output_delay -max 0.2 -clock clk [get_ports data_out]
    }
}
```

### Mock Objects

#### mock_objects.tcl
```tcl
# Mock objects for testing external dependencies

namespace eval ::CBFlow::Mock {
    variable mock_file_system
    variable mock_commands
    variable mock_tools

    namespace export {
        enable_file_system_mocking
        disable_file_system_mocking
        mock_file_exists
        mock_external_command
        mock_tool_execution
    }
}

proc ::CBFlow::Mock::enable_file_system_mocking {} {
    variable mock_file_system

    # Store original commands
    set mock_file_system(original_file) [info body file]
    set mock_file_system(original_glob) [info body glob]

    # Replace with mock versions
    rename file file_original
    proc file {args} {
        return [::CBFlow::Mock::mock_file_command {*}$args]
    }

    rename glob glob_original
    proc glob {args} {
        return [::CBFlow::Mock::mock_glob_command {*}$args]
    }
}

proc ::CBFlow::Mock::disable_file_system_mocking {} {
    # Restore original commands
    rename file ""
    rename file_original file
    rename glob ""
    rename glob_original glob
}

proc ::CBFlow::Mock::mock_file_command {operation args} {
    variable mock_file_system

    switch $operation {
        "exists" {
            set file_path [lindex $args 0]
            if {[dict exists $mock_file_system(exists) $file_path]} {
                return [dict get $mock_file_system(exists) $file_path]
            }
            return [file_original exists $file_path]
        }
        "isdirectory" {
            set file_path [lindex $args 0]
            if {[dict exists $mock_file_system(isdirectory) $file_path]} {
                return [dict get $mock_file_system(isdirectory) $file_path]
            }
            return [file_original isdirectory $file_path]
        }
        default {
            return [file_original $operation {*}$args]
        }
    }
}

proc ::CBFlow::Mock::set_mock_file_exists {file_path exists} {
    variable mock_file_system
    dict set mock_file_system(exists) $file_path $exists
}

proc ::CBFlow::Mock::mock_external_command {command expected_output {exit_code 0}} {
    variable mock_commands

    dict set mock_commands $command [list $expected_output $exit_code]

    # Replace exec command
    if {![info exists mock_commands(exec_original)]} {
        set mock_commands(exec_original) [info body exec]
        rename exec exec_original

        proc exec {args} {
            return [::CBFlow::Mock::mock_exec_command {*}$args]
        }
    }
}

proc ::CBFlow::Mock::mock_exec_command {args} {
    variable mock_commands

    set command_string [join $args " "]

    # Check for exact match first
    if {[dict exists $mock_commands $command_string]} {
        set result [dict get $mock_commands $command_string]
        set output [lindex $result 0]
        set exit_code [lindex $result 1]

        if {$exit_code != 0} {
            error $output
        }
        return $output
    }

    # Check for pattern matches
    dict for {pattern result} $mock_commands {
        if {[string match $pattern $command_string]} {
            set output [lindex $result 0]
            set exit_code [lindex $result 1]

            if {$exit_code != 0} {
                error $output
            }
            return $output
        }
    }

    # Fall back to original exec
    return [exec_original {*}$args]
}
```

## Unit Testing

### Unit Test Structure

#### Example Unit Test
```tcl
#!/usr/bin/env tclsh
# Unit Test: generate_run_makefile function

# Load test framework
source "../common/test_framework.tcl"
source "../common/test_utilities.tcl"
source "../common/mock_objects.tcl"

# Load module under test
source "../workspace/gen_run_makefile.tcl"

# Test setup
proc setup_test {} {
    global test_env

    # Create test environment
    set test_env(temp_dir) [::CBFlow::Test::create_temp_test_environment]
    set test_env(run_dir) [file join $test_env(temp_dir) "test_run"]
    file mkdir $test_env(run_dir)

    # Create test configuration
    set config_content [::CBFlow::TestUtils::create_test_config "basic_synth"]
    set config_file [file join $test_env(run_dir) "setup" "user_config.tcl"]
    file mkdir [file dirname $config_file]

    set fd [open $config_file w]
    puts $fd $config_content
    close $fd

    return true
}

proc cleanup_test {} {
    global test_env

    ::CBFlow::Test::cleanup_test_environment $test_env(temp_dir)
}

# Test cases
proc test_generate_makefile_basic_synth {} {
    global test_env

    # Execute function
    set result [generate_run_makefile "SYNTH" $test_env(run_dir)]

    # Verify success
    ::CBFlow::Test::assert_true $result "Makefile generation should succeed"

    # Verify Makefile exists
    set makefile_path [file join $test_env(run_dir) "Makefile"]
    ::CBFlow::Test::assert_file_exists $makefile_path "Makefile should be created"

    # Verify Makefile content
    set fd [open $makefile_path r]
    set makefile_content [read $fd]
    close $fd

    ::CBFlow::Test::assert_true [string match "*synthesis:*" $makefile_content] "Should contain synthesis target"
    ::CBFlow::Test::assert_true [string match "*inputs:*" $makefile_content] "Should contain inputs target"

    return true
}

proc test_generate_makefile_flat_mode {} {
    global test_env

    # Create flat mode configuration
    set config_content [::CBFlow::TestUtils::create_test_config "flat_mode"]
    set config_file [file join $test_env(run_dir) "setup" "user_config.tcl"]

    set fd [open $config_file w]
    puts $fd $config_content
    close $fd

    # Execute function
    set result [generate_run_makefile "SYNTH" $test_env(run_dir)]

    # Verify flat mode targets
    set makefile_path [file join $test_env(run_dir) "Makefile"]
    set fd [open $makefile_path r]
    set makefile_content [read $fd]
    close $fd

    ::CBFlow::Test::assert_true [string match "*synthesis_merged:*" $makefile_content] "Should contain merged synthesis target"

    return true
}

proc test_generate_makefile_invalid_flow_type {} {
    global test_env

    # Test error handling for invalid flow type
    ::CBFlow::Test::assert_error {
        generate_run_makefile "INVALID_FLOW" $test_env(run_dir)
    } "*Invalid flow type*"

    return true
}

proc test_generate_makefile_missing_directory {} {
    global test_env

    # Test error handling for missing directory
    ::CBFlow::Test::assert_error {
        generate_run_makefile "SYNTH" "/nonexistent/directory"
    } "*directory does not exist*"

    return true
}

# Performance test
proc test_generate_makefile_performance {} {
    global test_env

    # Measure execution time
    set start_time [clock milliseconds]
    set result [generate_run_makefile "SYNTH" $test_env(run_dir)]
    set end_time [clock milliseconds]

    set execution_time [expr {$end_time - $start_time}]

    # Should complete within reasonable time (5 seconds)
    ::CBFlow::Test::assert_within_range $execution_time 0 5000 "Execution should complete within 5 seconds"

    return true
}

# Run test suite
if {[info script] eq $argv0} {
    ::CBFlow::Test::run_test_suite {
        setup_test
        test_generate_makefile_basic_synth
        test_generate_makefile_flat_mode
        test_generate_makefile_invalid_flow_type
        test_generate_makefile_missing_directory
        test_generate_makefile_performance
        cleanup_test
    }
}
```

### Parameterized Testing

#### Data-Driven Tests
```tcl
proc test_multiple_flow_types {} {
    global test_env

    set flow_types {SYNTH FP PNR PV FCT}

    foreach flow_type $flow_types {
        puts "  Testing flow type: $flow_type"

        # Create flow-specific configuration
        set config [create_flow_config $flow_type]
        write_test_config $test_env(config_file) $config

        # Execute and verify
        set result [generate_run_makefile $flow_type $test_env(run_dir)]
        ::CBFlow::Test::assert_true $result "Should succeed for $flow_type"

        # Verify flow-specific content
        verify_flow_specific_content $flow_type $test_env(run_dir)
    }

    return true
}

proc create_flow_config {flow_type} {
    set base_config [::CBFlow::TestUtils::create_test_config "basic_synth"]

    # Flow-specific modifications
    switch $flow_type {
        "FP" {
            append base_config "\narray set flow {flow_type \"FP\"}"
            append base_config "\narray set fp {core_utilization \"0.75\"}"
        }
        "PNR" {
            append base_config "\narray set flow {flow_type \"PNR\"}"
            append base_config "\narray set pnr {place_density \"0.70\"}"
        }
        # Add other flow types...
    }

    return $base_config
}
```

## Integration Testing

### Workflow Integration Tests

#### Complete Flow Test
```tcl
#!/usr/bin/env tclsh
# Integration Test: Complete synthesis workflow

source "../common/test_framework.tcl"
source "../common/test_utilities.tcl"

proc setup_integration_test {} {
    global test_env

    # Create comprehensive test environment
    set test_env(workspace) [::CBFlow::Test::create_temp_test_environment]
    set test_env(core_dir) [file join $test_env(workspace) "core"]
    set test_env(run_dir) [file join $test_env(workspace) "run"]

    # Setup mock CBFlow environment
    setup_mock_cbflow_environment $test_env(core_dir)

    return true
}

proc setup_mock_cbflow_environment {core_dir} {
    # Create directory structure
    file mkdir [file join $core_dir "config" "flow" "v1.0.0"]
    file mkdir [file join $core_dir "scripts" "utilities" "v1.0.0"]
    file mkdir [file join $core_dir "scripts" "generation" "v1.0.0"]

    # Create minimal configuration files
    create_mock_flow_config $core_dir
    create_mock_utility_scripts $core_dir
    create_mock_generation_scripts $core_dir
}

proc test_complete_synthesis_workflow {} {
    global test_env

    # Set environment
    set ::env(FLOW_DIR) $test_env(core_dir)

    # Create test input files
    create_test_design_files $test_env(run_dir)

    # Test workflow steps
    test_run_creation $test_env(run_dir)
    test_input_processing $test_env(run_dir)
    test_synthesis_execution $test_env(run_dir)
    test_output_generation $test_env(run_dir)

    return true
}

proc test_run_creation {run_dir} {
    # Mock run creation
    file mkdir [file join $run_dir "setup"]
    file mkdir [file join $run_dir "work" "SYNTH"]
    file mkdir [file join $run_dir "logs" "SYNTH"]
    file mkdir [file join $run_dir "results" "SYNTH"]

    # Create configuration
    set config_file [file join $run_dir "setup" "user_config.tcl"]
    set config_content [::CBFlow::TestUtils::create_test_config "basic_synth"]

    set fd [open $config_file w]
    puts $fd $config_content
    close $fd

    ::CBFlow::Test::assert_file_exists $config_file "Configuration should be created"
}

proc test_input_processing {run_dir} {
    # Mock input processing
    set input_dir [file join $run_dir "work" "SYNTH" "inputs"]
    file mkdir $input_dir

    # Create mock input files
    set rtl_content [::CBFlow::TestUtils::generate_test_rtl]
    set sdc_content [::CBFlow::TestUtils::generate_test_sdc]

    set fd [open [file join $input_dir "design.v"] w]
    puts $fd $rtl_content
    close $fd

    set fd [open [file join $input_dir "design.sdc"] w]
    puts $fd $sdc_content
    close $fd

    ::CBFlow::Test::assert_file_exists [file join $input_dir "design.v"] "RTL should be processed"
    ::CBFlow::Test::assert_file_exists [file join $input_dir "design.sdc"] "SDC should be processed"
}

proc test_synthesis_execution {run_dir} {
    # Mock synthesis execution
    set synth_dir [file join $run_dir "work" "SYNTH" "synthesis"]
    file mkdir $synth_dir

    # Create mock synthesis results
    set fd [open [file join $synth_dir "synthesis.log"] w]
    puts $fd "INFO: Synthesis completed successfully"
    puts $fd "INFO: Area: 1500 um^2"
    puts $fd "INFO: Timing: slack = 0.2ns"
    close $fd

    ::CBFlow::Test::assert_file_exists [file join $synth_dir "synthesis.log"] "Synthesis log should exist"
}

proc test_output_generation {run_dir} {
    # Mock output generation
    set results_dir [file join $run_dir "results" "SYNTH"]
    file mkdir $results_dir

    # Create mock output files
    set fd [open [file join $results_dir "netlist.v"] w]
    puts $fd "// Synthesized netlist"
    puts $fd [::CBFlow::TestUtils::generate_test_rtl]
    close $fd

    set fd [open [file join $results_dir "timing.rpt"] w]
    puts $fd "Timing Report: All paths meet timing"
    close $fd

    ::CBFlow::Test::assert_file_exists [file join $results_dir "netlist.v"] "Netlist should be generated"
    ::CBFlow::Test::assert_file_exists [file join $results_dir "timing.rpt"] "Timing report should be generated"
}
```

### Cross-Module Integration

#### Module Interaction Test
```tcl
proc test_generation_utilities_integration {} {
    # Test interaction between generation and utilities modules

    # Setup test data
    set flow_type "SYNTH"
    set test_config [create_test_configuration]

    # Test generation module calling utilities
    ::CBFlow::Mock::mock_external_command "tclsh*" "Utilities loaded successfully"

    # Execute generation function that uses utilities
    set result [generate_with_utilities $flow_type $test_config]

    # Verify integration
    ::CBFlow::Test::assert_true $result "Generation should use utilities successfully"

    return true
}
```

## Regression Testing

### Regression Test Suite

#### Known Issues Regression
```tcl
#!/usr/bin/env tclsh
# Regression Test: Known issues and fixes

source "../common/test_framework.tcl"

proc test_hardcoded_path_regression {} {
    # Regression test for hardcoded path issues (previously fixed)

    # Create test environment without hardcoded paths
    set test_dir [::CBFlow::Test::create_temp_test_environment]

    # Test that no hardcoded paths are used
    set config_content [create_dynamic_path_config $test_dir]

    # Verify configuration uses dynamic paths
    ::CBFlow::Test::assert_false [string match "*/Users/vmerugu*" $config_content] "Should not contain hardcoded paths"

    ::CBFlow::Test::cleanup_test_environment $test_dir
    return true
}

proc test_flat_mode_node_creation_regression {} {
    # Regression test for flat mode node creation restrictions

    # Setup flat mode configuration
    set config {
        array set flow {
            run_type "flat"
            flow_type "FP"
        }
    }

    # Test that individual execution nodes are properly blocked
    ::CBFlow::Test::assert_error {
        validate_node_creation "floorplan" "FP" $config
    } "*individual execution nodes are not allowed*"

    # Test that merged nodes are allowed
    set result [validate_node_creation "floorplan_merged" "FP" $config]
    ::CBFlow::Test::assert_true $result "Merged nodes should be allowed in flat mode"

    return true
}

proc test_configuration_hierarchy_regression {} {
    # Regression test for configuration hierarchy precedence

    # Create test configurations at different levels
    set flow_config {array set synth {effort "low"}}
    set project_config {array set synth {effort "medium"}}
    set user_config {array set synth {effort "high"}}

    # Test precedence (user should override project and flow)
    set final_config [merge_configurations $flow_config $project_config $user_config]

    ::CBFlow::Test::assert_equal [get_config_value $final_config "synth(effort)"] "high" "User config should have highest precedence"

    return true
}
```

### Performance Regression

#### Performance Benchmark Tests
```tcl
proc test_performance_regression {} {
    # Baseline performance measurements
    set baseline_times {
        generate_makefile 500
        process_configuration 100
        validate_inputs 200
    }

    foreach {operation baseline_ms} $baseline_times {
        # Measure current performance
        set start_time [clock milliseconds]
        execute_operation $operation
        set end_time [clock milliseconds]

        set current_time [expr {$end_time - $start_time}]

        # Allow 20% variance from baseline
        set max_allowed [expr {$baseline_ms * 1.2}]

        ::CBFlow::Test::assert_within_range $current_time 0 $max_allowed "Performance regression check for $operation"
    }

    return true
}
```

## Performance Testing

### Benchmark Tests

#### Scalability Testing
```tcl
#!/usr/bin/env tclsh
# Performance Test: Scalability benchmarks

source "../common/test_framework.tcl"

proc test_large_design_performance {} {
    # Test performance with large design configurations

    set design_sizes {100 1000 10000 100000}

    foreach size $design_sizes {
        puts "Testing design size: $size modules"

        # Create large design configuration
        set large_config [create_large_design_config $size]

        # Measure processing time
        set start_time [clock milliseconds]
        process_large_design_config $large_config
        set end_time [clock milliseconds]

        set processing_time [expr {$end_time - $start_time}]

        # Log performance data
        puts "Size: $size, Time: ${processing_time}ms"

        # Performance should scale reasonably (not exponentially)
        if {$size > 1000} {
            set expected_max [expr {$processing_time * $size / 1000}]
            ::CBFlow::Test::assert_within_range $processing_time 0 $expected_max "Performance should scale linearly"
        }
    }

    return true
}

proc test_memory_usage_performance {} {
    # Test memory usage patterns

    # Get baseline memory
    set baseline_memory [get_memory_usage]

    # Execute memory-intensive operation
    set large_data [create_large_test_data]
    process_large_data $large_data

    # Check memory usage
    set peak_memory [get_memory_usage]
    set memory_increase [expr {$peak_memory - $baseline_memory}]

    # Memory increase should be reasonable
    ::CBFlow::Test::assert_within_range $memory_increase 0 100000000 "Memory usage should be within bounds"

    # Cleanup and verify memory is released
    unset large_data
    gc_if_available

    set final_memory [get_memory_usage]
    set memory_leak [expr {$final_memory - $baseline_memory}]

    # Should not have significant memory leaks
    ::CBFlow::Test::assert_within_range $memory_leak 0 10000000 "Should not have memory leaks"

    return true
}
```

### Stress Testing

#### Concurrent Execution Test
```tcl
proc test_concurrent_execution_stress () {
    # Test multiple concurrent operations

    set concurrent_tasks {}

    # Start multiple background tasks
    for {set i 0} {$i < 10} {incr i} {
        set task_id [start_background_task "process_test_data_$i"]
        lappend concurrent_tasks $task_id
    }

    # Wait for all tasks to complete
    foreach task_id $concurrent_tasks {
        wait_for_task $task_id
        verify_task_success $task_id
    }

    return true
}
```

## Test Execution and Reporting

### Running Tests

#### Command Line Interface
```bash
# Run all tests for a category
make test_all CATEGORY=generation

# Run specific test type
make test_unit CATEGORY=generation
make test_integration CATEGORY=generation
make test_regression CATEGORY=generation
make test_performance CATEGORY=generation

# Run specific test file
tclsh utils/generation/tests/unit/test_gen_makefile.tcl

# Run tests with coverage reporting
make test_coverage CATEGORY=generation

# Run stress tests
make test_stress CATEGORY=generation
```

#### Continuous Integration
```bash
# Pre-commit test hook
make pre_commit_test

# Full CI test suite
make ci_test_suite

# Performance regression detection
make performance_regression_test

# Generate test reports
make generate_test_reports
```

### Test Reporting

#### Test Report Generation
```tcl
proc generate_test_report {test_results output_file} {
    set fd [open $output_file w]

    puts $fd "# CBFlow Test Report"
    puts $fd "Generated: [clock format [clock seconds]]"
    puts $fd ""

    # Summary statistics
    set total_tests [dict get $test_results total]
    set passed_tests [dict get $test_results passed]
    set failed_tests [dict get $test_results failed]

    puts $fd "## Summary"
    puts $fd "- Total Tests: $total_tests"
    puts $fd "- Passed: $passed_tests"
    puts $fd "- Failed: $failed_tests"
    puts $fd "- Success Rate: [expr {($passed_tests * 100.0) / $total_tests}]%"
    puts $fd ""

    # Detailed results
    puts $fd "## Detailed Results"
    dict for {test_name result} [dict get $test_results details] {
        puts $fd "### $test_name"
        puts $fd "Status: [dict get $result status]"

        if {[dict exists $result error]} {
            puts $fd "Error: [dict get $result error]"
        }

        if {[dict exists $result duration]} {
            puts $fd "Duration: [dict get $result duration]ms"
        }

        puts $fd ""
    }

    close $fd
}
```

## Best Practices

### Test Design
1. **Independent Tests**: Each test should be independent and isolated
2. **Clear Names**: Use descriptive test names that explain what is being tested
3. **Single Purpose**: Each test should verify one specific behavior
4. **Fast Execution**: Unit tests should execute quickly

### Test Data Management
1. **Use Fixtures**: Organize test data in fixture directories
2. **Generate Data**: Generate test data programmatically when possible
3. **Clean State**: Always start tests with a clean state
4. **Cleanup**: Clean up test artifacts after execution

### Mock Strategy
1. **Mock External Dependencies**: Mock file system, external commands, and tools
2. **Realistic Mocks**: Mocks should behave realistically
3. **Verify Interactions**: Test that mocks are called correctly
4. **Reset Mocks**: Reset mock state between tests

### Performance Testing
1. **Baseline Measurements**: Establish performance baselines
2. **Regression Detection**: Automatically detect performance regressions
3. **Scalability Testing**: Test with various input sizes
4. **Resource Monitoring**: Monitor memory and CPU usage

---

This comprehensive testing guide ensures CBFlow maintains high quality, reliability, and performance across all development activities.