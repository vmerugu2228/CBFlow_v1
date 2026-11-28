#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV_SIGNOFF (opensource) — signoff Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: dv_signoff(oss,tool,signoff)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "DV_SIGNOFF"

set ::flow_type "DV_SIGNOFF"
set stage_name "signoff"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DV_DIR)/cmds/DV_SIGNOFF/opensource/verilator/$_tool_ver/signoff_verilator.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::dv_signoff(oss,tool,$stage_name)]} {
    puts "ERROR: dv_signoff(oss,tool,$stage_name) not set — DV_SIGNOFF_verilator_config.tcl not loaded?"
    exit 1
}
set _tool $::dv_signoff(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
