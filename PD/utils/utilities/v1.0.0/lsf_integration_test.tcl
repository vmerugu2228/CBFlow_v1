#!/usr/bin/env tclsh

# LSF Integration Test Suite
# Comprehensive test of LSF management system integration with CBFlow

# Source required modules
source [file join [file dirname [info script]] "lsf_auto_integration.tcl"]
source [file join [file dirname [info script]] "lsf_cost_manager.tcl"]
source [file join [file dirname [info script]] "error_utils.tcl"]

namespace eval ::lsf::test {
    variable test_results [list]
    variable test_count 0
    variable passed_tests 0
}

# Test framework functions
proc ::lsf::test::assert {condition message} {
    variable test_results
    variable test_count
    variable passed_tests

    incr test_count

    if {$condition} {
        incr passed_tests
        lappend test_results [dict create \
            test_id $test_count \
            status "PASS" \
            message $message \
        ]
        puts "✓ TEST $test_count PASSED: $message"
    } else {
        lappend test_results [dict create \
            test_id $test_count \
            status "FAIL" \
            message $message \
        ]
        puts "✗ TEST $test_count FAILED: $message"
    }
}

proc ::lsf::test::run_test {test_name test_proc} {
    puts "\n=== Running Test: $test_name ==="

    if {[catch {$test_proc} error]} {
        assert false "$test_name - Exception: $error"
    }
}

# Test LSF configuration loading
proc ::lsf::test::test_lsf_configuration {} {
    # Test 1: Check if LSF configuration exists
    set config_dirs [list \
        "../../../config/flow/v1.0.0" \
        "../../config/flow/v1.0.0" \
        "../config/flow/v1.0.0" \
        "config/flow/v1.0.0" \
    ]

    set config_found false
    foreach config_dir $config_dirs {
        set lsf_config [file join $config_dir "lsf_config.tcl"]
        if {[file exists $lsf_config]} {
            set config_found true
            break
        }
    }

    assert $config_found "LSF configuration file exists"

    # Test 2: Check if configuration can be loaded
    if {$config_found} {
        set load_success [catch {source $lsf_config} error]
        assert [expr {$load_success == 0}] "LSF configuration loads without errors"

        # Test 3: Check if lsf array exists
        if {$load_success == 0} {
            assert [info exists ::lsf] "LSF configuration array exists"

            # Test 4: Check queue types
            if {[info exists ::lsf]} {
                set queue_types [list S M L XL ultra]
                set all_queues_exist true

                foreach queue_type $queue_types {
                    if {![info exists ::lsf(queue_types,$queue_type,memory)]} {
                        set all_queues_exist false
                        break
                    }
                }

                assert $all_queues_exist "All required queue types (S, M, L, XL, ultra) are configured"
            }
        }
    }
}

# Test LSF utilities
proc ::lsf::test::test_lsf_utilities {} {
    # Test 1: Check if LSF utilities can be loaded
    set utils_file [file join [file dirname [info script]] "lsf_utils.tcl"]
    set load_success [catch {source $utils_file} error]
    assert [expr {$load_success == 0}] "LSF utilities load successfully"

    if {$load_success == 0} {
        # Test 2: Check if namespace exists
        assert [namespace exists ::lsf::utils] "LSF utilities namespace exists"

        # Test 3: Check if key procedures exist
        set required_procs [list \
            "::lsf::utils::initialize" \
            "::lsf::utils::submit_lsf_job" \
            "::lsf::utils::get_job_status" \
            "::lsf::utils::cancel_job" \
        ]

        set all_procs_exist true
        foreach proc_name $required_procs {
            if {[info procs $proc_name] eq ""} {
                set all_procs_exist false
                break
            }
        }

        assert $all_procs_exist "All required LSF utility procedures exist"
    }
}

# Test dynamic queue management
proc ::lsf::test::test_dynamic_queues {} {
    # Test 1: Check if dynamic queue module loads
    set dynamic_file [file join [file dirname [info script]] "lsf_dynamic_queues.tcl"]
    set load_success [catch {source $dynamic_file} error]
    assert [expr {$load_success == 0}] "Dynamic queue module loads successfully"

    if {$load_success == 0} {
        # Test 2: Check namespace
        assert [namespace exists ::lsf::dynamic] "Dynamic queue namespace exists"

        # Test 3: Test resource prediction (heuristic mode)
        set test_characteristics [dict create \
            gate_count 500000 \
            design_size "medium" \
            hierarchy_depth 5 \
        ]

        set prediction_result [::lsf::dynamic::get_heuristic_resource_prediction "SYNTH" "synthesis" $test_characteristics]

        assert [dict exists $prediction_result "memory_gb"] "Resource prediction returns memory estimate"
        assert [dict exists $prediction_result "cpu_count"] "Resource prediction returns CPU estimate"
        assert [dict exists $prediction_result "predicted_queue"] "Resource prediction returns queue recommendation"

        # Test 4: Test queue spec calculation
        set queue_spec [::lsf::dynamic::calculate_optimal_queue_spec $prediction_result]

        assert [dict exists $queue_spec "memory"] "Queue specification includes memory"
        assert [dict exists $queue_spec "cpu"] "Queue specification includes CPU count"
        assert [dict exists $queue_spec "runtime_limit"] "Queue specification includes runtime limit"
    }
}

