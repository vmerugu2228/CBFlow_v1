#!/usr/bin/env tclsh
# CBFlow STA INPUTS Subnode Handler - Synopsys PT
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/STA_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
set ::flow_type "STA"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: STA $stage_name setup..."
        file mkdir "$run_dir/work/STA/$node_name/netlist"
        file mkdir "$run_dir/work/STA/$node_name/sdc"
        file mkdir "$run_dir/work/STA/$node_name/spef"
        file mkdir "$run_dir/work/STA/$node_name/library"
        puts "INFO: STA $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: STA $stage_name netlist..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] netlist loading skipped" }
        set ff "$run_dir/work/STA/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set netlist_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set netlist_info(status) \"loaded\""; close $fh
        puts "INFO: STA $stage_name netlist completed"
    }
    "sdc" {
        puts "INFO: STA $stage_name sdc..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] sdc loading skipped" }
        set ff "$run_dir/work/STA/$node_name/sdc/sdc_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set sdc_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set sdc_info(status) \"loaded\""; close $fh
        puts "INFO: STA $stage_name sdc completed"
    }
    "spef" {
        puts "INFO: STA $stage_name spef..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] spef loading skipped" }
        set ff "$run_dir/work/STA/$node_name/spef/spef_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set spef_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set spef_info(status) \"loaded\""; close $fh
        puts "INFO: STA $stage_name spef completed"
    }
    "library" {
        puts "INFO: STA $stage_name library..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] library loading skipped" }
        set ff "$run_dir/work/STA/$node_name/library/library_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set library_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set library_info(status) \"loaded\""; close $fh
        puts "INFO: STA $stage_name library completed"
    }
    "validate" {
        puts "INFO: STA $stage_name validate..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] Validation skipped" }
        puts "INFO: STA $stage_name validate completed"
    }
    "finish" {
        puts "INFO: STA $stage_name finish..."
        set ff "$run_dir/work/STA/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set finish_info(timestamp) \"[clock format [clock seconds]]\""; close $fh
        puts "INFO: STA $stage_name finish completed"
    }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
