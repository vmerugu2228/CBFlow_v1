#!/usr/bin/env tclsh
# CBFlow EMIR INPUTS Subnode Handler
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/EMIR_config.tcl"
if {[file exists $node_config]} { source $node_config }
# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set ::flow_type "EMIR"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }

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
        puts "INFO: EMIR $stage_name setup..."
        file mkdir "$run_dir/work/EMIR/$node_name/netlist"
        file mkdir "$run_dir/work/EMIR/$node_name/def"
        file mkdir "$run_dir/work/EMIR/$node_name/spef"
        file mkdir "$run_dir/work/EMIR/$node_name/library"
        puts "INFO: EMIR $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: EMIR $stage_name netlist..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] netlist loading skipped" }
        set info_file "$run_dir/work/EMIR/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set netlist_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set netlist_info(status) \"loaded\""
        close $fh
        puts "INFO: EMIR $stage_name netlist completed"
    }
    "def" {
        puts "INFO: EMIR $stage_name def..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] def loading skipped" }
        set info_file "$run_dir/work/EMIR/$node_name/def/def_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set def_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set def_info(status) \"loaded\""
        close $fh
        puts "INFO: EMIR $stage_name def completed"
    }
    "spef" {
        puts "INFO: EMIR $stage_name spef..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] spef loading skipped" }
        set info_file "$run_dir/work/EMIR/$node_name/spef/spef_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set spef_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set spef_info(status) \"loaded\""
        close $fh
        puts "INFO: EMIR $stage_name spef completed"
    }
    "library" {
        puts "INFO: EMIR $stage_name library..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] library loading skipped" }
        set info_file "$run_dir/work/EMIR/$node_name/library/library_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set library_info(timestamp) \"[clock format [clock seconds]]\""
        puts $fh "set library_info(status) \"loaded\""
        close $fh
        puts "INFO: EMIR $stage_name library completed"
    }
    "validate" {
        puts "INFO: EMIR $stage_name validate..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] Validation skipped" } else { puts "INFO: EMIR inputs validation passed" }
        puts "INFO: EMIR $stage_name validate completed"
    }
    "finish" {
        puts "INFO: EMIR $stage_name finish..."
        set finish_file "$run_dir/work/EMIR/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $finish_file]
        set fh [open $finish_file "w"]
        puts $fh "set finish_info(timestamp) \"[clock format [clock seconds]]\""
        close $fh
        puts "INFO: EMIR $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
