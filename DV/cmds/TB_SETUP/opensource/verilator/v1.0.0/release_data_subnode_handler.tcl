#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow TB_SETUP (opensource) — release_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: tb_setup(oss,tool,release_data)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "TB_SETUP"

set ::flow_type "TB_SETUP"
set stage_name "release_data"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [cbflow_require tb_setup tool,version]
set cmd_file "$::env(CBFLOW_DV_DIR)/cmds/TB_SETUP/opensource/verilator/$_tool_ver/release_data_verilator.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::tb_setup(oss,tool,$stage_name)]} {
    puts "ERROR: tb_setup(oss,tool,$stage_name) not set — TB_SETUP_verilator_config.tcl not loaded?"
    exit 1
}
set _tool $::tb_setup(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
