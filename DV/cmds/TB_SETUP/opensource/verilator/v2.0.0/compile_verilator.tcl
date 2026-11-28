#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow TB_SETUP — compile (opensource / container tclsh -> verilator)
# The testbench built by Verilator (--binary --timing --coverage, UVM from
# UVM_HOME, ccache) -> outputs/sim.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "TB_SETUP"
set STAGE_NAME "compile"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_DV_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dv_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"
flow_proc build {
    set _tbf "[cbflow_node_dir [oss_chain_node tb_gen]]/outputs/tb/tb.f"
    set _sim [dv_build tb_setup $_tbf "$::WORK_DIR/build" "$::REPORTS_DIR/build.log"]
    file copy -force $_sim [oss_stage_out sim]
    handle_info "testbench built -> [oss_stage_out sim]"
}

oss_exec_all
exit
