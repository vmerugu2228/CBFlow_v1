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
    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $::flow_type $node_name ${node_name}_default $run_dir}
        }
    }
        puts "INFO: $node_name setup completed"
    }
    "run" -
    "netlist_golden" -
    "netlist_revised" -
    "constraints" -
    $stage_base {
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
        puts $fh "[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
        close $fh
        puts "INFO: $node_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode"
        exit 1
    }
}
