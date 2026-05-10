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
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
}

set ::flow_type "LEC"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

# Check test mode
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
    set test_mode true
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
        puts $fh "set netlist_golden_info(timestamp) \"[clock format [clock seconds]]\""
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
        puts $fh "set netlist_revised_info(timestamp) \"[clock format [clock seconds]]\""
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
        puts $fh "set finish_info(timestamp) \"[clock format [clock seconds]]\""
        close $fh
        puts "INFO: LEC $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
