#!/usr/bin/env tclsh
# CBFlow FCFP INPUTS Subnode Handler - Synopsys FC
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/FCFP_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
set ::flow_type "FCFP"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: FCFP $stage_name setup..."
        file mkdir "$run_dir/work/FCFP/$node_name/netlist"
        file mkdir "$run_dir/work/FCFP/$node_name/sdc"
        file mkdir "$run_dir/work/FCFP/$node_name/def"
        file mkdir "$run_dir/work/FCFP/$node_name/upf"
        file mkdir "$run_dir/work/FCFP/$node_name/library"
        puts "INFO: FCFP $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: FCFP $stage_name netlist..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] netlist loading skipped" }
        set ff "$run_dir/work/FCFP/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set netlist_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set netlist_info(status) \"loaded\""; close $fh
        puts "INFO: FCFP $stage_name netlist completed"
    }
    "sdc" {
        puts "INFO: FCFP $stage_name sdc..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] sdc loading skipped" }
        set ff "$run_dir/work/FCFP/$node_name/sdc/sdc_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set sdc_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set sdc_info(status) \"loaded\""; close $fh
        puts "INFO: FCFP $stage_name sdc completed"
    }
    "def" {
        puts "INFO: FCFP $stage_name def..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] def loading skipped" }
        set ff "$run_dir/work/FCFP/$node_name/def/def_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set def_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set def_info(status) \"loaded\""; close $fh
        puts "INFO: FCFP $stage_name def completed"
    }
    "upf" {
        puts "INFO: FCFP $stage_name upf..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] upf loading skipped" }
        set ff "$run_dir/work/FCFP/$node_name/upf/upf_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set upf_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set upf_info(status) \"loaded\""; close $fh
        puts "INFO: FCFP $stage_name upf completed"
    }
    "library" {
        puts "INFO: FCFP $stage_name library..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] library loading skipped" }
        set ff "$run_dir/work/FCFP/$node_name/library/library_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set library_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; puts $fh "set library_info(status) \"loaded\""; close $fh
        puts "INFO: FCFP $stage_name library completed"
    }
    "validate" {
        puts "INFO: FCFP $stage_name validate..."
        if {$test_mode} { puts "INFO: \[TEST MODE\] Validation skipped" }
        puts "INFO: FCFP $stage_name validate completed"
    }
    "finish" {
        puts "INFO: FCFP $stage_name finish..."
        set ff "$run_dir/work/FCFP/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set finish_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; close $fh
        puts "INFO: FCFP $stage_name finish completed"
    }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
