#!/usr/bin/env tclsh
# CBFlow RTL_CDC INPUTS Subnode Handler — spyglass
# Subnodes: rtl sdc scheme waivers

if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
if {$argc > 1} {
    set run_dir [lindex $argv 1]
} elseif {[info exists ::env(CBFLOW_RUN_DIR)] && $::env(CBFLOW_RUN_DIR) ne ""} {
    set run_dir $::env(CBFLOW_RUN_DIR)
} else {
    puts stderr "ERROR: run_dir not provided as argv and CBFLOW_RUN_DIR not set in env"
    exit 1
}
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: .run.cbflow.tcl not found"; exit 1
}
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/RTL_CDC_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "RTL_CDC"
set stage_name  "inputs"
if {$node_name eq ""} { set node_name $stage_name }

set test_mode false
if {[info exists flow(test_mode)] && [is_true $flow(test_mode)]} { set test_mode true }

if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_resolve_lib]} { source $_resolve_lib; resolve_flow_inputs $::flow_type $run_dir }
}

set _ts [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _t] ? "epoch [clock seconds]" : $_t}]

proc _gen_input_subnode {flow node_name sub} {
    upvar 1 _ts _ts test_mode test_mode
    global run_dir
    set wd "$run_dir/work/$flow/$node_name/$sub"
    file mkdir $wd
    set fh [open "$wd/${sub}_info.tcl" "w"]
    puts $fh "set ${sub}_info(timestamp) \"$_ts\""
    puts $fh "set ${sub}_info(status) \"loaded\""
    close $fh
    puts "INFO: RTL_CDC $sub input prepared"
}

set valid_subnodes {rtl sdc scheme waivers}
if {[lsearch -exact $valid_subnodes $subnode_name] == -1} {
    puts "ERROR: Invalid subnode '$subnode_name' for RTL_CDC inputs — expected: $valid_subnodes"
    exit 1
}
_gen_input_subnode "RTL_CDC" $node_name $subnode_name
