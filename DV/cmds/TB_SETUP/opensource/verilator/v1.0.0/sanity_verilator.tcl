#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow TB_SETUP — sanity (opensource / container tclsh -> testbench)
# <design>_sanity_test x tb_setup(oss,sanity,seeds) seeds: every run must pass
# (UVM_ERROR / UVM_FATAL 0) -> reports/sanity.rpt (+ the uvmgen summary).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "TB_SETUP"
set STAGE_NAME "sanity"
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
flow_proc sanity {
    set _sim "[cbflow_node_dir [oss_chain_node compile]]/outputs/sim"
    set _n [oss_get tb_setup oss,sanity,seeds]
    dv_tool "$::REPORTS_DIR/regress.log" regress --sim $_sim --tests ${::design_name}_sanity_test --seeds $_n \
        --jobs $_n --timeout-s [oss_get tb_setup oss,sim,timeout_s] -o "$::WORK_DIR/regress"
    dv_tool "$::REPORTS_DIR/runsum.log" runsum --results "$::WORK_DIR/regress/results.csv" \
        --title "TB sanity — $::design_name" -o "$::REPORTS_DIR/sanity.rpt"
    set _fh [open "[cbflow_node_dir [oss_chain_node tb_gen]]/reports/tb_gen.rpt"]; set _g [read $_fh]; close $_fh
    set _fh [open "$::REPORTS_DIR/sanity.rpt" a]; puts $_fh "\n$_g"; close $_fh
    set _st [dv_status "$::REPORTS_DIR/sanity.rpt"]
    oss_write_file [oss_stage_out sanity.status] "$_st\n"
    if {$_st ne "PASS"} { error "sanity test failed — $::REPORTS_DIR/sanity.rpt" }
    handle_info "sanity PASS ($_n seed(s))"
}

oss_exec_all
exit
