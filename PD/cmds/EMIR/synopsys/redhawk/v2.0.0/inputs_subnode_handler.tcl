#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow EMIR — inputs Subnode Handler
# Subnodes: setup, netlist / def / spef / library, validate, finish
# Delegated to handler_dispatch_inputs.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "EMIR"

set ::flow_type "EMIR"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

set test_mode [handler_is_test_mode]

# Resolve upstream inputs (from_run manifest / release_tag / direct paths).
# Safe to call every subnode invocation — resolve_flow_inputs is idempotent.
handler_resolve_inputs $::flow_type $run_dir

set input_types {netlist def spef library}
handler_dispatch_inputs $subnode_name $run_dir $::flow_type $node_name $input_types $test_mode
