#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV DV_SIGNOFF — inputs Subnode Handler
# Collects the single generic review_artifact input bundle.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "DV_SIGNOFF"

set ::flow_type "DV_SIGNOFF"
set stage_name "review_artifact"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set test_mode [handler_is_test_mode]

handler_resolve_inputs $::flow_type $run_dir

set input_types {review_artifact}
handler_dispatch_inputs $subnode_name $run_dir $::flow_type $node_name $input_types $test_mode
