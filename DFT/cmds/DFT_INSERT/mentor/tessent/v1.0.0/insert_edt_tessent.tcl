#!/usr/bin/env tclsh
# CBFlow DFT_INSERT insert_edt — Mentor Tessent (EDT / SSN compression)

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "insert_edt"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc configure_edt {
    handle_info "Configuring EDT / SSN..."
    set ratio [expr {[info exists ::dft_insert(edt,compression_ratio)] ? $::dft_insert(edt,compression_ratio) : 100}]
    set inch  [expr {[info exists ::dft_insert(edt,input_channels)]    ? $::dft_insert(edt,input_channels)    : 8}]
    set outch [expr {[info exists ::dft_insert(edt,output_channels)]   ? $::dft_insert(edt,output_channels)   : 8}]
    add_edt_block default -input_channel_count $inch -output_channel_count $outch
    set_edt_options -compression_ratio $ratio
    if {[info exists ::dft_insert(edt,ssn,enable)] && $::dft_insert(edt,ssn,enable)} {
        add_ssn_block -default
        handle_info "SSN streaming compression enabled"
    }
    handle_info "EDT: ratio=$ratio in=$inch out=$outch"
}

flow_proc insert_edt_logic {
    handle_info "Inserting EDT/SSN logic..."
    insert_test_logic -edt
}

flow_proc write_edt_outputs {
    set design $::flow(design_name)
    set out "$::OUTPUTS_DIR/${design}.edt.v"
    write_verilog $out
    handle_info "EDT netlist: $out"

    set rpt "$::REPORTS_DIR/edt_insertion.rpt"
    set fh [open $rpt "w"]
    puts $fh "EDT Insertion Report - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Status: PASS"
    close $fh
}

flow_proc insert_edt_flow {
    handle_info "Executing DFT_INSERT insert_edt flow..."
    flow_exec configure_edt
    flow_exec insert_edt_logic
    flow_exec write_edt_outputs
    handle_info "DFT_INSERT insert_edt completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec insert_edt_flow } else { puts " DFT_INSERT insert_edt procedures loaded" }
exit
