#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 tap_spec — Mentor Tessent
# TAP spec extraction — writes <block>.tap.icl.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "tap_spec"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc tap_spec_extract {
    set block [dft_tessent_block_name]
    set out "$::OUTPUTS_DIR/${block}.tap.icl"
    handle_info "Extracting TAP ICL spec → $out"
    extract_icl -tap -output $out
}

flow_proc tap_spec_flow {
    handle_info "Executing DFT_INSERT_PASS1 tap_spec flow..."
    flow_exec tap_spec_extract
    handle_info "DFT_INSERT_PASS1 tap_spec completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec tap_spec_flow } else { puts "DFT_INSERT_PASS1 tap_spec procedures loaded" }
exit
