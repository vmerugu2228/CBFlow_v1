#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_FUNC — coverage (opensource / container tclsh)
# Coverage: toggle coverage of gls_func(oss,dump_scope) from the simulation VCD
# (gls_func(oss,toggle,enable)), with the simulation result.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "GLS_FUNC"
set STAGE_NAME "coverage"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc coverage {
    set _arr [oss_flow_arr]
    set _rs "[cbflow_node_dir [oss_chain_node run_sim]]"
    set _l [list "GLS coverage — $::design_name ($::FLOW_TYPE)"]
    set _fh [open "$_rs/reports/run_sim.rpt"]; lappend _l [string trimright [read $_fh]]; close $_fh
    if {[is_true [oss_get $_arr oss,toggle,enable]]} {
        dft_py "$::REPORTS_DIR/toggle.log" toggle --vcd "$_rs/outputs/sim.vcd" -o "$::REPORTS_DIR/toggle.rpt"
        set _fh [open "$::REPORTS_DIR/toggle.rpt"]; lappend _l [string trimright [read $_fh]]; close $_fh
    } else {
        lappend _l "Toggle coverage: not collected (${_arr}(oss,toggle,enable) false)"
    }
    dft_write [oss_stage_out coverage.rpt] "[join $_l \n]\n"
    file copy -force [oss_stage_out coverage.rpt] "$::REPORTS_DIR/coverage.rpt"
}

dft_exec_all
exit
