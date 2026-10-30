#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV M4_EXEC — release_data Subnode Handler
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "M4_EXEC"

set ::flow_type "M4_EXEC"
set stage_name "release_data"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set cmd_file "$::env(FLOW_DIR)/cmds/M4_EXEC/generic/review/v1.0.0/release_data_review.tcl"

set test_mode [handler_is_test_mode]
handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode "review" "review"
