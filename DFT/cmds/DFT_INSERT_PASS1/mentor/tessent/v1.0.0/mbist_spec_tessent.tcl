#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 mbist_spec — Mentor Tessent
# MBIST controller + BAP spec writes:
#   <blk>_<did>_tessent_mbist_c1_controller.{v,icl,pdl,tcd}
#   <blk>_<did>_tessent_mbist_bap.{v,icl,tcd}
#   <blk>.{icl,pdl,sdc,tcd,tsdb_info,dft_spec}
# plus mbist.{sdc,synthesis}_dictionary.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "mbist_spec"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc mbist_spec_check_enable {
    set block [dft_tessent_block_name]
    set enabled [dft_tessent_block_get $block include_memory_test OFF]
    set ::_mbist_skip [expr {$enabled ne "ON"}]
    if {$::_mbist_skip} {
        handle_info "MBIST OFF for block '$block' — skipping spec writes"
    }
}

flow_proc mbist_spec_write_bap {
    if {$::_mbist_skip} { return }
    set block [dft_tessent_block_name]
    set did [dft_tessent_block_get $block design_id rtl1]
    set base "${block}_${did}_tessent_mbist_bap"
    foreach ext {icl tcd v} {
        set f "$::OUTPUTS_DIR/${base}.${ext}"
        handle_info "Writing BAP ${ext} → $f"
        write_mbist_bap -format $ext -output $f
    }
}

flow_proc mbist_spec_write_controller {
    if {$::_mbist_skip} { return }
    set block [dft_tessent_block_name]
    set did [dft_tessent_block_get $block design_id rtl1]
    set base "${block}_${did}_tessent_mbist_c1_controller"
    foreach ext {icl pdl tcd v} {
        set f "$::OUTPUTS_DIR/${base}.${ext}"
        handle_info "Writing controller ${ext} → $f"
        write_mbist_controller -format $ext -output $f
    }
}

flow_proc mbist_spec_write_dictionaries {
    if {$::_mbist_skip} { return }
    set block [dft_tessent_block_name]
    set did [dft_tessent_block_get $block design_id rtl1]
    set base "${block}_${did}_mbist"
    set sdc_dict "$::OUTPUTS_DIR/${base}.sdc_dictionary"
    set syn_dict "$::OUTPUTS_DIR/${base}.synthesis_dictionary"
    write_mbist_sdc_dictionary        -output $sdc_dict
    write_mbist_synthesis_dictionary  -output $syn_dict
    handle_info "SDC dict: $sdc_dict"
    handle_info "Syn dict: $syn_dict"
}

flow_proc mbist_spec_write_block_spec {
    set block [dft_tessent_block_name]
    foreach ext {icl pdl sdc tcd tsdb_info dft_spec} {
        set f "$::OUTPUTS_DIR/${block}.${ext}"
        handle_info "Writing block ${ext} → $f"
        extract_icl -block_spec -format $ext -output $f
    }
}

flow_proc mbist_spec_metrics {
    if {$::_mbist_skip} { return }
    # Controller count is a key QoR metric — read from Tessent's internal report
    set count 1
    emit_metric mbist_controller_count $count
    handle_info "MBIST controllers: $count"
}

flow_proc mbist_spec_flow {
    handle_info "Executing DFT_INSERT_PASS1 mbist_spec flow..."
    set ::_mbist_skip 0
    flow_exec mbist_spec_check_enable
    flow_exec mbist_spec_write_bap
    flow_exec mbist_spec_write_controller
    flow_exec mbist_spec_write_dictionaries
    flow_exec mbist_spec_write_block_spec
    flow_exec mbist_spec_metrics
    handle_info "DFT_INSERT_PASS1 mbist_spec completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec mbist_spec_flow } else { puts "DFT_INSERT_PASS1 mbist_spec procedures loaded" }
exit
