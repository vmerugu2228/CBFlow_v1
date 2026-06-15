#!/usr/bin/env tclsh
# CBFlow DFT_INSERT dft_inserted_export — Mentor Tessent

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "dft_inserted_export"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc write_dft_rtl {
    handle_info "Writing DFT-inserted RTL..."
    set design $::flow(design_name)
    set out "$::OUTPUTS_DIR/${design}.dft.v"
    write_verilog $out
    handle_info "DFT-inserted RTL: $out"
}

flow_proc write_dft_manifest {
    set design $::flow(design_name)
    set manifest "$::OUTPUTS_DIR/dft_manifest.tcl"
    set fh [open $manifest "w"]
    puts $fh "# DFT_INSERT manifest - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "set dft_output(rtl)   \"$::OUTPUTS_DIR/${design}.dft.v\""
    puts $fh "set dft_output(mbist) \"$::OUTPUTS_DIR/${design}.mbist.v\""
    puts $fh "set dft_output(occ)   \"$::OUTPUTS_DIR/${design}.occ.v\""
    puts $fh "set dft_output(edt)   \"$::OUTPUTS_DIR/${design}.edt.v\""
    close $fh
    handle_info "DFT manifest: $manifest"
}

flow_proc dft_inserted_export_flow {
    handle_info "Executing DFT_INSERT dft_inserted_export flow..."
    flow_exec write_dft_rtl
    flow_exec write_dft_manifest
    handle_info "DFT_INSERT dft_inserted_export completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec dft_inserted_export_flow } else { puts " DFT_INSERT dft_inserted_export procedures loaded" }
exit
