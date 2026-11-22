#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — inputs Subnode Handler
# Subnodes: setup, netlist / sdc / def / upf / library, validate, finish
# Delegated to handler_dispatch_inputs.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "inputs"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set test_mode [handler_is_test_mode]

# Resolve upstream inputs (from_run manifest / release_tag / direct paths).
# Safe to call every subnode invocation — resolve_flow_inputs is idempotent.
handler_resolve_inputs $::flow_type $run_dir

# Input types = the flow's input nodes (<flow>(node_types,<n>) "inputs") with
# the instance number stripped — the same rtl1 -> rtl rule the RACE engine
# uses to name each input node's subnode.
set ::FLOW_TYPE $::flow_type
set input_types {}
foreach _n [cbflow_require [cbflow_flow_arr] stages] {
    if {[cbflow_node_type $_n] eq "inputs"} { lappend input_types [string trimright $_n 0123456789] }
}
if {![llength $input_types]} { puts "ERROR: no input nodes in [cbflow_flow_arr](stages)"; exit 1 }
handler_dispatch_inputs $subnode_name $run_dir $::flow_type $node_name $input_types $test_mode
