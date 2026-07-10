#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV — fill Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PV"

set ::flow_type "PV"
set stage_name "fill"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(CALIBRE_VERSION)] ? $::env(CALIBRE_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/PV/mentor/calibre/$_tool_ver/fill_calibre.tcl"

set test_mode [handler_is_test_mode]
set _tool [expr {[info exists ::pv(tool,name)] ? $::pv(tool,name) : "calibre"}]

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
