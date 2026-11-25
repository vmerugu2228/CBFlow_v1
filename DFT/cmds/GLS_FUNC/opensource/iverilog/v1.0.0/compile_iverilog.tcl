#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_FUNC — compile (opensource / container tclsh → iverilog)
# Compile netlist + models + testbench (iverilog -g2012, FUNCTIONAL /
# UNIT_DELAY=#1 cell models, gls_func(oss,defines)).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "GLS_FUNC"
set STAGE_NAME "compile"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc compile {
    set _arr [oss_flow_arr]
    set _init "[cbflow_node_dir [oss_chain_node init_sim]]/outputs"
    set _fh [open "$_init/sim_files.txt"]; set _files [split [string trim [read $_fh]] \n]; close $_fh
    set _fh [open "$_init/sim_tops.txt"]; set _tops [split [string trim [read $_fh]] \n]; close $_fh
    set _d {}
    foreach _x [concat FUNCTIONAL UNIT_DELAY=#1 [oss_get_opt $_arr oss,defines]] { lappend _d "-D$_x" }
    set _s {}
    foreach _t $_tops { lappend _s -s $_t }
    dft_run "$::REPORTS_DIR/compile.log" iverilog -g2012 {*}$_d {*}$_s -o [oss_stage_out sim.vvp] {*}$_files
    handle_info "compiled [llength $_files] files (tops: $_tops)"
}

dft_exec_all
exit
