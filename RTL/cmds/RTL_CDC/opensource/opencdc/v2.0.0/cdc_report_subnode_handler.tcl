#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_CDC (opensource) — cdc_report Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: rtl_cdc(oss,tool,cdc_report)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "RTL_CDC"

set ::flow_type "RTL_CDC"
set stage_name "cdc_report"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_RTL_DIR)/cmds/RTL_CDC/opensource/opencdc/$_tool_ver/cdc_report_opencdc.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::rtl_cdc(oss,tool,$stage_name)]} {
    puts "ERROR: rtl_cdc(oss,tool,$stage_name) not set — RTL_CDC_opencdc_config.tcl not loaded?"
    exit 1
}
set _tool $::rtl_cdc(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
