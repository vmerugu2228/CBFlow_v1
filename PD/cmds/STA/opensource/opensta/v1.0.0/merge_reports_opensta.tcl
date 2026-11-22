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
    set _rows {}; set _prows {}
    foreach _q [lsort [glob -nocomplain "[cbflow_node_dir $_tnode]/*/reports/[oss_get sta oss,scenario_qor_file]"]] {
        array unset qor
        source $_q
        lappend _rows [list $qor(scenario) $qor(wns_setup) $qor(tns_setup) $qor(wns_hold) $qor(tns_hold)]
        if {[info exists qor(power_total)]} {
            lappend _prows [list $qor(scenario) $qor(power_total) $qor(power_internal) $qor(power_switching) $qor(power_leakage)]
        }
    }
    if {[llength $_rows] == 0 && ![is_true $::flow(test_mode)]} { error "no per-scenario QoR under [cbflow_node_dir $_tnode]" }
    set _ws 1e9; set _wh 1e9
    set _fh [open [oss_stage_out sta_summary.rpt] w]
    puts $_fh [format "%-40s %12s %12s %12s %12s" scenario setup_wns setup_tns hold_wns hold_tns]
    foreach _r $_rows {
        lassign $_r _s _wsn _tsn _whn _thn
        puts $_fh [format "%-40s %12s %12s %12s %12s" $_s [cbflow_fmt_slack $_wsn] [cbflow_fmt_slack $_tsn] [cbflow_fmt_slack $_whn] [cbflow_fmt_slack $_thn]]
        if {$_wsn < $_ws} { set _ws $_wsn }
        if {$_whn < $_wh} { set _wh $_whn }
    }
    puts $_fh "\nworst setup WNS: [cbflow_fmt_slack $_ws]    worst hold WNS: [cbflow_fmt_slack $_wh]    scenarios: [llength $_rows]"
    close $_fh
    set _fh [open [oss_stage_out sta_summary.tcl] w]
    puts $_fh "set sta_summary(wns_setup) $_ws\nset sta_summary(wns_hold) $_wh\nset sta_summary(scenarios) [llength $_rows]"
    close $_fh
    # Power per scenario (mW) -> outputs/sta_power.rpt
    if {[is_true [oss_get sta oss,report_power]]} {
        if {[llength $_prows] != [llength $_rows]} { error "power missing for [expr {[llength $_rows] - [llength $_prows]}] scenario(s)" }
        set _fh [open [oss_stage_out sta_power.rpt] w]
        puts $_fh [format "%-40s %12s %12s %12s %12s" scenario total_mW internal_mW switching_mW leakage_mW]
        foreach _r $_prows {
            lassign $_r _s _t _i _w _l
            puts $_fh [format "%-40s %12.4g %12.4g %12.4g %12.4g" $_s [expr {$_t*1e3}] [expr {$_i*1e3}] [expr {$_w*1e3}] [expr {$_l*1e3}]]
        }
        close $_fh
    }
    # Checklist report (STA_SIGNOFF checks): worst over all
    # scenarios, one "Key : value" line per check (STA_opensta_config map).
    set _ts 0.0; set _th 0.0; set _tran 0; set _cap 0; set _fan 0; set _fail 0; set _pw ""
    set _du 0; set _dtm 0; set _dtn 0
    foreach _q [lsort [glob -nocomplain "[cbflow_node_dir $_tnode]/*/reports/[oss_get sta oss,scenario_qor_file]"]] {
        array unset qor
        source $_q
        if {$qor(tns_setup) < $_ts} { set _ts $qor(tns_setup) }
        if {$qor(tns_hold) < $_th} { set _th $qor(tns_hold) }
        # violations: the worst scenario's count (the same nets repeat per scenario)
        if {$qor(max_tran_violations) > $_tran} { set _tran $qor(max_tran_violations) }
        if {$qor(max_cap_violations) > $_cap} { set _cap $qor(max_cap_violations) }
        if {$qor(max_fanout_violations) > $_fan} { set _fan $qor(max_fanout_violations) }
        if {$qor(wns_setup) < [oss_get sta signoff,min_setup_wns] || $qor(wns_hold) < [oss_get sta signoff,min_hold_wns]} { incr _fail }
        if {[info exists qor(power_total)] && ($_pw eq "" || $qor(power_total) > $_pw)} { set _pw $qor(power_total) }
        # netlist checks: same netlist in every scenario — worst seen
        if {$qor(dont_use_cells) > $_du} { set _du $qor(dont_use_cells) }
        if {$qor(dont_touch_missing) > $_dtm} { set _dtm $qor(dont_touch_missing) }
        set _dtn $qor(dont_touch_instances)
    }
    set _C [list "Scenarios timed : [llength $_rows]" "Failing scenarios : $_fail" \
                 "Worst setup WNS : [cbflow_fmt_slack $_ws]" "Worst setup TNS : [cbflow_fmt_slack $_ts]" \
                 "Worst hold WNS : [cbflow_fmt_slack $_wh]" "Worst hold TNS : [cbflow_fmt_slack $_th]" \
                 "Tran violations : $_tran" "Cap violations : $_cap" "Fanout violations : $_fan" \
                 "Noise : N/A" "Dont use cells : $_du" "Dont touch missing : $_dtm" \
                 "Dont touch instances : $_dtn"]
    if {$_pw ne ""} { lappend _C "Total power mW : [format %.4g [expr {$_pw * 1e3}]]" }
    set _fh [open [oss_stage_out sta_checklist.rpt] w]; puts $_fh [join $_C \n]; close $_fh
    handle_info "STA: worst setup WNS $_ws, worst hold WNS $_wh over [llength $_rows] scenarios"
}

flow_exec_all
exit
