#!/usr/bin/env tclsh
# CBflow DFT_INSERT_PASS1 sim — Mentor Tessent
# Simulation prep — writes simulation_data_dictionary for downstream VCS/Questa.
# This stage does NOT run simulation; it stages data for GLS_SCAN_MBIST.

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/dft_tessent_common.tcl"

set FLOW_TYPE "DFT_INSERT_PASS1"
set STAGE_NAME "sim"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------

flow_proc sim_write_data_dictionary {
    if {![string is true -strict $::dft_insert_pass1(sim,write_data_dictionary)]} {
        handle_info "sim,write_data_dictionary disabled — skipping"
        return
    }
    set out "$::OUTPUTS_DIR/simulation_data_dictionary"
    handle_info "Writing simulation data dictionary → $out"
    write_simulation_data_dictionary -output $out
}

flow_proc sim_flow {
    handle_info "Executing DFT_INSERT_PASS1 sim flow..."
    flow_exec sim_write_data_dictionary
    handle_info "DFT_INSERT_PASS1 sim completed"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec sim_flow } else { puts "DFT_INSERT_PASS1 sim procedures loaded" }
exit
