#!/usr/bin/env tclsh
# CBflow User Config — STA with Synopsys PT (2 corners only)
set project(name)        "ravendrive"
set project(phase)       "P0"
set flow(type)           "STA"
set flow(design_name)    "cpu_core"
set flow(run_name)       "pt_2corner"
set flow(test_mode)      "true"
set flow(use_lsf)        "true"
set flow(use_xterm)      "true"

# Tool: Synopsys PT (default for STA)
# No tool override needed — STA defaults to PT

# MMMC: Override to use only 2 corners (1 setup + 1 hold)
set sta(mmmc,scenario_set) "custom"
set sta(mmmc,setup_scenarios) "func_ss_0p76v_rcmax_150c"
set sta(mmmc,hold_scenarios)  "func_ff_0p84v_rcmin_m40c"

# Design Inputs
set sta(input,netlist)       "/Users/vmerugu/projects/CBflow_clone/netlist.v"
set sta(input,sdc_func_file) "/Users/vmerugu/projects/CBflow_clone/func.sdc"
