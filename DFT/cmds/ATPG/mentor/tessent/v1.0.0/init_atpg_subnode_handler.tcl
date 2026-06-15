#!/usr/bin/env tclsh
# CBflow ATPG — init_atpg Subnode Handler (tessent)
# Subnodes: setup, run, validate, finish

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "ATPG"

set ::flow_type "ATPG"
set stage_name  "init_atpg"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(TOOL_VERSION)] ? $::env(TOOL_VERSION) : "v1.0.0"}]
set _dft_root [expr {[info exists ::env(CBFLOW_DFT_DIR)] ? $::env(CBFLOW_DFT_DIR) : "$::env(FLOW_DIR)/../DFT"}]
set cmd_file  "$_dft_root/cmds/ATPG/mentor/tessent/$_tool_ver/${stage_name}_tessent.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup"    { puts "INFO: $stage_name setup...";    handler_setup    $run_dir $::flow_type $node_name; puts "INFO: $stage_name setup completed" }
    "run"      { puts "INFO: $stage_name run...";      handler_run      $run_dir $::flow_type $node_name $stage_name $cmd_file $test_mode "tessent" }
    "validate" { puts "INFO: $stage_name validate..."; handler_validate $run_dir $::flow_type $node_name $stage_name $test_mode; puts "INFO: $stage_name validate completed" }
    "finish"   { puts "INFO: $stage_name finish...";   handler_finish   $run_dir $::flow_type $node_name $stage_name; puts "INFO: $stage_name finish completed" }
    default    { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
