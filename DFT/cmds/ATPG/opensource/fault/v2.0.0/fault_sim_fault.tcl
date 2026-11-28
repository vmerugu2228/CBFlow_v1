#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — fault_sim (opensource / container tclsh)
# Independent stuck-at fault simulation of the generated pattern set on the
# ATPG model (cell-pin faults: every netlist net and cell input branch, both
# polarities; all patterns bit-parallel). atpg(oss,fault_sim,sample) N > 0
# simulates a random sample of N faults (coverage +- 95 % confidence).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "fault_sim"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc fault_sim {
    set _pg "[cbflow_node_dir [oss_chain_node pattern_gen]]/outputs"
    set _s [oss_get atpg oss,fault_sim,sample]
    dft_py "$::REPORTS_DIR/fsim.log" fsim --bench "$_pg/atpg.bench" --test "$_pg/atpg.test" \
        --map "$_pg/bench_map.json" --sample $_s -o "$::REPORTS_DIR/fault_sim.rpt" --json [oss_stage_out fault_sim.json]
    handle_info "pin fault coverage [dft_report_value $::REPORTS_DIR/fault_sim.rpt {Fault coverage}] %"
}

dft_exec_all
exit
