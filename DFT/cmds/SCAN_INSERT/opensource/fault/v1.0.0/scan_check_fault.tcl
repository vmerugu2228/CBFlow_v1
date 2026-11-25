#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT — scan_check (opensource / container tclsh → iverilog)
# Scan DRC + shift check: the tracer's rule violations (broken / looped
# chains, scan enable not from a scan-enable port, clock mixing under no_mix,
# chains over max_chain_length, untraced clocks), unscanned flops
# (scan_insert(oss,allow_unscanned)), and a chain-flush simulation of the gate
# netlist — 0011… shifted through every chain, scan-out compared after the
# chain length (macros stubbed). Any failure fails the stage.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SCAN_INSERT"
set STAGE_NAME "scan_check"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_design {
    set ::init   "[cbflow_node_dir [oss_chain_node init_scan]]/outputs"
    set ::stitch "[cbflow_node_dir [oss_chain_node scan_stitch]]"
    set ::netlist [dft_input netlist]
    set ::fails {}
}

flow_proc check_rules {
    set _r "$::stitch/reports/scan_chains.rpt"
    set _v [dft_report_value $_r Violations]
    set _u [dft_report_value $_r unscanned]
    set ::rules [list chains [dft_report_value $_r chains] scanned [dft_report_value $_r {scanned flops}] \
                      sequential [dft_report_value $_r {sequential cells}] unscanned $_u violations $_v \
                      coverage [dft_report_value $_r {scan coverage %}]]
    if {$_v > 0} { lappend ::fails "$_v scan rule violation(s) — $_r" }
    if {$_u > 0 && ![is_true [oss_get scan_insert oss,allow_unscanned]]} {
        lappend ::fails "$_u unscanned flop(s) (scan_insert(oss,allow_unscanned) false) — $_r"
    }
}

flow_proc flush_sim {
    global design_name
    set ::flush "not run (scan_insert(oss,flush,enable) false)"
    if {![is_true [oss_get scan_insert oss,flush,enable]]} { return }
    set _w "$::WORK_DIR/run"
    dft_py "$::REPORTS_DIR/stubs.log" stubs --json "$::init/netlist.json" --top $design_name \
        --cells "$::init/cells.json" -o "$_w/macro_stubs.v"
    dft_py "$::REPORTS_DIR/flush_tb.log" flush-tb --scan "$::stitch/outputs/scan.json" --top $design_name \
        -o "$_w/scan_flush_tb.v"
    set _log [dft_simulate [concat [dft_cell_models] [list "$_w/macro_stubs.v" $::netlist "$_w/scan_flush_tb.v"]] \
                  cbflow_scan_flush_tb "$_w/scan_flush.vvp" "$::REPORTS_DIR/scan_flush_sim.log"]
    set _fh [open $_log]; set _t [read $_fh]; close $_fh
    if {![regexp {Mismatches:\s*(\d+)} $_t -> _mm] || ![regexp {Flush checks:\s*(\d+)} $_t -> _ck]} {
        lappend ::fails "flush simulation did not complete — $_log"
        set ::flush "incomplete"
        return
    }
    set ::flush "$_ck checks, $_mm mismatches"
    if {$_mm > 0 || ![string match "*FLUSH TEST PASSED*" $_t]} { lappend ::fails "chain flush failed: $_mm mismatch(es) — $_log" }
}

flow_proc report {
    global design_name
    set _st [expr {[llength $::fails] ? "FAIL" : "PASS"}]
    set _l [list "Scan check — $design_name" \
                 "  Chains            : [dict get $::rules chains]" \
                 "  Scanned flops     : [dict get $::rules scanned] of [dict get $::rules sequential]" \
                 "  scan_coverage_pct : [dict get $::rules coverage]" \
                 "  Unscanned flops   : [dict get $::rules unscanned]" \
                 "  Rule violations   : [dict get $::rules violations]" \
                 "  Chain flush       : $::flush" \
                 "  Status            : $_st"]
    foreach _f $::fails { lappend _l "  FAIL: $_f" }
    lappend _l "" "  Chain detail: $::stitch/reports/scan_chains.rpt"
    dft_write "$::REPORTS_DIR/scan_check.rpt" "[join $_l \n]\n"
    dft_write [oss_stage_out scan_check.status] "$_st\n"
    if {$_st ne "PASS"} { error "scan check FAILED: [join $::fails {; }]" }
    handle_info "scan check PASS ($::flush)"
}

dft_exec_all
exit
