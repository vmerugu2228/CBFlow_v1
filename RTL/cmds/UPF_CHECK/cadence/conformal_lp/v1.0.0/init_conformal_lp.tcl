#!/usr/bin/env tclsh
# CBflow UPF_CHECK init — cadence conformal_lp (SCAFFOLD)
# Owner team: fill in conformal_lp-specific commands.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE  "UPF_CHECK"
set STAGE_NAME "init"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc emit_init_script {
    global upf_check run_dir NODE_NAME FLOW_TYPE
    handle_info "Emitting conformal_lp init stub..."
    set work "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run"
    set logdir "$run_dir/reports/upf_check"
    file mkdir $work $logdir
    set fh [open "$work/init_conformal_lp.tcl" w]
    puts $fh "# conformal_lp init — SCAFFOLD. Fill in real tool commands."
    puts $fh "exit"
    close $fh
    handle_info "  Wrote: $work/init_conformal_lp.tcl"
}

flow_proc init_run { emit_init_script }
init_run
