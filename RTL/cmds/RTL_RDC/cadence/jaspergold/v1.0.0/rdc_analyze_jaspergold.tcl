#!/usr/bin/env tclsh
# CBflow RTL_RDC rdc_analyze — cadence jaspergold (SCAFFOLD)
# Owner team: fill in jaspergold-specific commands.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE  "RTL_RDC"
set STAGE_NAME "rdc_analyze"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc emit_rdc_analyze_script {
    global rtl_rdc run_dir NODE_NAME FLOW_TYPE
    handle_info "Emitting jaspergold rdc_analyze stub..."
    set work "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run"
    set logdir "$run_dir/reports/rtl_rdc"
    file mkdir $work $logdir
    set fh [open "$work/rdc_analyze_jaspergold.tcl" w]
    puts $fh "# jaspergold rdc_analyze — SCAFFOLD. Fill in real tool commands."
    puts $fh "exit"
    close $fh
    handle_info "  Wrote: $work/rdc_analyze_jaspergold.tcl"
}

flow_proc rdc_analyze_run { emit_rdc_analyze_script }
rdc_analyze_run
