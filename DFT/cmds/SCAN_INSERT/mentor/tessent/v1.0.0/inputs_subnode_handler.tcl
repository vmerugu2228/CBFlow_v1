#!/usr/bin/env tclsh
# CBFlow SCAN_INSERT INPUTS Subnode Handler — tessent
# Subnodes: netlist sdc lib

if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir      [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name    [expr {$argc > 2 ? [lindex $argv 2] : ""}]

if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/SCAN_INSERT_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "SCAN_INSERT"
set stage_name  "inputs"
if {$node_name eq ""} { set node_name $stage_name }

set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }

if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_resolve_lib]} { source $_resolve_lib; resolve_flow_inputs $::flow_type $run_dir }
}

set _ts [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _t] ? "epoch [clock seconds]" : $_t}]

# Generic handler — creates work/<flow>/<node_name>/<subnode>/ and writes an _info.tcl stub
proc _gen_input_subnode {flow node_name sub} {
    upvar 1 _ts _ts test_mode test_mode
    set wd "$::env(CBFLOW_RUN_DIR)/work/$flow/$node_name/$sub"
    file mkdir $wd
    set fh [open "$wd/${sub}_info.tcl" "w"]
    puts $fh "set ${sub}_info(timestamp) \"$_ts\""
    puts $fh "set ${sub}_info(status) \"loaded\""
    close $fh
    puts "INFO: SCAN_INSERT $sub completed"
}

switch $subnode_name {
    "netlist" { puts "INFO: SCAN_INSERT netlist..."; _gen_input_subnode "SCAN_INSERT" $node_name "netlist" }
    "sdc" { puts "INFO: SCAN_INSERT sdc..."; _gen_input_subnode "SCAN_INSERT" $node_name "sdc" }
    "lib" { puts "INFO: SCAN_INSERT lib..."; _gen_input_subnode "SCAN_INSERT" $node_name "lib" }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
