#!/usr/bin/env tclsh
# CBflow user_config — Bumblebee STA on Synopsys PrimeTime (persistent demo run)

# ── Project ──
set project(name)              "bumblebee"

# ── Flow ──
set flow(type)                 "STA"
set flow(design_name)          "cpu_core"
set flow(run_name)             "synopsys_demo"
set flow(run_type)             "hier"
set flow(test_mode)            "true"

# ── Tool (Synopsys) ──
set sta(tool,name)             "pt"

# ── MMMC (align with bumblebee's auto-generated views) ──
set sta(mmmc,scenario_set)     "signoff"

# ── Inputs (test_mode — placeholder paths, real EDA tool is bypassed) ──
set sta(input,netlist)         "/Users/vmerugu/projects/CBflow_clone/inputs/netlist.v"
set sta(input,sdc,func)        "/Users/vmerugu/projects/CBflow_clone/inputs/cpu_core_func.sdc"
set sta(input,sdc,test)        "/Users/vmerugu/projects/CBflow_clone/inputs/cpu_core_test.sdc"
set sta(input,def_file)        "/Users/vmerugu/projects/CBflow_clone/inputs/design.def"

# ── Execution ──
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
