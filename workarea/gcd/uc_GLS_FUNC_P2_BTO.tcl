set project(name)              "opensky"
set flow(type)                 "GLS_FUNC"
set flow(design_name)          "gcd"
set flow(run_name)             "p2_gls_bto"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
set gls_func(tool,name)              "iverilog"       ;# GLS_FUNC_iverilog_config.tcl (open-source)
set gls_func(input,netlist_release_tag) "BTO"         ;# post-route netlist of the PNR BTO release
set gls_func(input,testbench)        "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P2/tb/gcd_gls_tb.v"
set gls_func(oss,tb_top)             "gcd_gls_tb"
set gls_func(oss,dump_scope)         "gcd_gls_tb.dut"
set gls_func(oss,defines)            {CBFLOW_CHECK_SRAM}
