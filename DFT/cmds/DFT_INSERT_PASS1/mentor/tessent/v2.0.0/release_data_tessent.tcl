#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 release_data — Mentor Tessent
# Packages the 35+ Pass1 artifacts into the release directory per
# dft_insert_pass1(release_types,dft_pass1,files).

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "release_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
# release_data uses the shared release_utils.tcl machinery which reads
# dft_insert_pass1(release_types,dft_pass1,files) directly. The actual
# packaging is handler-level, not stage-level — this file is a sentinel.

flow_proc release_data_flow {
    handle_info "DFT_INSERT_PASS1 release_data invoked — release packaging is handled by handler_run via release_utils."
    # Nothing to do here beyond emitting the completion marker; the
    # subnode handler's release_data path copies files per release_types.
    set rpt "$::REPORTS_DIR/release_data.rpt"
    set fh [open $rpt "w"]
    puts $fh "DFT_INSERT_PASS1 release_data completed — [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "Block: [dft_tessent_block_name]"
    close $fh
    handle_info "Release report: $rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec release_data_flow } else { puts "DFT_INSERT_PASS1 release_data procedures loaded" }
exit
