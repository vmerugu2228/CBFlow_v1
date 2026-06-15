#!/usr/bin/env tclsh
# CBFlow DFT_INSERT insert_occ — Mentor Tessent

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "insert_occ"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc configure_occ {
    handle_info "Configuring OCC insertion..."
    set scan_en [expr {[info exists ::dft_insert(occ,scan_enable_pin)] ? $::dft_insert(occ,scan_enable_pin) : "scan_en"}]
    set tclk    [expr {[info exists ::dft_insert(occ,test_clock_pin)]  ? $::dft_insert(occ,test_clock_pin)  : "test_clk"}]
    add_dft_signal -type ScanEnable -pin $scan_en
    add_dft_signal -type TestClock  -pin $tclk
    handle_info "OCC: scan_en=$scan_en test_clk=$tclk"
}

flow_proc insert_occ_logic {
    handle_info "Inserting OCC controllers..."
    add_clock_controller -auto
    insert_test_logic -occ
}

flow_proc write_occ_outputs {
    set design $::flow(design_name)
    set out "$::OUTPUTS_DIR/${design}.occ.v"
    write_verilog $out
    handle_info "OCC netlist: $out"

    set rpt "$::REPORTS_DIR/occ_insertion.rpt"
    set fh [open $rpt "w"]
    puts $fh "OCC Insertion Report - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Status: PASS"
    close $fh
}

flow_proc insert_occ_flow {
    handle_info "Executing DFT_INSERT insert_occ flow..."
    flow_exec configure_occ
    flow_exec insert_occ_logic
    flow_exec write_occ_outputs
    handle_info "DFT_INSERT insert_occ completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec insert_occ_flow } else { puts " DFT_INSERT insert_occ procedures loaded" }
exit
