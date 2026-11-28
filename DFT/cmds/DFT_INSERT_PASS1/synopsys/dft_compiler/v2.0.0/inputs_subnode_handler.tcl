#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 — inputs Subnode Handler (DFT Compiler)

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "DFT_INSERT_PASS1"

set ::flow_type "DFT_INSERT_PASS1"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode [handler_is_test_mode]
handler_resolve_inputs $::flow_type $run_dir
set input_types {rtl spec lib}
handler_dispatch_inputs $subnode_name $run_dir $::flow_type $node_name $input_types $test_mode
