#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 bscan_spec — Mentor Tessent
# BSCAN interface spec writes — <block>_rtl1_tessent_bscan_interface_m{1,2}.{icl,v}.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "bscan_spec"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc bscan_spec_write {
    set block [dft_tessent_block_name]
    set did [dft_tessent_block_get $block design_id rtl1]
    set base "${block}_${did}_tessent_bscan_interface"
    foreach m {m1 m2} {
        set icl "$::OUTPUTS_DIR/${base}_${m}.icl"
        set v   "$::OUTPUTS_DIR/${base}_${m}.v"
        handle_info "Writing BSCAN interface $m → $icl + $v"
        extract_icl -bscan -mode $m -output $icl
        write_bscan_interface -mode $m -output $v
    }
}

flow_proc bscan_spec_flow {
    handle_info "Executing DFT_INSERT_PASS1 bscan_spec flow..."
    flow_exec bscan_spec_write
    handle_info "DFT_INSERT_PASS1 bscan_spec completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec bscan_spec_flow } else { puts "DFT_INSERT_PASS1 bscan_spec procedures loaded" }
exit
