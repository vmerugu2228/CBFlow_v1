set project(name)              "opensky"
set flow(type)                 "GLS_SCAN_MBIST"
set flow(design_name)          "gcd"
set flow(run_name)             "p2_glsscan_bto"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
set gls_scan_mbist(tool,name)                 "iverilog"          ;# GLS_SCAN_MBIST_iverilog_config.tcl
set gls_scan_mbist(input,netlist_release_tag) "BTO"               ;# post-route netlist of the PNR BTO release
set gls_scan_mbist(input,patterns_release_tag) "ATPG_PREPD_EXIT"  ;# pre-PD ATPG serial-scan testbench
