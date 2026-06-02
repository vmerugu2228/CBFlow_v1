#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Conformal — Release Data Subnode Handler
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir    $::env(CBFLOW_RUN_DIR)
set node_name  $::env(CBFLOW_NODE_NAME)
set subnode    $::env(CBFLOW_SUBNODE)
set flow_type  "LEC"

source "$run_dir/.run.cbflow.tcl"

set work_dir "$run_dir/work/$flow_type/$node_name"

set test_mode false
catch { set test_mode [expr {$::flow(test_mode) eq "true"}] }
if {!$test_mode} {
    catch { set test_mode [expr {$::env(CBFLOW_TEST_MODE) eq "true"}] }
}
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
        file mkdir "$work_dir/results"
        puts "INFO: $node_name setup completed"
    }
    "run" {
        set compare_rpt_dir "$run_dir/work/$flow_type/compare1/reports"
        set rel_dir "$work_dir/results"

        foreach rpt {comparison_summary.rpt equivalence_analysis.rpt status.rpt PASSED FAILED} {
            set src "$compare_rpt_dir/$rpt"
            if {[file exists $src]} {
                file copy -force $src "$rel_dir/$rpt"
            }
        }
        puts "INFO: $node_name release data prepared"
    }
    "validate" {
        set rel_dir "$work_dir/results"
        if {[file exists "$rel_dir/comparison_summary.rpt"]} {
            puts "INFO: $node_name release validation passed"
        } elseif {$test_mode} {
            puts "INFO: $node_name release validation skipped (test_mode)"
        } else {
            puts "ERROR: Missing comparison_summary.rpt in release"
            exit 1
        }
    }
    "finish" {
        set ts "$work_dir/run/release_data_finish.timestamp"
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
