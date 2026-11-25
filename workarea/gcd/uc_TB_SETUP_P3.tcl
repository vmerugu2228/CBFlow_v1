# gcd P3 — UVM testbench from the spec (RTL_SPEC SPEC_EXIT) on the lint-clean RTL (LINT_SIGNOFF)
set project(name)              "opensky"
set flow(design_name)          "gcd"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"
set project(phase)             "P3"
set project(release,phase)     "P3"
set project(lib_config_tag)    "OSS2"
set flow(type)                 "TB_SETUP"
set flow(run_name)             "p3_tb"
set tb_setup(tool,name)        "verilator"           ;# TB_SETUP_verilator_config.tcl (open-source UVM)
set tb_setup(input,release_tag)     "SPEC_EXIT"      ;# spec, register model, vPlan
set tb_setup(input,rtl_release_tag) "LINT_SIGNOFF"   ;# RTL filelist
set tb_setup(oss,tb_dir)       "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P3/tb/uvm"
