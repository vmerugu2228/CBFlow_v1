#!/usr/bin/env tclsh
# CBFlow DFT_INSERT release_data — Mentor Tessent

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DFT_INSERT"
set STAGE_NAME "release_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Shared release utilities (test_mode-aware)
set _rel "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_rel]} { source $_rel }

# ---------------------------------------------------------------------------
flow_proc release_dft_data {
    handle_info "Releasing DFT_INSERT deliverables..."
    if {[info commands ::CBFlow::Release::stage_release_data] ne ""} {
        ::CBFlow::Release::stage_release_data DFT_INSERT $run_dir
    } else {
        # Minimal fallback — write a release marker
        set fh [open "$::OUTPUTS_DIR/RELEASE.txt" "w"]
        puts $fh "DFT_INSERT release - [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
        close $fh
        handle_info "Release marker written"
    }
}

flow_proc release_data_flow {
    handle_info "Executing DFT_INSERT release_data flow..."
    flow_exec release_dft_data
    handle_info "DFT_INSERT release_data completed"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec release_data_flow } else { puts " DFT_INSERT release_data procedures loaded" }
exit
