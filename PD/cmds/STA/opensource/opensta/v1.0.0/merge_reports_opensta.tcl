#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — merge_reports (opensource / tclsh)
# Merge the per-scenario QoR: worst setup / hold slack and TNS per scenario
# and overall -> outputs/sta_summary.rpt (+ sta_summary.tcl).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "merge_reports"
# Dynamic subnodes (per RC corner / per scenario) pass their node in the
# context script (::OSS_NODE); otherwise the launch wrapper's node.
set NODE_NAME [expr {[info exists ::OSS_NODE] ? $::OSS_NODE : [cbflow_node_name]}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc merge {
    global design_name
    set _tnode [oss_chain_node timing]
    set _rows {}
    foreach _q [lsort [glob -nocomplain "[cbflow_node_dir $_tnode]/*/reports/[oss_get sta oss,scenario_qor_file]"]] {
        array unset qor
        source $_q
        lappend _rows [list $qor(scenario) $qor(wns_setup) $qor(tns_setup) $qor(wns_hold) $qor(tns_hold)]
    }
    if {[llength $_rows] == 0 && ![is_true $::flow(test_mode)]} { error "no per-scenario QoR under [cbflow_node_dir $_tnode]" }
    set _ws 1e9; set _wh 1e9
    set _fh [open [oss_stage_out sta_summary.rpt] w]
    puts $_fh [format "%-40s %12s %12s %12s %12s" scenario setup_wns setup_tns hold_wns hold_tns]
    foreach _r $_rows {
        lassign $_r _s _wsn _tsn _whn _thn
        puts $_fh [format "%-40s %12.4f %12.4f %12.4f %12.4f" $_s $_wsn $_tsn $_whn $_thn]
        if {$_wsn < $_ws} { set _ws $_wsn }
        if {$_whn < $_wh} { set _wh $_whn }
    }
    puts $_fh "\nworst setup WNS: $_ws    worst hold WNS: $_wh    scenarios: [llength $_rows]"
    close $_fh
    set _fh [open [oss_stage_out sta_summary.tcl] w]
    puts $_fh "set sta_summary(wns_setup) $_ws\nset sta_summary(wns_hold) $_wh\nset sta_summary(scenarios) [llength $_rows]"
    close $_fh
    handle_info "STA: worst setup WNS $_ws, worst hold WNS $_wh over [llength $_rows] scenarios"
}

flow_exec_all
exit
