#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_CDC — cdc_setup (opensource / container tclsh)
# CDC set-up: the clocks from the staged SDC (cdc.sdc — opencdc reads SDC
# create_clock / groups) and the RTL as Verilog through sv2v (opencdc does not
# read SystemVerilog unpacked structs / packages) -> design_sv2v.v.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_CDC"
set STAGE_NAME "cdc_setup"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_RTL_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_rtl_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc setup {
    file copy -force [oss_input sdc] [oss_stage_out cdc.sdc]
    oss_run "$::REPORTS_DIR/sv2v.log" sh -c "sv2v [join [rtl_init_sources]] > [oss_stage_out design_sv2v.v]"
    set _fh [open [oss_stage_out cdc.sdc]]; set _t [read $_fh]; close $_fh
    handle_info "CDC clocks: [llength [regexp -all -inline {create_clock} $_t]] (from [file tail [oss_input sdc]])"
}

oss_exec_all
exit
