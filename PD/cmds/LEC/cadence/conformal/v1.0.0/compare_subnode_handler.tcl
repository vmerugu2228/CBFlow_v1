#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Conformal — Compare Subnode Handler
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir    $::env(CBFLOW_RUN_DIR)
set node_name  $::env(CBFLOW_NODE_NAME)
set subnode    $::env(CBFLOW_SUBNODE)
set flow_type  "LEC"

source "$run_dir/.run.cbflow.tcl"

set work_dir "$run_dir/work/$flow_type/$node_name"
set cmd_dir  "$::env(FLOW_DIR)/cmds/$flow_type/cadence/conformal/$::env(FLOW_CONFIG_VERSION)"
set cmd_file "$cmd_dir/compare_conformal.tcl"

set test_mode false
catch { set test_mode [expr {$::flow(test_mode) eq "true"}] }
if {!$test_mode} {
    catch { set test_mode [expr {$::env(CBFLOW_TEST_MODE) eq "true"}] }
}
# Also check user_config for test_mode
if {!$test_mode} {
    set _uc "$run_dir/setup/user_config.tcl"
    if {[file exists $_uc]} {
        set _fh [open $_uc r]; set _c [read $_fh]; close $_fh
        if {[string match "*test_mode*true*" $_c]} { set test_mode true }
    }
}

switch -- $subnode {
    "setup" {
        file mkdir "$work_dir/run"
        file mkdir "$work_dir/reports"
        file mkdir "$work_dir/results"

        # Generate config.tcl and setup.tcl for the compare stage
        source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $::flow_type $node_name ${node_name}_default $run_dir}
        }
    }
        puts "INFO: $node_name setup completed"
    }
    "run" {
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] LEC Conformal comparison"
            # Create mock reports
            file mkdir "$work_dir/reports"
            set fh [open "$work_dir/reports/comparison_summary.rpt" "w"]
            puts $fh "Conformal LEC Comparison Summary"
            puts $fh "Status: SUCCEEDED"
            puts $fh "Equivalent points: 12345"
            puts $fh "Non-equivalent points: 0"
            puts $fh "PASSED"
            close $fh
            set fh [open "$work_dir/reports/PASSED" "w"]
            puts $fh "LEC PASSED — [clock format [clock seconds]]"
            close $fh
            puts "INFO: \[TEST MODE\] LEC comparison completed — PASSED"
        } else {
            if {![file exists $cmd_file]} {
                puts "ERROR: Command file not found: $cmd_file"
                exit 1
            }
            set _tool "lec"
            set _log "$work_dir/run/${node_name}_compare.log"
            catch { if {[info exists lsf(tool_shell,conformal)]} { set _tool $lsf(tool_shell,conformal) } }
            puts "INFO: Invoking Conformal: $_tool -dofile $cmd_file"
            if {[catch {exec $_tool -dofile $cmd_file -logfile $_log} result]} {
                puts "ERROR: Conformal comparison failed: $result"
                exit 1
            }
            puts "INFO: $node_name comparison completed"
        }
    }
    "validate" {
        set rpt "$work_dir/reports/comparison_summary.rpt"
        if {[file exists $rpt]} {
            set fh [open $rpt "r"]
            set content [read $fh]
            close $fh
            if {[string match "*SUCCEEDED*" $content] || [string match "*PASSED*" $content]} {
                puts "INFO: LEC validation: PASSED"
            } else {
                puts "ERROR: LEC validation: FAILED — designs not equivalent"
                exit 1
            }
        } else {
            if {!$test_mode} {
                puts "ERROR: Missing comparison report: $rpt"
                exit 1
            }
        }
    }
    "finish" {
        set ts "$work_dir/run/compare_finish.timestamp"
        set fh [open $ts "w"]
        puts $fh "[clock format [clock seconds]]"
        close $fh
        puts "INFO: $node_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode"
        exit 1
    }
}