# Test ML analytics
proc ::lsf::test::test_ml_analytics {} {
    # Test 1: Check if ML analytics script exists
    set ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_ml_analytics.py"]
    assert [file exists $ml_script] "ML analytics script exists"

    # Test 2: Check if advanced ML script exists
    set advanced_ml_script [file join [file dirname [info script]] "../ml_analytics/v1.0.0/lsf_advanced_ml.py"]
    assert [file exists $advanced_ml_script] "Advanced ML analytics script exists"

    # Test 3: Check if Python can execute the script (basic syntax check)
    if {[file exists $ml_script]} {
        set python_check [catch {exec python3 -m py_compile $ml_script} error]
        assert [expr {$python_check == 0}] "ML analytics script has valid Python syntax"
    }

    if {[file exists $advanced_ml_script]} {
        set python_check [catch {exec python3 -m py_compile $advanced_ml_script} error]
        assert [expr {$python_check == 0}] "Advanced ML analytics script has valid Python syntax"
    }
}

# Test cost management
proc ::lsf::test::test_cost_management {} {
    # Test 1: Check if cost manager loads
    set cost_file [file join [file dirname [info script]] "lsf_cost_manager.tcl"]
    set load_success [catch {source $cost_file} error]
    assert [expr {$load_success == 0}] "Cost manager loads successfully"

    if {$load_success == 0} {
        # Test 2: Check namespace
        assert [namespace exists ::lsf::cost] "Cost management namespace exists"

        # Test 3: Test cost calculation
        set test_job_data [dict create \
            memory_gb 16 \
            cpu_count 8 \
            runtime_seconds 3600 \
        ]

        set cost_result [::lsf::cost::calculate_job_cost $test_job_data]

        assert [dict exists $cost_result "total_cost"] "Cost calculation returns total cost"
        assert [dict exists $cost_result "memory_cost"] "Cost calculation returns memory cost"
        assert [dict exists $cost_result "cpu_cost"] "Cost calculation returns CPU cost"

        set total_cost [dict get $cost_result "total_cost"]
        assert [expr {$total_cost > 0}] "Calculated cost is positive value"

        # Test 4: Test budget management
        ::lsf::cost::set_budget "TEST_FLOW" 100.0 "monthly"
        set budget_status [::lsf::cost::get_budget_status "TEST_FLOW"]

        assert [dict exists $budget_status "allocated_budget"] "Budget status includes allocated budget"
        assert [dict exists $budget_status "current_spend"] "Budget status includes current spend"
        assert [dict exists $budget_status "budget_utilization"] "Budget status includes utilization"
    }
}

# Test integration components
proc ::lsf::test::test_integration {} {
    # Test 1: Check if integration module loads
    set integration_file [file join [file dirname [info script]] "lsf_integration.tcl"]
    set load_success [catch {source $integration_file} error]
    assert [expr {$load_success == 0}] "LSF integration module loads successfully"

    if {$load_success == 0} {
        # Test 2: Check namespace
        assert [namespace exists ::lsf::integration] "Integration namespace exists"

        # Test 3: Test context detection
        set context [::lsf::integration::get_execution_context]

        assert [dict exists $context "working_directory"] "Context detection returns working directory"
        assert [dict exists $context "flow_type"] "Context detection returns flow type"

        # Test 4: Test LSF recommendation
        set test_context [dict create \
            flow_type "SYNTH" \
            stage_name "synthesis" \
            design_characteristics [dict create gate_count 100000] \
        ]

        set recommendation [::lsf::integration::get_default_lsf_queue_for_context $test_context]
        assert [expr {$recommendation ne ""}] "LSF recommendation returns valid queue"

        # Test 5: Test integration status
        set status [::lsf::integration::get_integration_status]
        assert [dict exists $status "lsf_enabled"] "Integration status includes LSF enabled flag"
    }
}

# Test optimizer
proc ::lsf::test::test_optimizer {} {
    # Test 1: Check if optimizer loads
    set optimizer_file [file join [file dirname [info script]] "lsf_optimizer.tcl"]
    set load_success [catch {source $optimizer_file} error]
    assert [expr {$load_success == 0}] "LSF optimizer loads successfully"

    if {$load_success == 0} {
        # Test 2: Check namespace
        assert [namespace exists ::lsf::optimizer] "Optimizer namespace exists"

        # Test 3: Test queue recommendation logic
        set test_memory 32.0
        set test_cpu_util 0.8

        set queue_rec [::lsf::optimizer::determine_optimal_queue $test_memory $test_cpu_util]
        assert [expr {$queue_rec ne ""}] "Optimizer returns valid queue recommendation"

        # Verify it's a valid queue type
        set valid_queues [list S M L XL ultra]
        assert [expr {[lsearch $valid_queues $queue_rec] >= 0}] "Recommended queue is valid queue type"
    }
}

