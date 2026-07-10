#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow shared (PNR + SYNTH_PNR) — release_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir $::env(CBFLOW_FLOW_TYPE)

set ::flow_type $::env(CBFLOW_FLOW_TYPE)
set stage_name "release_data"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(FC_VERSION)] ? $::env(FC_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/$::flow_type/synopsys/fc/$_tool_ver/release_data_fc.tcl"

set test_mode [handler_is_test_mode]
upvar #0 [string tolower $::flow_type] _cfg
set _tool [expr {[info exists _cfg(tool,name)] ? $_cfg(tool,name) : "fc"}]

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
