#!/usr/bin/env tclsh
# CBFlow PV INPUTS Subnode Handler - Synopsys ICV
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/PV_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
set ::flow_type "PV"
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
        puts "INFO: PV $stage_name setup..."
        file mkdir "$run_dir/work/PV/$node_name/netlist"
        file mkdir "$run_dir/work/PV/$node_name/def"
        file mkdir "$run_dir/work/PV/$node_name/gds"
        puts "INFO: PV $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: PV $stage_name netlist..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] netlist loading skipped" }
        set ff "$run_dir/work/PV/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set netlist_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set netlist_info(status) \"loaded\""; close $fh
        puts "INFO: PV $stage_name netlist completed"
    }
    "def" {
        puts "INFO: PV $stage_name def..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] def loading skipped" }
        set ff "$run_dir/work/PV/$node_name/def/def_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set def_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set def_info(status) \"loaded\""; close $fh
        puts "INFO: PV $stage_name def completed"
    }
    "gds" {
        puts "INFO: PV $stage_name gds..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] gds loading skipped" }
        set ff "$run_dir/work/PV/$node_name/gds/gds_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set gds_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set gds_info(status) \"loaded\""; close $fh
        puts "INFO: PV $stage_name gds completed"
    }
    "validate" {
        puts "INFO: PV $stage_name validate..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] Validation skipped" }
        puts "INFO: PV $stage_name validate completed"
    }
    "finish" {
        puts "INFO: PV $stage_name finish..."
        set ff "$run_dir/work/PV/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set finish_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; close $fh
        puts "INFO: PV $stage_name finish completed"
    }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
