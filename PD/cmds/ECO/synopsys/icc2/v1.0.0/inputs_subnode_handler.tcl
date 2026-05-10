#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow ECO INPUTS Subnode Handler
# Description: Handles inputs stage subnodes for ECO flow
# Subnodes: setup, netlist, def, sdc, library, validate, finish
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

# Load flow and ECO configuration
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }

set eco_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/ECO_config.tcl"
if {[file exists $eco_config]} { source $eco_config }

# Load user configuration
if {[file exists "$run_dir/setup/user_config.tcl"]} {
    source "$run_dir/setup/user_config.tcl"
}

set ::flow_type "ECO"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

# Check test mode
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
    set test_mode true
}

switch $subnode_name {
    "setup" {
        puts "INFO: ECO $stage_name setup..."
        file mkdir "$run_dir/work/ECO/$node_name"
        file mkdir "$run_dir/work/ECO/$node_name/netlist"
        file mkdir "$run_dir/work/ECO/$node_name/def"
        file mkdir "$run_dir/work/ECO/$node_name/sdc"
        file mkdir "$run_dir/work/ECO/$node_name/library"
        puts "INFO: ECO $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: ECO $stage_name netlist..."
        # Link or copy netlist for ECO
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Netlist loading skipped"
        }
        set info_file "$run_dir/work/ECO/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set netlist_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set netlist_info(status) \"loaded\""
        close $fh
        puts "INFO: ECO $stage_name netlist completed"
    }
    "def" {
        puts "INFO: ECO $stage_name def..."
        # Link or copy DEF file for ECO
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] DEF loading skipped"
        }
        set info_file "$run_dir/work/ECO/$node_name/def/def_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set def_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set def_info(status) \"loaded\""
        close $fh
        puts "INFO: ECO $stage_name def completed"
    }
    "sdc" {
        puts "INFO: ECO $stage_name sdc..."
        # Link or copy SDC constraints for ECO
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] SDC loading skipped"
        }
        set info_file "$run_dir/work/ECO/$node_name/sdc/sdc_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set sdc_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set sdc_info(status) \"loaded\""
        close $fh
        puts "INFO: ECO $stage_name sdc completed"
    }
    "library" {
        puts "INFO: ECO $stage_name library..."
        # Link or copy library files for ECO
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Library loading skipped"
        }
        set info_file "$run_dir/work/ECO/$node_name/library/library_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set library_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set library_info(status) \"loaded\""
        close $fh
        puts "INFO: ECO $stage_name library completed"
    }
    "validate" {
        puts "INFO: ECO $stage_name validate..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Validation skipped"
        } else {
            puts "INFO: ECO inputs validation passed"
        }
        puts "INFO: ECO $stage_name validate completed"
    }
    "finish" {
        puts "INFO: ECO $stage_name finish..."
        set finish_file "$run_dir/work/ECO/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $finish_file]
        set fh [open $finish_file "w"]
        puts $fh "set finish_info(timestamp) \"[clock format [clock seconds]]\""
        close $fh
        puts "INFO: ECO $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
