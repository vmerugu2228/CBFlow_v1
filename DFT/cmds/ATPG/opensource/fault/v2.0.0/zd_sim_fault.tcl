#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — zd_sim (opensource / container tclsh → iverilog)
# Zero-delay serial-scan simulation of every pattern on the gate netlist
# (cell models FUNCTIONAL, macros stubbed): load through the scan chains,
# capture, unload and compare. Any mismatch fails the stage.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "zd_sim"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc simulate {
    set _ex "[cbflow_node_dir [oss_chain_node export_patterns]]/outputs"
    set _log [dft_simulate [concat [dft_cell_models] [list "$_ex/macro_stubs.v" [dft_input netlist] "$_ex/scan_tb.v"]] \
                  cbflow_scan_tb "$::WORK_DIR/run/zd_sim.vvp" "$::REPORTS_DIR/zd_sim.log"]
    set _fh [open $_log]; set _t [read $_fh]; close $_fh
    if {![regexp {Mismatches:\s*(\d+)} $_t -> _mm] || ![regexp {Checks:\s*(\d+)} $_t -> _ck]} {
        dft_write [oss_stage_out zd_sim.status] "FAIL\n"
        error "zero-delay pattern simulation did not complete — $_log"
    }
    set _st [expr {$_mm == 0 && [string match "*SCAN PATTERN TEST PASSED*" $_t] ? "PASS" : "FAIL"}]
    dft_write [oss_stage_out zd_sim.status] "$_st\n"
    if {$_st ne "PASS"} { error "zero-delay pattern simulation: $_mm mismatch(es) of $_ck checks — $_log" }
    handle_info "zero-delay pattern simulation PASS ($_ck checks, 0 mismatches)"
}

dft_exec_all
exit
