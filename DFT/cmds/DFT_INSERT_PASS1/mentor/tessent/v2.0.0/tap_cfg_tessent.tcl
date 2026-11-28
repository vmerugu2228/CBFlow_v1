#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 tap_cfg — Mentor Tessent
# TAP controller configuration: pins (TCK/TMS/TDI/TDO/TRST), IR width, instructions.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "tap_cfg"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc tap_cfg_apply {
    handle_info "Applying TAP configuration..."
    set tck   $::dft_insert_pass1(tap,tck_pin)
    set tms   $::dft_insert_pass1(tap,tms_pin)
    set tdi   $::dft_insert_pass1(tap,tdi_pin)
    set tdo   $::dft_insert_pass1(tap,tdo_pin)
    set trst  $::dft_insert_pass1(tap,trst_pin)
    set irw   $::dft_insert_pass1(tap,ir_width)

    add_tap_controller TAP_CTRL -ir_width $irw \
        -tck  $tck \
        -tms  $tms \
        -tdi  $tdi \
        -tdo  $tdo \
        -trst $trst

    foreach inst $::dft_insert_pass1(tap,instructions) {
        add_tap_instruction $inst
    }
    handle_info "TAP configured: TCK=$tck TMS=$tms TDI=$tdi TDO=$tdo TRST=$trst IR=$irw"
}

flow_proc tap_cfg_summary {
    set rpt "$::REPORTS_DIR/tap_cfg.rpt"
    set fh [open $rpt "w"]
    puts $fh "TAP configuration — [dft_tessent_block_name]"
    puts $fh "Pins: TCK=$::dft_insert_pass1(tap,tck_pin) TMS=$::dft_insert_pass1(tap,tms_pin)"
    puts $fh "      TDI=$::dft_insert_pass1(tap,tdi_pin) TDO=$::dft_insert_pass1(tap,tdo_pin)"
    puts $fh "      TRST=$::dft_insert_pass1(tap,trst_pin)"
    puts $fh "IR width: $::dft_insert_pass1(tap,ir_width)"
    puts $fh "Instructions: $::dft_insert_pass1(tap,instructions)"
    close $fh
    handle_info "TAP cfg report: $rpt"
}

flow_proc tap_cfg_flow {
    handle_info "Executing DFT_INSERT_PASS1 tap_cfg flow..."
    flow_exec tap_cfg_apply
    flow_exec tap_cfg_summary
    handle_info "DFT_INSERT_PASS1 tap_cfg completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec tap_cfg_flow } else { puts "DFT_INSERT_PASS1 tap_cfg procedures loaded" }
exit
