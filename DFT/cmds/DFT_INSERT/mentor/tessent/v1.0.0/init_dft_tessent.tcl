#!/usr/bin/env tclsh
# CBFlow DFT_INSERT init_dft — Mentor Tessent

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "init_dft"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc init_tessent {
    handle_info "Tessent shell init..."
    set context dft -no_rtl
    set_design_level chip
    set_system_mode setup
    handle_info "Tessent context: dft (chip)"
}

flow_proc read_rtl {
    handle_info "Reading RTL..."
    if {[info exists ::dft_insert(input,rtl)] && $::dft_insert(input,rtl) ne ""} {
        read_verilog $::dft_insert(input,rtl)
        handle_info "RTL: $::dft_insert(input,rtl)"
    }
}

flow_proc read_dft_spec {
    handle_info "Reading DFT specification..."
    if {[info exists ::dft_insert(input,dft_spec)] && $::dft_insert(input,dft_spec) ne ""} {
        source $::dft_insert(input,dft_spec)
        handle_info "DFT spec: $::dft_insert(input,dft_spec)"
    }
}

flow_proc set_dft_signals {
    handle_info "Tagging DFT signals..."
    set_dft_signal -view existing -type ScanEnable -port [list scan_en]
    set_dft_signal -view existing -type Reset      -port [list rst_n]
    set_dft_signal -view existing -type Constant   -port [list test_mode] -value 0
}

flow_proc init_summary {
    set rpt "$::REPORTS_DIR/init_dft.rpt"
    set fh [open $rpt "w"]
    puts $fh "DFT_INSERT init - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Tool: Tessent  Status: OK"
    close $fh
    handle_info "Init summary: $rpt"
}

flow_proc init_dft_flow {
    handle_info "Executing DFT_INSERT init_dft flow..."
    flow_exec init_tessent
    flow_exec read_rtl
    flow_exec read_dft_spec
    flow_exec set_dft_signals
    flow_exec init_summary
    handle_info "DFT_INSERT init_dft completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec init_dft_flow } else { puts " DFT_INSERT init_dft procedures loaded" }
exit
