#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV SPEC_RAMP — release_data Subnode Handler
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "SPEC_RAMP"

set ::flow_type "SPEC_RAMP"
set stage_name "release_data"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set cmd_file "$::env(FLOW_DIR)/cmds/SPEC_RAMP/generic/review/v1.0.0/release_data_review.tcl"

set test_mode [handler_is_test_mode]
handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode "review" "review"
