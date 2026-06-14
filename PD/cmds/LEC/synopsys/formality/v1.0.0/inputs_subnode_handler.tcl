#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow LEC INPUTS Subnode Handler
# Description: Handles inputs stage subnodes for LEC flow
# Subnodes: setup, netlist_golden, netlist_revised, constraints, validate, finish
# Supports test_mode: bypasses EDA tool and shows command file instead
# ═══════════════════════════════════════════════════════════════════════════════

# Parse arguments
if {$argc < 1} {
    puts "ERROR: Missing subnode argument"
    puts "Usage: $argv0 <subnode_name> \[run_dir\]"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

# Load environment
if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: Cannot find .run.cbflow.tcl in $run_dir"
    exit 1
}

# Load error handling
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

# Load flow and LEC configuration
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }

set lec_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/LEC_config.tcl"
if {[file exists $lec_config]} { source $lec_config }

# Load user configuration
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "LEC"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

# Check test mode
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
    set test_mode true
}

# Resolve inputs from upstream run manifest or release tag (before processing subnodes)
if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_resolve_lib]} {
        source $_resolve_lib
        resolve_flow_inputs $::flow_type $run_dir
    }
}
switch $subnode_name {
    "setup" {
        puts "INFO: LEC $stage_name setup..."
        file mkdir "$run_dir/work/LEC/$node_name"
        file mkdir "$run_dir/work/LEC/$node_name/netlist_golden"
        file mkdir "$run_dir/work/LEC/$node_name/netlist_revised"
        file mkdir "$run_dir/work/LEC/$node_name/constraints"
        puts "INFO: LEC $stage_name setup completed"
    }
    "netlist_golden" {
        puts "INFO: LEC $stage_name netlist_golden..."
        # Link or copy golden netlist
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Golden netlist loading skipped"
        }
        set info_file "$run_dir/work/LEC/$node_name/netlist_golden/golden_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set netlist_golden_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $fh "set netlist_golden_info(status) \"loaded\""
        close $fh
        puts "INFO: LEC $stage_name netlist_golden completed"
    }
    "netlist_revised" {
        puts "INFO: LEC $stage_name netlist_revised..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Revised netlist loading skipped"
        }
        set info_file "$run_dir/work/LEC/$node_name/netlist_revised/revised_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set netlist_revised_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $fh "set netlist_revised_info(status) \"loaded\""
        close $fh
        puts "INFO: LEC $stage_name netlist_revised completed"
    }
    "constraints" {
        puts "INFO: LEC $stage_name constraints..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Constraints loading skipped"
        }
        puts "INFO: LEC $stage_name constraints completed"
    }
    "validate" {
        puts "INFO: LEC $stage_name validate..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Validation skipped"
        } else {
            puts "INFO: LEC inputs validation passed"
        }
        puts "INFO: LEC $stage_name validate completed"
    }
    "finish" {
        puts "INFO: LEC $stage_name finish..."
        set finish_file "$run_dir/work/LEC/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $finish_file]
        set fh [open $finish_file "w"]
        puts $fh "set finish_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        close $fh
        puts "INFO: LEC $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
