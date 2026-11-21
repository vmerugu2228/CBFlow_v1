#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA (opensource) — merge_reports Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: sta(oss,tool,merge_reports)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "merge_reports"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(OPENSTA_VERSION)] ? $::env(OPENSTA_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/STA/opensource/opensta/$_tool_ver/merge_reports_opensta.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::sta(oss,tool,$stage_name)]} {
    puts "ERROR: sta(oss,tool,$stage_name) not set — STA_opensta_config.tcl not loaded?"
    exit 1
}
set _tool $::sta(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
