#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV PLANNING — review Subnode Handler (shared across every review stage)
# ═══════════════════════════════════════════════════════════════════════════════
# One file handles every review stage in this flow — the engine invokes it
# once per node (drs_review, architecture_detailing, etc.). stage_name is
# derived from the engine-provided node_name by stripping the numeric suffix.

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PLANNING"

set ::flow_type "PLANNING"
# Strip the trailing instance digits to recover the stage name — e.g.
# drs_review1 → drs_review, architecture_detailing1 → architecture_detailing.
set stage_name [regsub {\d+$} $node_name {}]
if {$node_name eq ""} {
    puts stderr "ERROR: review handler invoked without node_name"
    exit 1
}

# Shared command file — one script serves every DV review flow × every
# review stage. The DV/ segment is hardcoded because the handler lives there.
set cmd_file "$::env(FLOW_DIR)/DV/cmds/_shared/generic/review/v1.0.0/review_gate.tcl"

set test_mode [handler_is_test_mode]
handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode "review" "review"
