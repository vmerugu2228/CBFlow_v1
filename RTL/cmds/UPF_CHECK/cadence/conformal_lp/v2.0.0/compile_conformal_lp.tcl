#!/usr/bin/env tclsh
# CBflow UPF_CHECK compile — cadence conformal_lp (SCAFFOLD)
# Owner team: fill in conformal_lp-specific commands.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE  "UPF_CHECK"
set STAGE_NAME "compile"
set NODE_NAME  "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc emit_compile_script {
    global upf_check run_dir NODE_NAME FLOW_TYPE
    handle_info "Emitting conformal_lp compile stub..."
    set work "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run"
    set logdir "$run_dir/reports/upf_check"
    file mkdir $work $logdir
    set fh [open "$work/compile_conformal_lp.tcl" w]
    puts $fh "# conformal_lp compile — SCAFFOLD. Fill in real tool commands."
    puts $fh "exit"
    close $fh
    handle_info "  Wrote: $work/compile_conformal_lp.tcl"
}

flow_proc compile_run { emit_compile_script }
compile_run
