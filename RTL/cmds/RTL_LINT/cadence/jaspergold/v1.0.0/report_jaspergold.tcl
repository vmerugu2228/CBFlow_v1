#!/usr/bin/env tclsh
# CBflow RTL_LINT report — cadence jaspergold (SCAFFOLD)
# Owner team: fill in jaspergold-specific commands.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE  "RTL_LINT"
set STAGE_NAME "report"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc emit_report_script {
    global rtl_lint run_dir NODE_NAME FLOW_TYPE
    handle_info "Emitting jaspergold report stub..."
    set work "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run"
    set logdir "$run_dir/reports/rtl_lint"
    file mkdir $work $logdir
    set fh [open "$work/report_jaspergold.tcl" w]
    puts $fh "# jaspergold report — SCAFFOLD. Fill in real tool commands."
    puts $fh "exit"
    close $fh
    handle_info "  Wrote: $work/report_jaspergold.tcl"
}

flow_proc report_run { emit_report_script }
report_run
