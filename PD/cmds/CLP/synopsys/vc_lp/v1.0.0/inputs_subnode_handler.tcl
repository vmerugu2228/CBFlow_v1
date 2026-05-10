#!/usr/bin/env tclsh
# CBFlow CLP INPUTS Subnode Handler - Synopsys VC_LP
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/CLP_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
set ::flow_type "CLP"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: CLP $stage_name setup..."
        file mkdir "$run_dir/work/CLP/$node_name/netlist"
        file mkdir "$run_dir/work/CLP/$node_name/upf"
        file mkdir "$run_dir/work/CLP/$node_name/power_spec"
        puts "INFO: CLP $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: CLP $stage_name netlist..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] netlist loading skipped" }
        set ff "$run_dir/work/CLP/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set netlist_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set netlist_info(status) \"loaded\""; close $fh
        puts "INFO: CLP $stage_name netlist completed"
    }
    "upf" {
        puts "INFO: CLP $stage_name upf..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] upf loading skipped" }
        set ff "$run_dir/work/CLP/$node_name/upf/upf_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set upf_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set upf_info(status) \"loaded\""; close $fh
        puts "INFO: CLP $stage_name upf completed"
    }
    "power_spec" {
        puts "INFO: CLP $stage_name power_spec..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] power_spec loading skipped" }
        set ff "$run_dir/work/CLP/$node_name/power_spec/power_spec_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set power_spec_info(timestamp) \"[clock format [clock seconds]]\""; puts $fh "set power_spec_info(status) \"loaded\""; close $fh
        puts "INFO: CLP $stage_name power_spec completed"
    }
    "validate" {
        puts "INFO: CLP $stage_name validate..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] Validation skipped" }
        puts "INFO: CLP $stage_name validate completed"
    }
    "finish" {
        puts "INFO: CLP $stage_name finish..."
        set ff "$run_dir/work/CLP/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set finish_info(timestamp) \"[clock format [clock seconds]]\""; close $fh
        puts "INFO: CLP $stage_name finish completed"
    }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
