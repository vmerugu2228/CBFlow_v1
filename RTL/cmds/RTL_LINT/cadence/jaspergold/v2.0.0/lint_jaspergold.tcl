#!/usr/bin/env tclsh
# CBflow RTL_LINT lint — cadence jaspergold (SCAFFOLD)
# Owner team: fill in jaspergold-specific commands.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE  "RTL_LINT"
set STAGE_NAME "lint"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc emit_lint_script {
    global rtl_lint run_dir NODE_NAME FLOW_TYPE
    handle_info "Emitting jaspergold lint stub..."
    set work "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run"
    set logdir "$run_dir/reports/rtl_lint"
    file mkdir $work $logdir
    set fh [open "$work/lint_jaspergold.tcl" w]
    puts $fh "# jaspergold lint — SCAFFOLD. Fill in real tool commands."
    puts $fh "exit"
    close $fh
    handle_info "  Wrote: $work/lint_jaspergold.tcl"
}

flow_proc lint_run { emit_lint_script }
lint_run
