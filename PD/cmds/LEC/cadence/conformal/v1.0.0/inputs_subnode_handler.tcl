#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Conformal — Inputs Subnode Handler
# Handles: netlist_golden1, netlist_revised1, constraints1 input stages
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir    $::env(CBFLOW_RUN_DIR)
set node_name  $::env(CBFLOW_NODE_NAME)
set subnode    $::env(CBFLOW_SUBNODE)
set flow_type  "LEC"

source "$run_dir/.run.cbflow.tcl"

# Determine stage base (netlist_golden, netlist_revised, constraints)
set stage_base [regsub {\d+$} $node_name ""]

set work_dir "$run_dir/work/$flow_type/$node_name"
set test_mode false
catch { set test_mode [expr {$::flow(test_mode) eq "true"}] }

switch -- $subnode {
    "setup" {
        file mkdir "$work_dir/run"
        file mkdir "$work_dir/results"
        puts "INFO: $node_name setup completed"
    }
    "run" - $stage_base {
        # Validate input file exists
        set _var_map {
            netlist_golden "lec(input,netlist_golden)"
            netlist_revised "lec(input,netlist_revised)"
            constraints "lec(input,constraints)"
        }
        foreach {_stage _var} $_var_map {
            if {$stage_base eq $_stage} {
                if {[info exists ::$_var]} {
                    set _path [set ::$_var]
                    if {$_path ne "" && [file exists $_path]} {
                        puts "INFO: $node_name: $_var = $_path (OK)"
                    } elseif {$test_mode} {
                        puts "INFO: $node_name: $_var = $_path (test_mode — skipping validation)"
                    } else {
                        puts "WARNING: $node_name: file not found: $_path"
                    }
                }
            }
        }
        puts "INFO: $node_name $subnode completed"
    }
    "validate" {
        puts "INFO: $node_name validate completed"
    }
    "finish" {
        set ts "$work_dir/run/${stage_base}_finish.timestamp"
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
