#!/usr/bin/env tclsh
# CBFlow DFT_INSERT insert_mbist — Mentor Tessent

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "insert_mbist"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc configure_mbist {
    handle_info "Configuring MBIST insertion..."
    set ctrl  [expr {[info exists ::dft_insert(mbist,controller_type)] ? $::dft_insert(mbist,controller_type) : "smart_serial"}]
    set wrap  [expr {[info exists ::dft_insert(mbist,wrap_memories)]   ? $::dft_insert(mbist,wrap_memories)   : true}]
    set clk   [expr {[info exists ::dft_insert(mbist,bist_clock_domain)] ? $::dft_insert(mbist,bist_clock_domain) : "tessent_clk"}]
    add_mbist_controller -type $ctrl -clock_domain $clk
    if {$wrap} { wrap_memories }
    handle_info "MBIST: controller=$ctrl clock=$clk wrap=$wrap"
}

flow_proc insert_mbist_logic {
    handle_info "Inserting MBIST logic..."
    insert_test_logic -mbist
}

flow_proc write_mbist_outputs {
    set design $::flow(design_name)
    set out "$::OUTPUTS_DIR/${design}.mbist.v"
    write_verilog $out
    handle_info "MBIST netlist: $out"

    set rpt "$::REPORTS_DIR/mbist_insertion.rpt"
    set fh [open $rpt "w"]
    puts $fh "MBIST Insertion Report - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Status: PASS"
    close $fh
}

flow_proc insert_mbist_flow {
    handle_info "Executing DFT_INSERT insert_mbist flow..."
    flow_exec configure_mbist
    flow_exec insert_mbist_logic
    flow_exec write_mbist_outputs
    handle_info "DFT_INSERT insert_mbist completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec insert_mbist_flow } else { puts " DFT_INSERT insert_mbist procedures loaded" }
exit