# Test auto-integration
proc ::lsf::test::test_auto_integration {} {
    # Test 1: Check if auto-integration loads
    set auto_file [file join [file dirname [info script]] "lsf_auto_integration.tcl"]
    set load_success [catch {source $auto_file} error]
    assert [expr {$load_success == 0}] "Auto-integration module loads successfully"

    # Test 2: The module should have executed and provided feedback
    # This is more of a smoke test to ensure no errors occur during loading
}

# Test project configuration integration
proc ::lsf::test::test_project_integration {} {
    # Test 1: Check if project config has LSF settings
    set project_config [file join [file dirname [info script]] "../../../config/project/phoenix/v1.0.0/phoenix_config.tcl"]

    if {[file exists $project_config]} {
        assert true "Project configuration file exists"

        # Test 2: Try to load and check for LSF settings
        if {[catch {source $project_config} error] == 0} {
            # Check if project array has LSF configuration
            if {[info exists ::project]} {
                set has_lsf_config false

                # Look for any LSF-related configuration
                foreach key [array names ::project] {
                    if {[string match "*lsf*" $key]} {
                        set has_lsf_config true
                        break
                    }
                }

                assert $has_lsf_config "Project configuration includes LSF settings"
            }
        }
    } else {
        assert false "Project configuration file not found"
    }
}

# Run comprehensive test suite
proc ::lsf::test::run_all_tests {} {
    variable test_results
    variable test_count
    variable passed_tests

    puts "=========================================="
    puts "CBFlow LSF Integration Test Suite"
    puts "=========================================="

    # Reset test counters
    set test_results [list]
    set test_count 0
    set passed_tests 0

    # Run all tests
    run_test "LSF Configuration" ::lsf::test::test_lsf_configuration
    run_test "LSF Utilities" ::lsf::test::test_lsf_utilities
    run_test "Dynamic Queues" ::lsf::test::test_dynamic_queues
    run_test "ML Analytics" ::lsf::test::test_ml_analytics
    run_test "Cost Management" ::lsf::test::test_cost_management
    run_test "Integration Components" ::lsf::test::test_integration
    run_test "Optimizer" ::lsf::test::test_optimizer
    run_test "Auto-Integration" ::lsf::test::test_auto_integration
    run_test "Project Integration" ::lsf::test::test_project_integration

    # Print summary
    puts "\n=========================================="
    puts "Test Summary"
    puts "=========================================="
    puts "Total Tests: $test_count"
    puts "Passed: $passed_tests"
    puts "Failed: [expr {$test_count - $passed_tests}]"

    set success_rate [expr {$test_count > 0 ? double($passed_tests) / $test_count * 100.0 : 0}]
    puts "Success Rate: [format "%.1f" $success_rate]%"

    if {$passed_tests == $test_count} {
        puts "\n✓ ALL TESTS PASSED - LSF Integration is working correctly!"
        return true
    } else {
        puts "\n✗ Some tests failed - Please review the output above"
        return false
    }
}

# Demonstration function
proc ::lsf::test::run_demonstration {} {
    puts "\n=========================================="
    puts "CBFlow LSF Integration Demonstration"
    puts "=========================================="

    # Demo 1: Resource optimization
    puts "\n--- Demo 1: Resource Optimization ---"
    set demo_characteristics [dict create \
        gate_count 750000 \
        design_size "large" \
        hierarchy_depth 8 \
        net_count 300000 \
    ]

    if {[namespace exists ::lsf::cost]} {
        set optimization [::lsf::cost::optimize_resources "SYNTH" "synthesis" $demo_characteristics]
        puts "Resource Optimization Result:"
        dict for {key value} $optimization {
            puts "  $key: $value"
        }
    }

    # Demo 2: Cost calculation
    puts "\n--- Demo 2: Cost Calculation ---"
    set demo_job [dict create \
        memory_gb 32 \
        cpu_count 16 \
        runtime_seconds 7200 \
        flow_type "PNR" \
        stage_name "route" \
    ]

    if {[namespace exists ::lsf::cost]} {
        set cost_breakdown [::lsf::cost::calculate_job_cost $demo_job]
        puts "Cost Breakdown:"
        dict for {key value} $cost_breakdown {
            puts "  $key: $[format "%.2f" $value]"
        }
    }

    # Demo 3: Dynamic queue creation simulation
    puts "\n--- Demo 3: Dynamic Queue Recommendation ---"
    if {[namespace exists ::lsf::dynamic]} {
        set queue_prediction [::lsf::dynamic::get_heuristic_resource_prediction "PNR" "route" $demo_characteristics]
        puts "Queue Recommendation:"
        dict for {key value} $queue_prediction {
            puts "  $key: $value"
        }
    }

    puts "\n--- Demonstration Complete ---"
}

# Main execution
if {[info exists argv0] && [file tail $argv0] eq "lsf_integration_test.tcl"} {
    # Script is being run directly
    if {[llength $argv] > 0 && [lindex $argv 0] eq "demo"} {
        ::lsf::test::run_demonstration
    } else {
        set test_success [::lsf::test::run_all_tests]
        exit [expr {$test_success ? 0 : 1}]
    }
}